#!/bin/bash

set -o errexit

if [[ -z "$DRIVERS_TOOLS" ]]; then
    echo >&2 "\$DRIVERS_TOOLS must be set"
    exit 1
fi

OS_NAME=$(uname -s)
# Determine the target port:
# Use MDB_TEST_LOCAL_PORT if it's set and not empty, otherwise use DEFAULT_PORT.
DEFAULT_PORT=28017
TARGET_PORT="${MDB_TEST_LOCAL_PORT:-$DEFAULT_PORT}"
# use CONFIG_FILE if provided, otherwise use default basic.json
CONFIG_FILE="$1"
if [[ -z "$CONFIG_FILE" ]]; then
  CONFIG_FILE="basic.json"
fi
CONFIG_PATH="${DRIVERS_TOOLS}/.evergreen/orchestration/configs/servers/${CONFIG_FILE}"
OS_NAME=$(uname -s)
if [[ $OS_NAME =~ ^CYGWIN ]]; then
  CONFIG_PATH="/cygdrive/c/$CONFIG_PATH"
fi

cp "$CONFIG_PATH" "$CONFIG_PATH.bak"

if ! sed -E -e "s/\"port\": [0-9]+/\"port\": $TARGET_PORT/" "$CONFIG_PATH" > "$CONFIG_PATH.tmp"; then
  echo >&2 "sed failed to update port"
  mv "$CONFIG_PATH.bak" "$CONFIG_PATH"
  exit 1
fi

mv "$CONFIG_PATH.tmp" "$CONFIG_PATH"

echo "Updated port to $TARGET_PORT in $CONFIG_PATH"
