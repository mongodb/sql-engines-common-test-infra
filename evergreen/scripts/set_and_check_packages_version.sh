#!/bin/bash

set -o errexit

#no-op when not triggered by a tag
if [[ "$triggered_by_git_tag" != "" ]]; then
  cargo install cargo-edit
  # we only release one project at a time, so setting the version on all Cargo.toml files is safe
  cargo set-version $release_version
fi

cargo install cargo-get

# check all of the releasable packages in the monorepo to verify that whichever is being released has the correct version
CARGO_PKGS_VERSION=$(cargo get --entry="$cargo_file" package.version)
if [[ "$triggered_by_git_tag" == "" ]]; then
  EXPECTED_RELEASE_VERSION="0.0.0"
else
  EXPECTED_RELEASE_VERSION="$release_version"
fi

if [[ "$CARGO_PKGS_VERSION" != "$EXPECTED_RELEASE_VERSION" ]]; then
  >&2 echo "Expected version $EXPECTED_RELEASE_VERSION but got $CARGO_PKGS_VERSION for $package_name"
  exit 1
fi
