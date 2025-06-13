#!/bin/bash
set -o errexit
# Starts a mongod compute node for ADF integration tests that require it.
# ${DRIVERS_TOOLS}/.evergreen/run-orchestration.sh must be run before this script to set up
# the mongod binary and directory.

if [[ -z "$DRIVERS_TOOLS" ]]; then
    echo >&2 "Error: The \$DRIVERS_TOOLS environment variable must be set."
    exit 1
fi

export COMPUTE_MODE_MONGOD_PORT=${COMPUTE_MODE_MONGOD_PORT:-47017}

echo "Starting mongod compute node on port $COMPUTE_MODE_MONGOD_PORT..."

COMPUTE_NODE_DIR=/tmp/compute_node
mkdir -p "$COMPUTE_NODE_DIR"
"$DRIVERS_TOOLS/mongodb/bin/mongod" --port "$COMPUTE_MODE_MONGOD_PORT" \
                                  --setParameter enableComputeMode=1 \
                                  --dbpath "$COMPUTE_NODE_DIR" \
                                  --logpath "$COMPUTE_NODE_DIR/mongod.log" \
                                  --fork

echo "Successfully launched mongod compute node."

