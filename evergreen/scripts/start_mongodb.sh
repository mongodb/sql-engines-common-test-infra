#!/bin/bash
#
# Starts a MongoDB deployment with drivers-evergreen-tools' mongodb-runner (run-mongodb.sh). On hosts
# where the runner can't be installed, drivers-evergreen-tools falls back to mongo-orchestration itself.
# Use stop_mongodb.sh to stop it.

set -o errexit

if [[ -z "$DRIVERS_TOOLS" ]]; then
    echo >&2 "\$DRIVERS_TOOLS must be set"
    exit 1
fi

echo "Starting MongoDB using mongodb-runner (run-mongodb.sh)"
bash "$DRIVERS_TOOLS/.evergreen/run-mongodb.sh" start
