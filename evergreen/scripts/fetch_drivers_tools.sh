#!/bin/bash

set -o errexit

if [[ -z "$DRIVERS_TOOLS" ]]; then
    echo >&2 "\$DRIVERS_TOOLS must be set"
    exit 1
fi

# The drivers-evergreen-tools revision used by all SQL Engines projects. We pin it so that upstream
# changes (it is mid-migration from mongo-orchestration to mongodb-runner) cannot silently change
# our CI. To bump it, update the default below and run the `test-run-adf` task on all of its
# build variants in this repo. To try another revision without changing the pin (e.g. in a patch
# build), set the DRIVERS_TOOLS_REF expansion.
DRIVERS_TOOLS_REF="${DRIVERS_TOOLS_REF:-5753ca3568cc728bdf43024e967bdfbb341e5c48}"

rm -rf $DRIVERS_TOOLS
# until global git config is updated directly in hosts, we need this to avoid trying
# to clone over ssh
git config --global --get-regexp '^url\.' | while read -r key _; do
    git config --global --unset "$key"
done

DRIVERS_TOOLS_PATH=$DRIVERS_TOOLS
if [[ "Windows_NT" == "$OS" ]]; then
  DRIVERS_TOOLS_PATH=$(cygpath -m "$DRIVERS_TOOLS")
fi
git clone https://github.com/mongodb-labs/drivers-evergreen-tools.git $DRIVERS_TOOLS_PATH
git -C $DRIVERS_TOOLS_PATH checkout --quiet "$DRIVERS_TOOLS_REF"
echo "Using drivers-evergreen-tools at $(git -C $DRIVERS_TOOLS_PATH rev-parse HEAD)"

