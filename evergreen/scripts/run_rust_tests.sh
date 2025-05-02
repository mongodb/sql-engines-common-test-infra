#!/bin/bash

set -o errexit

echo $description
set +e
cargo test $cargo_test_flags
EXITCODE=$?
set -e
exit $EXITCODE
