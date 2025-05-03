#!/bin/bash

set -o errexit

cargo run --bin data-loader -- $data_loader_args
