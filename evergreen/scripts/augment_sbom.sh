#!/bin/bash

set -o errexit

echo "SBOM_IN_PATH = $sbom_in_path"
echo "SBOM_OUT_PATH = $sbom_out_path"

echo "-- Augmenting SBOM Lite --"
docker run -i --platform="linux/amd64" --rm -v "$PWD":/pwd \
  --env-file ./aws_vars.env \
  901841024863.dkr.ecr.us-east-1.amazonaws.com/release-infrastructure/silkbomb:2.0 \
  augment --repo $github_org/$github_repo --branch $branch_name --sbom-in /pwd/$sbom_in_path --sbom-out /pwd/$sbom_out_path --force
echo "-------------------------------"
