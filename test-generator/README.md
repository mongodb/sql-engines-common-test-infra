## SQL Engines Test Generator Library
### Overview
This test generator library is intended for use by SQL Engines team repositories that
1. are written in Rust, and
2. have tests specified in YAML files.

The goal of all YAML-specified tests in our team's repos is to run each one as its own Rust test.
This library provides the primitives needed to auto-generate Rust tests from YAML files as part of
a `cargo test` run.

### How to Use
This how-to section assumes the repository using this library has tests written in YAML.

To use the `test-generator` library in a downstream SQL Engines repo, first create or navigate to a
package in the repo that can be used for testing. For example, see the
[`mongosql/e2e-tests`](https://github.com/mongodb/mongosql/tree/main/e2e-tests) package in the
[mongosql](https://github.com/mongodb/mongosql) repo. There, create a `build.rs` file with a `main`
function. Placing a file named `build.rs` in the root of a package will cause Cargo to compile that
script and execute it just before building the package
([docs](https://doc.rust-lang.org/cargo/reference/build-scripts.html)). This notion of build scripts
is how the library is useful for "auto-generating" tests -- the build script dynamically generates
Rust files with Rust tests based on input YAML files as part of the `cargo test` invocation.

Next, with the testing package selected and `build.rs` file created, the package should add
`sql-engines-common-test-infra` as a dependency. This will give the package programmatic access to
the public libraries in this repository -- in this case, the `test-generator` library.

Then, determine which YAML tests this package will execute. Create a `templates` directory in the
package and, for each type of test, create "header" and "body" template files in that directory.
Each YAML file will correspond to a Rust file, and each YAML test case in a file will correspond to
a Rust test case in the respective Rust file. The "header" template represents the beginning of the
Rust file, useful for any necessary `use` statements, attributes (such as `clippy` ignores), and set
up functions. The "body" template represents a single Rust test. Each test should be guarded with a
`feature` flag so that they can be run separately from other test types. Again, see the
`mongosql/e2e-tests` package or this library's `src/test/generate_tests.rs` file for examples.

Finally, the `build.rs` script must implement the `TestGenerator` and `TestGeneratorFactory` traits
and may create type aliases for any `YamlTestCase` types. Each test type the package is responsible
for must have a corresponding `TestGenerator` implementation. The implementation must implement two
methods: `generate_test_file_header`, which should use the "header" template to generate a Rust test
file header, and `generate_test_case`, which should use the "body" template to generate a Rust test
case in the file. The package should have one implementation of `TestGeneratorFactory` that is able
to return any of the package's `TestGenerator` impls based on the path to a test file.

With those traits implemented, the `main` function can simply call `generate_tests` with the
appropriate arguments: a path to the generated test directory, a path to the generated test mod
file, a path to the input test directory, and the `TestGeneratorFactory` impl. That is all the
`main` function needs to do to ensure the package runs each YAML test as an independent Rust test.

Be sure to also read the code comments in the library for more details on each component.

### Example
A code example is available in this library at
[`src/test/generate_tests.rs`](./src/test/generate_tests.rs). The YAML test files and templates are
in [`src/test/testdata`](./src/test/testdata). Instead of a `main` function in a build script, this
example invokes `generate_tests` in a unit test, but the translation to `main` is trivial.
