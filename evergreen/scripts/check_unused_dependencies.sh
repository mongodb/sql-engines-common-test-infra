#!/bin/bash

set -o errexit

cargo install cargo-machete
cargo build
set +e
cargo machete
RETURN=$?
set -e
if [ $RETURN -ne 0 ]; then
  >&2 echo "Unused dependencies found"
  >&2 cargo machete
  exit 1
fi
