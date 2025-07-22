#!/bin/bash
#
# Usage: run_adf.sh <operation>
# operation: 'start' or 'stop'
#
# This script will start a local mongod and Atlas Data Federation instance, used for integration testing.
# The supported platforms are windows, macos, ubuntu1804, and rhel7.
#
# - To skip the download of ADF, set the environment variable HAVE_LOCAL_MONGOHOUSE to 1
#   and set the environment variable LOCAL_MONGOHOUSE_DIR to the root directory of the
#   mongohouse source tree.
# - To skip the operations of this script, set the environment variable SKIP_RUN_ADF to 1.

NAME=`basename "$0"`
if [[ $SKIP_RUN_ADF -eq 1 ]]; then
  echo "Skipping $NAME"
  exit 0
fi

ARG=`echo $1 | tr '[:upper:]' '[:lower:]'`
if [[ -z $ARG ]]; then
  echo "Usage: $NAME <operation>"
  echo "operation: 'start' or 'stop'"
  exit 0
fi

GO_VERSION="go1.22"
if [ -d "/opt/golang/$GO_VERSION" ]; then
  GOROOT="/opt/golang/$GO_VERSION"
  GOBINDIR="$GOROOT"/bin
elif [ -d "C:\\golang\\$GO_VERSION" ]; then
  GOROOT="C:\\golang\\$GO_VERSION"
  GOBINDIR="$GOROOT"\\bin
  export GOCACHE=$(cygpath -m $HOME/gocache)
  export GOPATH=$(cygpath -m $HOME/go)
# local testing macos
elif [ -e /usr/local/bin/go ]; then
  GOBINDIR=/usr/local/bin
elif [ -e /opt/homebrew/bin/go ]; then
  GOBINDIR=/opt/homebrew/bin
# local testing ubuntu
elif [ -e /home/linuxbrew/.linuxbrew/bin/go ]; then
  GOBINDIR=/home/linuxbrew/.linuxbrew/bin
else #local testing
  GOBINDIR=/usr/bin
fi

GO="$GOBINDIR/go"

PATH=$GOBINDIR:$PATH

# GITHUB_TOKEN must be set for cloning 10gen/mongohouse repository from Evergreen hosts, and the
# dependencies needed to build it.
# If unset, it will default to using the SSH private key on the local system.
if [[ ${GITHUB_TOKEN} ]]; then
  # Clear git url configurations if they exist
  git config --global --get-regexp '^url\.' | while read -r key _; do
      git config --global --unset "$key"
  done

  MONGOHOUSE_URI=https://x-access-token:${GITHUB_TOKEN}@github.com/10gen/mongohouse.git
  git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/10gen/".insteadOf https://github.com/10gen/

else
  MONGOHOUSE_URI=git@github.com:10gen/mongohouse.git
  git config --global url.git@github.com:.insteadOf https://github.com/
fi

MACHINE_ARCH=$(uname -m)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
LOCAL_INSTALL_DIR=$SCRIPT_DIR/local_adf
LOGS_PATH=$LOCAL_INSTALL_DIR/logs
DB_CONFIG_PATH=$SCRIPT_DIR/configuration/adf_db_config.json
USERS_CONFIG_PATH=$SCRIPT_DIR/configuration/adf_users_config.json
# This config enables match filters after currentOp
ADF_CONFIG_PATH=$SCRIPT_DIR/configuration/adf_config.yaml
MONGOD_PORT=28017
MONGOHOUSED_PORT=27017
START="start"
STOP="stop"
MONGOD="mongod"
MONGOHOUSED="mongohoused"
TENANT_CONFIG="./testdata/config/inline_local/tenant-config.json"

# Locate and validate mongosh executable
MONGOSH_EXECUTABLE=""
if [[ -n "$DRIVERS_TOOLS" ]]; then
  # Try $DRIVERS_TOOLS first
  MONGOSH_PATH="$DRIVERS_TOOLS/mongodb/bin/mongosh"
  if [[ -x "$MONGOSH_PATH" ]]; then
    MONGOSH_EXECUTABLE="$MONGOSH_PATH"
  elif [[ "$OS" =~ ^CYGWIN && -x "$MONGOSH_PATH.exe" ]]; then
    MONGOSH_EXECUTABLE="$MONGOSH_PATH.exe"
  fi
fi
if [[ -z "$MONGOSH_EXECUTABLE" ]]; then
  MONGOSH_EXECUTABLE=$(command -v mongosh 2>/dev/null || command -v mongosh.exe 2>/dev/null)
