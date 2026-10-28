#!/bin/bash
#
# Stops the MongoDB deployment started by start_mongodb.sh.
#
# By default this uses the legacy mongo-orchestration based stop_mongo_orchestration.sh. If
# USE_MONGODB_RUNNER is set to a non-empty value, this uses run-mongodb.sh instead.
#
# This is safe to call from a `post` block, i.e. in tasks that never started a deployment.

set -o errexit

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ -z "$USE_MONGODB_RUNNER" ]]; then
    echo "Stopping MongoDB using mongo-orchestration"
    sh "$SCRIPT_DIR/stop_mongo_orchestration.sh"
    exit 0
fi

if [[ -z "$DRIVERS_TOOLS" ]]; then
    echo >&2 "\$DRIVERS_TOOLS must be set"
    exit 1
fi

# drivers-evergreen-tools is cloned fresh by every task and only creates its mongodb directory (which
# holds the downloaded binaries) when it starts a deployment. If the directory does not exist then
# this task never started anything, and `run-mongodb.sh stop` would only spend time installing its
# own tooling.
if [[ ! -d "$DRIVERS_TOOLS/mongodb" ]]; then
    echo "No MongoDB deployment was started by this task, nothing to stop"
    exit 0
fi

echo "Stopping MongoDB using mongodb-runner (run-mongodb.sh)"
bash "$DRIVERS_TOOLS/.evergreen/run-mongodb.sh" stop
