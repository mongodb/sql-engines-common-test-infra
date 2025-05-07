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
LOCAL_INSTALL_DIR=$(pwd)/local_adf
LOGS_PATH=$LOCAL_INSTALL_DIR/logs
DB_CONFIG_PATH=$(pwd)/test-environment/configuration/adf_db_config.json
# This config enables match filters after currentOp
ADF_CONFIG_PATH=$(pwd)/test-environment/configuration/adf_config.yaml
MONGOD_PORT=28017
MONGOHOUSED_PORT=27017
START="start"
STOP="stop"
MONGOD="mongod"
MONGOHOUSED="mongohoused"
TENANT_CONFIG="./testdata/config/inline_local/tenant-config.json"

OS=$(uname)
if [[ $OS =~ ^CYGWIN ]]; then
    TMP_DIR="C:\\temp\\run_adf"
else
    TMP_DIR="/tmp/run_adf"
fi
TIMEOUT=180
JQ=$TMP_DIR/jq


## OS Agnostic definitions
MONGOSH_DOWNLOAD_BASE=https://downloads.mongodb.com/compass

# Shared Linux mongosh
MONGOSH_DOWNLOAD_LINUX_FILE=mongosh-1.8.0-linux-x64.tgz
MONGOSH_DOWNLOAD_LINUX_ARM_FILE=mongosh-1.8.0-linux-arm64.tgz

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
  VERSION=`$MONGOSH_DOWNLOAD_DIR/bin/mongosh --port $1 --eval 'db.version()'`
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

check_mongohoused() {
  check_version $MONGOHOUSED_PORT
  return $?
}

# check if mac or linux
if [ $OS = "Linux" ]; then
  distro=$(awk -F= '/^NAME/{print $2}' /etc/os-release)
  if [ "$distro" = "\"Red Hat Enterprise Linux\"" ] ||
    [ "$distro" = "\"Red Hat Enterprise Linux Server\"" ]; then
    if [ "$MACHINE_ARCH" = "aarch64" ]; then
      export VARIANT=rhel9
      MONGOSH_DOWNLOAD_FILE=$MONGOSH_DOWNLOAD_LINUX_ARM_FILE
    else
      export VARIANT=rhel7
      MONGOSH_DOWNLOAD_FILE=$MONGOSH_DOWNLOAD_LINUX_FILE
    fi
    MONGOSH_DOWNLOAD_LINK=$MONGOSH_DOWNLOAD_BASE/$MONGOSH_DOWNLOAD_FILE
  elif [ "$distro" = "\"Ubuntu\"" ]; then
    export VARIANT=ubuntu2204
    if [ "$MACHINE_ARCH" = "aarch64" ]; then
      MONGOSH_DOWNLOAD_FILE=$MONGOSH_DOWNLOAD_LINUX_ARM_FILE
    else
      MONGOSH_DOWNLOAD_FILE=$MONGOSH_DOWNLOAD_LINUX_FILE
    fi
    MONGOSH_DOWNLOAD_LINK=$MONGOSH_DOWNLOAD_BASE/$MONGOSH_DOWNLOAD_FILE
  elif [ "$distro" = "\"Amazon Linux\"" ] && [ "$MACHINE_ARCH" = "aarch64" ]; then
    export VARIANT=amazon2
    MONGOSH_DOWNLOAD_FILE=$MONGOSH_DOWNLOAD_LINUX_ARM_FILE
    MONGOSH_DOWNLOAD_LINK=$MONGOSH_DOWNLOAD_BASE/$MONGOSH_DOWNLOAD_FILE
  else
    echo ${distro} not supported
    exit 1
  fi
elif [ $OS = "Darwin" ]; then
  if [ "$MACHINE_ARCH" = "x86_64" ]; then
    MONGOSH_DOWNLOAD_FILE=$MONGOSH_DOWNLOAD_MAC_FILE
    MONGOSH_DOWNLOAD_LINK=$MONGOSH_DOWNLOAD_BASE/$MONGOSH_DOWNLOAD_FILE
  else
    MONGOSH_DOWNLOAD_FILE=$MONGOSH_DOWNLOAD_MAC_FILE_ARM
    MONGOSH_DOWNLOAD_LINK=$MONGOSH_DOWNLOAD_BASE/$MONGOSH_DOWNLOAD_FILE
  fi
elif [[ $OS =~ ^CYGWIN ]]; then
  MONGOSH_DOWNLOAD_FILE=$MONGOSH_DOWNLOAD_WINDOWS_FILE
  MONGOSH_DOWNLOAD_LINK=$MONGOSH_DOWNLOAD_BASE/$MONGOSH_DOWNLOAD_FILE
else
  echo $(uname) not supported
  exit 1
fi

# SQL-2814: Use the mongosh binary that is installed by mongo-orchestration/drivers-evergreen-tools
install_mongosh() {
    (cd $LOCAL_INSTALL_DIR && curl -O $MONGOSH_DOWNLOAD_LINK)
    if [[ $OS =~ ^CYGWIN ]]; then
      unzip -qo $LOCAL_INSTALL_DIR/$MONGOSH_DOWNLOAD_FILE -d $LOCAL_INSTALL_DIR 2> /dev/null

      # Obtain unzipped directory name
      MONGOSH_UNZIP_DIR=$(unzip -lq $LOCAL_INSTALL_DIR/$MONGOSH_DOWNLOAD_FILE | grep mongosh.exe | tr -s ' ' \
              | cut -d ' ' -f 5 | cut -d/ -f1)
      chmod -R +x $LOCAL_INSTALL_DIR/$MONGOSH_UNZIP_DIR/bin/
      echo $LOCAL_INSTALL_DIR/$MONGOSH_UNZIP_DIR
    elif [ $OS = "Darwin" ]; then
      unzip -qo $LOCAL_INSTALL_DIR/$MONGOSH_DOWNLOAD_FILE -d $LOCAL_INSTALL_DIR 2> /dev/null
      echo $LOCAL_INSTALL_DIR/${MONGOSH_DOWNLOAD_FILE:0:$((${#MONGOSH_DOWNLOAD_FILE} - 4))}
    else
      tar zxf $LOCAL_INSTALL_DIR/$MONGOSH_DOWNLOAD_FILE --directory $LOCAL_INSTALL_DIR
      echo $LOCAL_INSTALL_DIR/${MONGOSH_DOWNLOAD_FILE:0:$((${#MONGOSH_DOWNLOAD_FILE} - 4))}
    fi
}

MONGOSH_DOWNLOAD_DIR=$(install_mongosh)

if [ $ARG = $START ]; then
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

    # Replace the existing storage config with a wildcard collection for the local mongodb
    cp ${TENANT_CONFIG} ${TENANT_CONFIG}.orig
    $JQ "del(.storage)" ${TENANT_CONFIG} > ${TENANT_CONFIG}.tmp && mv ${TENANT_CONFIG}.tmp ${TENANT_CONFIG}
    $JQ --argjson obj "$STORES" '.storage.stores += [$obj]' ${TENANT_CONFIG} > ${TENANT_CONFIG}.tmp\
                                                               && mv ${TENANT_CONFIG}.tmp ${TENANT_CONFIG}
    $JQ --argjson obj "$DATABASES" '.storage.databases += $obj' ${TENANT_CONFIG} > ${TENANT_CONFIG}.tmp\
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
