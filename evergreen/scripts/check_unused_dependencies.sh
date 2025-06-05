#!/bin/bash

set -o errexit

cargo install cargo-machete
if [[ $skip_machete_build != "" ]]; then
  echo "Skipping build step"
else
  echo "Building before cargo machete"
  cargo build
fi
set +e
cargo machete
RETURN=$?
set -e
if [ $RETURN -ne 0 ]; then
  >&2 echo "Unused dependencies found"
  >&2 cargo machete
  exit 1
fi
