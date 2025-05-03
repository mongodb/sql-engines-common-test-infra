#!/bin/bash

set -o errexit

cargo clippy --all-targets -- -D warnings
