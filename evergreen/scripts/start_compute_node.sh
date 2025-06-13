#!/bin/bash

set -o errexit

if [[ -z "$DRIVERS_TOOLS" ]]; then
    echo >&2 "Error: The \$DRIVERS_TOOLS environment variable must be set."
    exit 1
fi

export COMPUTE_MODE_MONGOD_PORT=${COMPUTE_MODE_MONGOD_PORT:-47017}

echo "Starting mongod compute node on port $COMPUTE_MODE_MONGOD_PORT..."

mkdir -p "$DRIVERS_TOOLS/mongodb/compute_node"
"$DRIVERS_TOOLS/mongodb/bin/mongod" --port "$COMPUTE_MODE_MONGOD_PORT" \
                                  --setParameter enableComputeMode=1 \
                                  --dbpath "$DRIVERS_TOOLS/mongodb/compute_node" \
                                  --logpath "$DRIVERS_TOOLS/mongodb/compute_node/mongod.log" \
                                  --fork

echo "Successfully launched mongod compute node."