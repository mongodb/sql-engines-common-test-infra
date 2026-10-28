#!/bin/bash
#
# Starts a MongoDB deployment using drivers-evergreen-tools.
#
# By default this uses the legacy mongo-orchestration based run-orchestration.sh. If
# USE_MONGODB_RUNNER is set to a non-empty value, this uses run-mongodb.sh instead, which is backed by
# mongodb-runner. The deployment is configured by the environment variables that
# drivers-evergreen-tools understands (TOPOLOGY, MONGODB_VERSION, MONGODB_BINARIES, ...).
#
# Use stop_mongodb.sh to stop the deployment.

set -o errexit

if [[ -z "$DRIVERS_TOOLS" ]]; then
    echo >&2 "\$DRIVERS_TOOLS must be set"
    exit 1
fi

if [[ -n "$USE_MONGODB_RUNNER" ]]; then
    echo "Starting MongoDB using mongodb-runner (run-mongodb.sh)"
    bash "$DRIVERS_TOOLS/.evergreen/run-mongodb.sh" start
else
    echo "Starting MongoDB using mongo-orchestration (run-orchestration.sh)"
    sh "$DRIVERS_TOOLS/.evergreen/run-orchestration.sh"
fi
