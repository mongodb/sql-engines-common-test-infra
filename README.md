# sql-engines-common-test-infra

This repository contains common test infrastructure for SQL Engines projects. The binaries, libraries, scripts, and
Evergreen configuration files are only intended for use with SQL Engines projects.

The repository is broken down into several components, detailed below. See the end of this README for tips and info
about how to use changes in this repository in downstream SQL Engines projects.

## Data Loader Binary
The `data-loader` is a standalone executable that loads test data for SQL Engines integration tests. This tool must
connect to a mongod to write data and may connect to an ADF to write schema. Test data must be specified in YAML or JSON
files (using the .y[a]ml or .json extensions); such files must follow the format demonstrated in the
[data-loader/sample_files](data-loader/sample_files). See the `--help` output for a full description of the binary.

When run with the `adf` flag enabled, or with an `adf_uri` provided, this tool connects to an ADF instance in addition
to a mongod. In this mode, data and indexes are written to the mongod, and schemas are written to ADF (via
`sqlSetSchema` or `sqlGenerateSchema`, depending on the presence of schema info in the data files). In this mode, views
are not written to mongod, as they are assumed to be ADF views which are specified separately, in the ADF config.

When run without the `adf` flag enabled, and without an `adf_uri` provided, this tool only connects to a mongod. In this
mode, documents, indexes, views, and schema are written directly to the mongod.

To run:
```shell
cargo run --bin data-loader -- <args>
```

## Test Generator Library
The `test-generator` library is a Rust utility library that provides the primitives needed to auto-generate Rust tests
from YAML files as part of a `cargo test` run. Specifying tests via YAML is a common feature of SQL Engines projects
written in Rust. See the [test-generator README](test-generator/README.md) for more details.

## Evergreen Configs and Scripts
The [evergreen](evergreen) directory contains useful common Evergreen configuration files and scripts to be used across
SQL Engines projects.

The configs are separated by theme: `benchmark_util.yml` contains common benchmarking functions and tasks (e.g. `install
heaptrack`), `rust_util.yml` contains common Rust functions and tasks (e.g. `install rust toolchain` and `check
clippy`), and so on. If you need to add new common functions and/or tasks, consider the existing configs before creating
a new one. If your new functions and/or tasks do not match any of the existing config themes, create a new config file
in [evergreen/configs](evergreen/configs) and follow the naming convention `<theme>_util.yml`.

The scripts are all grouped together in [evergreen/scripts](evergreen/scripts). Each script focuses on one function and
is named appropriately. If you need to add a new Evergreen function, you should strongly consider writing it as a shell
script in that directory and using the Evergreen `subprocess.exec` command to invoke that script. See existing configs
and scripts for details on this.

## ADF Test Environment
The [test-environment](test-environment) directory contains the [run_adf.sh](test-environment/run_adf.sh) script, which
is useful for deploying a local ADF instance. This directory also contains the relevant configuration files for ADF.
The instance created is general purpose, but the config information is geared toward JDBC and ODBC integration testing.
Feel free to use this script to run ADF for yourself locally.

## Using this repository as an Evergreen module
As noted above, this repository is intended to be used by the other SQL Engines projects. Typically, that is achieved
by having those projects depend on this one as an ["Evergreen module"](https://docs.devprod.prod.corp.mongodb.com/evergreen/Project-Configuration/Project-Configuration-Files#modules).
At time of writing, all existing SQL Engines projects already define `sql-engines-common-test-infra` as a module. That
typically looks like this in a project's Evergreen configuration file:
```yaml
modules:
  - name: sql-engines-common-test-infra
    owner: mongodb
    repo: sql-engines-common-test-infra
    branch: main
    auto_update: true
```

To ensure the module is pulled from GitHub for Evergreen patches, projects typically include this in their `fetch source`
functions:
```yaml
functions:
  "fetch source":
    - command: git.get_project
      params:
        directory: <SQL Engine project repo>
        revisions:
          sql-engines-common-test-infra: ${sql-engines-common-test-infra_rev}
```
Note that the variable `${<module name>_rev}` is automatically provided by Evergreen.

By specifying the `sql-engines-common-test-infra` module in the `modules` list, and ensuring the appropriate revision is
fetched in the `fetch source` function, the module is effectively available for use throughout the evergreen config. To
include configs from this module, you can update the downstream project's `include` list like this:
```yaml
include:
  - filename: evergreen/configs/mongodb_util.yml
    module: sql-engines-common-test-infra
  - filename: evergreen/configs/rust_util.yml
    module: sql-engines-common-test-infra
```
Be sure to check each config file to see if there are any necessary Evergreen expansions that need to be set. For
example, it is common for the configs in this module to require the `${working_dir}` expansion to be set appropriately.

**Importantly**, the final step to ensure the module is available on the `buildvariant` you need it on is to update the
`buildvariant` definition to include the module like this:
```yaml
buildvariants:
  - name: <name>
    display_name: <display name>
    run_on: <list of platforms>
    modules:
      - sql-engines-common-test-infra
    tasks: <list of tasks>
```
If you omit the `modules` field from a buildvariant definition or omit `sql-engines-common-test-infra` from the list of
`modules`, the module will not be available on that buildvariant despite being specified at the top-level of the config
and fetched with the project's source code. You _must_ specify the module in the `modules` field for each `buildvariant`
on which you need the module present. (For the most part, this should already be set up on all relevant buildvariants 
for all existing projects.)

### ⚠️ IMPORTANT:  Using updates to this module ⚠️
If you make updates to this repository and want to test those changes in a downstream repo before pushing them, you
may do so by using the `evergreen` cli tool. First, ensure you have the `evergreen` cli tool installed and authenticated.
Then, in the downstream project you wish to test changes in, create a patch and include your local fork (with edits) of
this repository as a module. You can do so like this:
```shell
evergreen patch -p <project id> --include-module sql-engines-common-test-infra=/absolute/path/to/sql-engines-common-test-infra
```
Tip: don't forget to include the `-u` flag to include uncommitted local changes.

When your changes to this repository are merged, the downstream projects should pick them up automatically. To achieve this,
ensure each downstream project specifies the module with `auto_update: true`, as described in the previous section.

It is advised that you run a manual patch for relevant downstream projects before merging pull requests to main. This
helps ensure that the changes you make do not break downstream projects.
