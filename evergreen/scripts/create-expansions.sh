
# Put our own installation of Cargo first in the path to make sure this is the one used.
# Otherwise, on MacOs it will use the version installed with Brew which is not as recent.
if [[ "Windows_NT" == "$OS" ]]; then
  export CARGO_BIN="$HOME/.rustup/bin:$HOME/.cargo/bin"
else
  export CARGO_BIN="$HOME/.cargo/bin"
fi
export PATH="$CARGO_BIN:$PATH"
DRIVERS_TOOLS="$HOME/drivers-evergreen-tools"
cat <<EOT > expansions.yml
cargo_bin: "$CARGO_BIN"
working_dir: sql-engines-common-test-infra
script_dir: ./evergreen/scripts
DRIVERS_TOOLS: "$DRIVERS_TOOLS"
MONGO_ORCHESTRATION_HOME: "$DRIVERS_TOOLS/.evergreen/orchestration"
prepare_shell: |
  set -o errexit
  export PATH="$PATH"
EOT
