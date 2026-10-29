#!/bin/bash
#
# Checks that the MongoDB deployment managed by start_mongodb.sh and stop_mongodb.sh is `running` or
# `stopped`. Usage: check_mongodb_deployment.sh <running|stopped>
#
# Uses DRIVERS_TOOLS (required), MDB_TEST_LOCAL_PORT (default 28017, as in
# update_orchestrator_mongod_port.sh) and MONGODB_VERSION (if it is major.minor, e.g. 6.0, the running
# server must match it). `running` also checks that mongod and mongosh are in $DRIVERS_TOOLS/mongodb/bin,
# which run_adf.sh, start_compute_node.sh and the projects rely on.

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

MONGOSH=$(find_binary mongosh)

if [[ "$STATE" == "running" ]]; then
    [[ -n "$(find_binary mongod)" ]] || fail "mongod not found in $BIN_DIR"
    [[ -n "$MONGOSH" ]] || fail "mongosh not found in $BIN_DIR"

    VERSION=$("$MONGOSH" --quiet --port "$PORT" --eval 'db.version()' | tr -d '\r') ||
        fail "no mongod is responding on port $PORT"
    echo "mongod $VERSION is running on port $PORT"

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