fi
if [[ -x "$MONGOSH_EXECUTABLE" ]]; then
  "$MONGOSH_EXECUTABLE" --version &>/dev/null
  MONGOSH="$MONGOSH_EXECUTABLE"
else
  echo "Error: mongosh not found or not executable" >&2
  exit 1
fi

OS=$(uname)
if [[ $OS =~ ^CYGWIN ]]; then
    TMP_DIR="C:\\temp\\run_adf"
else
    TMP_DIR="/tmp/run_adf"
fi
# Set Variant needed for downloading mongosql library
if [[ "$OS" == "Linux" ]]; then
  distro=$(awk -F= '/^NAME/{print $2}' /etc/os-release)
  if [[ "$distro" == "\"Red Hat Enterprise Linux\"" || "$distro" == "\"Red Hat Enterprise Linux Server\"" ]]; then
    if [[ "$MACHINE_ARCH" == "aarch64" ]]; then
      export VARIANT=rhel9
    else
      export VARIANT=rhel7
    fi
  elif [[ "$distro" == "\"Ubuntu\"" ]]; then
    export VARIANT=ubuntu2204
  elif [[ "$distro" == "\"Amazon Linux\"" && "$MACHINE_ARCH" == "aarch64" ]]; then
    export VARIANT=amazon2
  else
    echo "$distro not supported"
    exit 1
  fi
fi

TIMEOUT=180
JQ=$TMP_DIR/jq

mkdir -p $LOCAL_INSTALL_DIR

