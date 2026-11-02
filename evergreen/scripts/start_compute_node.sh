#!/bin/bash
set -o errexit
# Starts a mongod compute node for ADF integration tests that require it.
# start_mongodb.sh must be run before this script to set up the mongod binary and directory.

if [[ -z "$DRIVERS_TOOLS" ]]; then
    echo >&2 "Error: The \$DRIVERS_TOOLS environment variable must be set."
    exit 1
fi

export COMPUTE_MODE_MONGOD_PORT=${COMPUTE_MODE_MONGOD_PORT:-47017}

echo "Starting mongod compute node on port $COMPUTE_MODE_MONGOD_PORT..."

MONGOD="$DRIVERS_TOOLS/mongodb/bin/mongod"
# With mongodb-runner, DET wraps mongod in a script that hides its exit status, so run mongod-real if
# it exists (DRIVERS-3673 tracks removing the wrapper).
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
