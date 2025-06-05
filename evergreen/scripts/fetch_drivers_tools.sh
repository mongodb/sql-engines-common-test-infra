#!/bin/bash

set -o errexit

if [[ -z "$DRIVERS_TOOLS" ]]; then
    echo >&2 "\$DRIVERS_TOOLS must be set"
    exit 1
fi

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

