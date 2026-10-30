#!/bin/bash
#
# Starts a MongoDB deployment using drivers-evergreen-tools: with mongodb-runner (run-mongodb.sh) if
# USE_MONGODB_RUNNER is "true", otherwise with mongo-orchestration (run-orchestration.sh). See the
# README. Use stop_mongodb.sh to stop it.

set -o errexit

if [[ -z "$DRIVERS_TOOLS" ]]; then
    echo >&2 "\$DRIVERS_TOOLS must be set"
    exit 1
fi

if [[ "$USE_MONGODB_RUNNER" == "true" ]]; then
    echo "Starting MongoDB using mongodb-runner (run-mongodb.sh)"
    bash "$DRIVERS_TOOLS/.evergreen/run-mongodb.sh" start
else
    echo "Starting MongoDB using mongo-orchestration (run-orchestration.sh)"
    sh "$DRIVERS_TOOLS/.evergreen/run-orchestration.sh"
fi
