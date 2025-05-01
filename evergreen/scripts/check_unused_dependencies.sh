#!/bin/bash

set -o errexit

echo "[script] PATH = $PATH"

cargo install cargo-machete
cargo build --all-features
set +e
cargo machete
RETURN=$?
set -e
if [ $RETURN -ne 0 ]; then
  >&2 echo "Unused dependencies found"
  >&2 cargo machete
  exit 1
fi
