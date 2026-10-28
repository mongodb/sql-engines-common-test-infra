#!/bin/bash
set -o errexit
# Starts a mongod compute node for ADF integration tests that require it.
# start_mongodb.sh (or ${DRIVERS_TOOLS}/.evergreen/run-orchestration.sh) must be run before this
# script to set up the mongod binary and directory.

if [[ -z "$DRIVERS_TOOLS" ]]; then
    echo >&2 "Error: The \$DRIVERS_TOOLS environment variable must be set."
    exit 1
fi

export COMPUTE_MODE_MONGOD_PORT=${COMPUTE_MODE_MONGOD_PORT:-47017}

echo "Starting mongod compute node on port $COMPUTE_MODE_MONGOD_PORT..."

MONGOD="$DRIVERS_TOOLS/mongodb/bin/mongod"
# When a deployment is started with mongodb-runner (USE_MONGODB_RUNNER), drivers-evergreen-tools
# replaces mongod with a shell script that logs the server's output and keeps the real binary as
# mongod-real. That script always exits with the status of the logging pipeline rather than
# mongod's, which would hide a failure to start the compute node, so run the real binary instead.
if [[ -x "$MONGOD-real" ]]; then
    MONGOD="$MONGOD-real"
fi

COMPUTE_NODE_DIR=/tmp/compute_node
mkdir -p "$COMPUTE_NODE_DIR"
"$MONGOD" --port "$COMPUTE_MODE_MONGOD_PORT" \
                                  --setParameter enableComputeMode=1 \
                                  --dbpath "$COMPUTE_NODE_DIR" \
                                  --logpath "$COMPUTE_NODE_DIR/mongod.log" \
                                  --fork

echo "Successfully launched mongod compute node."
