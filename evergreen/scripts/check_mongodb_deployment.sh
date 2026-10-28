#!/bin/bash
#
# Checks the state of the MongoDB deployment managed by start_mongodb.sh and stop_mongodb.sh.
#
# Usage: check_mongodb_deployment.sh <running|stopped>
#
# Environment:
#   DRIVERS_TOOLS       (required) path to the drivers-evergreen-tools directory
#   MDB_TEST_LOCAL_PORT port of the deployment (default: 28017, see update_orchestrator_mongod_port.sh)
#   MONGODB_VERSION     if this is a major.minor version (e.g. 6.0), the running server must match it
#
# `running` also checks that the mongod and mongosh binaries are in $DRIVERS_TOOLS/mongodb/bin, since
# other scripts in this repo (run_adf.sh, start_compute_node.sh) and the SQL Engines projects rely
# on that layout.

set -o errexit
set -o pipefail

fail() {
    echo >&2 "FAILED: $*"
    exit 1
}

STATE="$1"
if [[ "$STATE" != "running" && "$STATE" != "stopped" ]]; then
    echo >&2 "Usage: $(basename "$0") <running|stopped>"
    exit 1
fi

if [[ -z "$DRIVERS_TOOLS" ]]; then
    fail "\$DRIVERS_TOOLS must be set"
fi

BIN_DIR="$DRIVERS_TOOLS/mongodb/bin"
PORT="${MDB_TEST_LOCAL_PORT:-28017}"

# Prints the path of the named binary in BIN_DIR, if it exists.
find_binary() {
    if [[ -x "$BIN_DIR/$1" ]]; then
        echo "$BIN_DIR/$1"
    elif [[ -x "$BIN_DIR/$1.exe" ]]; then
        echo "$BIN_DIR/$1.exe"
    fi
}

MONGOD=$(find_binary mongod)
MONGOSH=$(find_binary mongosh)

if [[ "$STATE" == "running" ]]; then
    [[ -n "$MONGOD" ]] || fail "mongod not found in $BIN_DIR"
    [[ -n "$MONGOSH" ]] || fail "mongosh not found in $BIN_DIR"

    VERSION=$("$MONGOSH" --quiet --port "$PORT" --eval 'db.version()' | tr -d '\r') ||
        fail "no mongod is responding on port $PORT"
    echo "mongod $VERSION is running on port $PORT"

    # Not asserted on, but handy for comparing deployments started by mongo-orchestration and by
    # mongodb-runner.
    echo "Command line options:"
    "$MONGOSH" --quiet --port "$PORT" --eval 'JSON.stringify(db.adminCommand({getCmdLineOpts: 1}).parsed)'

    if [[ "$MONGODB_VERSION" =~ ^[0-9]+\.[0-9]+$ && "$VERSION" != "$MONGODB_VERSION".* ]]; then
        fail "expected mongod $MONGODB_VERSION but found $VERSION"
    fi
else
    if [[ -n "$MONGOSH" ]] && "$MONGOSH" --quiet --port "$PORT" --eval 'db.version()' >/dev/null 2>&1; then
        fail "a mongod is still responding on port $PORT"
    fi

    # mongodb-runner based deployments run mongod as mongod-real (see start_compute_node.sh). We
    # cannot see native Windows processes from cygwin, so only check on other platforms.
    if [[ "$(uname)" != CYGWIN* ]] && pgrep -l -x 'mongod|mongod-real|mongos|mongos-real'; then
        fail "mongod or mongos processes are still running"
    fi
    echo "No MongoDB deployment is running"
fi
