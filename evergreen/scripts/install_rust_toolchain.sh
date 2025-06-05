#!/bin/bash

set -o errexit

# make sure to use msvc toolchain rather than gnu, which is
# the default for cygwin
if [[ "Windows_NT" == "$OS" ]]; then
    export HOST="x86_64-pc-windows-msvc"
    export DEFAULT_HOST_OPTIONS="--default-host $HOST"
    export DEFAULT_TOOLCHAIN="stable-$HOST"
fi

# install rustup from scratch
rm -rf ~/.rustup
curl https://sh.rustup.rs -sSf | sh -s -- -y --no-modify-path $DEFAULT_HOST_OPTIONS

# rustup installs into C:\Users\$USER instead of
# C:\home\$USER, so we symlink both .rustup and .cargo
if [[ "Windows_NT" == "$OS" ]]; then
    ln -sf /cygdrive/c/Users/$USER/.rustup/toolchains/$DEFAULT_TOOLCHAIN ~/.rustup
    ln -sf /cygdrive/c/Users/$USER/.cargo/ ~/.cargo
    rustup toolchain install $DEFAULT_TOOLCHAIN
    rustup default $DEFAULT_TOOLCHAIN
fi

echo --------- rustup show -----------
rustup show
echo ----- Rustup toolchain list -----
rustup toolchain list
echo --------- Cargo version ---------
cargo --version
echo ---------------------------------
