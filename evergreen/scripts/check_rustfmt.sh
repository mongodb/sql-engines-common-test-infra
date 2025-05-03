#!/bin/bash

set -o errexit

cargo fmt --all -- --check
