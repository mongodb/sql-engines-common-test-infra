#!/bin/bash
#
# Stops the MongoDB deployment started by start_mongodb.sh. With mongodb-runner (USE_MONGODB_RUNNER is
# "true") this is safe to call from a `post` block, i.e. in tasks that never started a deployment.

set -o errexit

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ "$USE_MONGODB_RUNNER" != "true" ]]; then
    echo "Stopping MongoDB using mongo-orchestration"
    sh "$SCRIPT_DIR/stop_mongo_orchestration.sh"
elif [[ -z "$DRIVERS_TOOLS" ]]; then
    echo >&2 "\$DRIVERS_TOOLS must be set"
    exit 1
# drivers-evergreen-tools only creates this directory when it starts a deployment. Without it this task
# started none, and `run-mongodb.sh stop` would only spend time installing its own tooling.
elif [[ ! -d "$DRIVERS_TOOLS/mongodb" ]]; then
    echo "No MongoDB deployment was started by this task, nothing to stop"
else
    echo "Stopping MongoDB using mongodb-runner (run-mongodb.sh)"
    bash "$DRIVERS_TOOLS/.evergreen/run-mongodb.sh" stop
fi
