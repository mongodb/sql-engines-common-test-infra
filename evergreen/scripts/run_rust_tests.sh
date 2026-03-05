#!/bin/bash

set -o errexit

echo $description
echo "mongodb version: $mongodb_version"
export MONGODB_VERSION=$mongodb_version
cargo test $cargo_test_flags
