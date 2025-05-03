#!/bin/bash

set -o errexit

echo $description
cargo test $cargo_test_flags
