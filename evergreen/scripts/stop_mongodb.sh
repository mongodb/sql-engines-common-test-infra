#!/bin/bash
#
# Stops the MongoDB deployment started by start_mongodb.sh. This is safe to call from a `post` block, i.e.
# in tasks that never started a deployment.

set -o errexit

if [[ -z "$DRIVERS_TOOLS" ]]; then
    echo >&2 "\$DRIVERS_TOOLS must be set"
    exit 1
fi

# drivers-evergreen-tools only creates this directory when it starts a deployment. Without it this task
# started none, and `run-mongodb.sh stop` would only spend time installing its own tooling.
if [[ ! -d "$DRIVERS_TOOLS/mongodb" ]]; then
    echo "No MongoDB deployment was started by this task, nothing to stop"
    exit 0
fi

echo "Stopping MongoDB using mongodb-runner (run-mongodb.sh)"
bash "$DRIVERS_TOOLS/.evergreen/run-mongodb.sh" stop