check_procname() {
  ps -ef 2>/dev/null | grep $1 | grep -v grep >/dev/null
  result=$?

  if [[ result -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

check_version() {
  VERSION=`$MONGOSH --port $1 --eval 'db.version()'`
  result=$?
  VERSION=$(echo $VERSION | tail -n 1)
  echo "check_version() output"
  echo $VERSION

  if [[ result -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

# Check if jq exists.  If not, download and set path
get_jq() {
  if [ $OS = "Linux" ]; then
    if [ "$MACHINE_ARCH" = "aarch64" ]; then
      curl -L -o $JQ https://mongosql-noexpire.s3.us-east-2.amazonaws.com/run_adf/jq-linx-arm
    else
      curl -L -o $JQ https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
    fi
  elif [ $OS = "Darwin" ]; then
    curl -L -o $JQ https://github.com/stedolan/jq/releases/download/jq-1.6/jq-osx-amd64
  else
    curl -L -o $JQ https://github.com/stedolan/jq/releases/download/jq-1.6/jq-win64.exe
  fi
  chmod +x $JQ
}

check_mongod() {
  check_procname $MONGOD
  process_check_result=$?
  check_version $MONGOD_PORT
  port_check_result=$?

  if [[ $process_check_result -eq 0 ]] && [[ $port_check_result -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

check_mongohoused() {
  check_version $MONGOHOUSED_PORT
  return $?
}

if [ $ARG = $START ]; then
  check_mongod
  check_mongohoused
  if [[ $? -ne 0 ]]; then
    echo "Starting $MONGOHOUSED"
    $GO version

    if [[ $HAVE_LOCAL_MONGOHOUSE -eq 1 ]]; then
        if [ ! -d "$LOCAL_MONGOHOUSE_DIR" ]; then
            echo "ERROR: $LOCAL_MONGOHOUSE_DIR is not a directory"
            exit 1
        fi
        cd $LOCAL_MONGOHOUSE_DIR
    else
        echo "Downloading mongohouse"
        if [[ $OS =~ ^CYGWIN ]]; then
          MONGOHOUSE_DIR=$(cygpath -m $LOCAL_INSTALL_DIR/mongohouse)
        else
          MONGOHOUSE_DIR=$LOCAL_INSTALL_DIR/mongohouse
        fi
        # Install and start mongohoused
        # Clone the mongohouse repo
        if [ ! -d "$MONGOHOUSE_DIR" ]; then
            git clone $MONGOHOUSE_URI $MONGOHOUSE_DIR
            cd $MONGOHOUSE_DIR

            cd -
        fi
        cd $MONGOHOUSE_DIR

        export GOPRIVATE=github.com/10gen
        # make sure mod vendor is cleaned up
        $GO mod vendor
        $GO mod download
    fi

    # Set relevant environment variables
    export MONGOHOUSE_ENVIRONMENT="local"
    if [[ $OS =~ ^CYGWIN ]]; then
      export LIBRARY_PATH=$(cygpath -m $(pwd)/artifacts)
      MONGOSQL_LIB=$(cygpath -m $(pwd)/mongosql.dll)
    else
      export LIBRARY_PATH="$(pwd)/artifacts"
      MONGOSQL_LIB=$(pwd)/artifacts/libmongosql.a
    fi

    # Download latest versions of external dependencies
    if [[ $HAVE_LOCAL_MONGOHOUSE -eq 1 && -f "$MONGOSQL_LIB" ]]; then
        cp ${MONGOSQL_LIB} ${MONGOSQL_LIB}.orig
    fi
    rm -f $MONGOSQL_LIB
    $GO run cmd/buildscript/build.go tools:download:mongosql

    mkdir -p $TMP_DIR
    get_jq

    # Load tenant config into mongodb
    STORES='{ "name" : "localmongo", "provider" : "mongodb", "uri" : "mongodb://localhost:%s" }'
    STORES=$(printf "$STORES" "${MONGOD_PORT}")
    DATABASES=$(cat $DB_CONFIG_PATH)
    # add a user that only has read role for db2, it will have the same password 'pencil' as mhuser
    USERS=$(cat $USERS_CONFIG_PATH)

    echo "!!!!!!!!"
    echo "$USERS"
    echo "!!!!!!!!"

    # Replace the existing storage config with a wildcard collection for the local mongodb
    cp ${TENANT_CONFIG} ${TENANT_CONFIG}.orig
    $JQ "del(.storage)" ${TENANT_CONFIG} > ${TENANT_CONFIG}.tmp && mv ${TENANT_CONFIG}.tmp ${TENANT_CONFIG}
    $JQ --argjson obj "$STORES" '.storage.stores += [$obj]' ${TENANT_CONFIG} > ${TENANT_CONFIG}.tmp\
                                                               && mv ${TENANT_CONFIG}.tmp ${TENANT_CONFIG}
    $JQ --argjson obj "$DATABASES" '.storage.databases += $obj' ${TENANT_CONFIG} > ${TENANT_CONFIG}.tmp\
                                                               && mv ${TENANT_CONFIG}.tmp ${TENANT_CONFIG}
    $JQ --argjson obj "$USERS" '.security.users += $obj' ${TENANT_CONFIG} > ${TENANT_CONFIG}.tmp\
                                                               && mv ${TENANT_CONFIG}.tmp ${TENANT_CONFIG}

    $GO run cmd/buildscript/build.go init:mongodb-tenant

    mkdir -p $LOGS_PATH
    # Start mongohoused with appropriate config
    if [[ $OS =~ ^CYGWIN ]]; then
      $GO run -tags mongosql ./cmd/mongohoused/mongohoused.go \
        --config $(cygpath -m ${ADF_CONFIG_PATH}) >> $LOGS_PATH/${MONGOHOUSED}.log &
      echo $! > $TMP_DIR/${MONGOHOUSED}.pid
    else
      $GO run -tags mongosql ./cmd/mongohoused/mongohoused.go \
        --config $ADF_CONFIG_PATH >> $LOGS_PATH/${MONGOHOUSED}.log &
      echo $! > $TMP_DIR/${MONGOHOUSED}.pid
    fi

    waitCounter=0
    while : ; do
        check_mongohoused
        if [[ $? -eq 0 ]]; then
            break
        fi
        if [[ "$waitCounter" -gt $TIMEOUT ]]; then
            echo "ERROR: Local ADF did not start under $TIMEOUT seconds"
            exit 1
        fi
        let waitCounter=waitCounter+1
        sleep 1
    done
  fi
fi
if [ $ARG = $STOP ]; then
  MONGOHOUSED_PID=$(< $TMP_DIR/${MONGOHOUSED}.pid)
  echo "Stopping $MONGOHOUSED, pid $MONGOHOUSED_PID"

  if [[ $OS =~ ^CYGWIN ]]; then
    ps -W | grep $MONGOHOUSED | sed 's/   */:/g' | cut -d: -f5 | xargs -l taskkill /F /PID
  else
    pkill -TERM -P ${MONGOHOUSED_PID}
  fi
  if [[ $HAVE_LOCAL_MONGOHOUSE -eq 1 && -d "$LOCAL_MONGOHOUSE_DIR" ]]; then
      echo "Restoring ${TENANT_CONFIG}"
      cd $LOCAL_MONGOHOUSE_DIR
      mv ${TENANT_CONFIG}.orig ${TENANT_CONFIG}
      MONGOSQL_LIB=$LOCAL_MONGOHOUSE_DIR/artifacts/libmongosql.a
      if [[ -f ${MONGOSQL_LIB}.orig ]] ; then
          echo "Restoring $MONGOSQL_LIB"
          mv ${MONGOSQL_LIB}.orig $MONGOSQL_LIB
      fi
  fi
fi
