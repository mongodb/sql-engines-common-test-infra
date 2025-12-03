#!/bin/bash

set -o errexit

# Determine download target
case $build_variant in
  benchmarking-amazon2-x86-64 | mem-usage)
    echo "Downloading Heaptrack for Amazon Linux 2 x86_64"
    TARGET="heaptrack_build.tar.gz"
    ;;

  benchmarking-amazon2-ARM2)
    echo "Downloading Heaptrack for Amazon Linux 2 Graviton2 (ARM)"
    TARGET="heaptrack_build_AL2_ARM2.tar.gz"
    ;;

  benchmarking-amazon2023-x86-64)
    echo "Downloading Heaptrack for Amazon Linux 2023 x86_64"
    TARGET="heaptrack_build_AL2023_x86.tar.gz"
    ;;

  benchmarking-amazon2023-ARM2)
    echo "Downloading Heaptrack for Amazon Linux 2023 Graviton2 (ARM)"
    TARGET="heaptrack_build_AL2023_ARM2.tar.gz"
    ;;

  benchmarking-amazon2023-ARM9)
    echo "Downloading Heaptrack for Amazon Linux 2023 Graviton4 (ARM)"
    TARGET="heaptrack_build_AL2023_ARM9.tar.gz"
    ;;

  *)
    echo "Unknown build_variant: $build_variant"
    exit 1
    ;;
esac

# Download and extract the tools
curl -LO "https://mongosql-noexpire.s3.us-east-2.amazonaws.com/mem_usage/$TARGET"
tar -xzvf $TARGET

cat <<EOT > heaptrack_expansion.yml
heaptrack_path: "$PWD/heaptrack"
EOT
