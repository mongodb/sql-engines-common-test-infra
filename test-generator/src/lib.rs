///
/// This library is intended for use with other Rust repositories owned by the SQL Engines team. It
/// provides primitives for generating Rust test cases from YAML files. It is intended for use with
/// build scripts that execute as part of a `cargo test` invocation.
///
#[cfg(test)]
mod test;

use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::{
    fs::{self},
    io,
};
use thiserror::Error;

/// A struct representing a YAML file that contains tests. All YAML test files contain a top-level
/// `tests` key. The value of `tests` is a list of test cases, parameterized here as `T`.
#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct YamlTestFile<T> {
    pub tests: Vec<T>,
}

/// A struct representing a YAML-specified test case. All YAML test cases share common features: a
/// description, an optional skip_reason, an input, one or more expected values, and zero or more
/// options. The `input`, `expectations`, and `options` are parameterized here as `I`, `E`, and `O`,
/// respectively, because they can vary in number and type across test types. For example, one test
/// may assert multiple expectations while another may only assert one, or one test may specify a
/// `current_db` option while another may not.
///
/// Note that `input` can also be specified using the known aliases "query" or "test_definition". At
/// time of creation, these are common YAML test input names in SQL Engines repositories so they are
/// supported by default. Future use cases can expand the alias list or use "input" in test cases.
///
/// Also note that `expectations` and `options` are marked with the serde(flatten) attribute. This
/// allows for expected and option fields in the YAML files to be at the same nesting depth as the
/// other test fields.
#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct YamlTestCase<I, E, O> {
    pub description: String,
    pub skip_reason: Option<String>,

    #[serde(alias = "query", alias = "test_definition")]
    pub input: I,

    #[serde(flatten)]
    pub expectations: E,

    #[serde(flatten)]
    pub options: O,
}

/// A utility type for any test cases that do not have extra options.
#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct NoOptions {}

/// TestGenerator defines how a test should be generated. Implementors must provide a YamlFileType
/// definition, in addition to the feature name and test template used to generate tests of the
/// implementation's type. The trait provides a standard parse_yaml implementation that utilizes the
/// implementors' YamlFileType definitions and the general parse_yaml_test_file function.
pub trait TestGenerator {
    /// The target type for parsing YAML files
    type YamlTestCase: DeserializeOwned;

    /// Gets the feature name to be used to guard the generated tests of this type
    fn get_feature_name(&self) -> String;

    /// Gets the test template to use to generate tests of this type
    fn get_test_template(&self) -> String;

    /// Parses the YAML file at path into the implementation's YamlFileType
    fn parse_yaml(&self, path: &str) -> Result<YamlTestFile<Self::YamlTestCase>> {
        parse_yaml_test_file(path)
    }
}

/// A factory for creating TestGenerators. Implementors should know which test types they need to
/// support and should have implementations of TestGenerator for each.
pub trait TestGeneratorFactory {
    /// Given a path to a test file, create the appropriate TestGenerator for handling
    /// that file.
    fn create_test_generator(&self, path: &str) -> impl TestGenerator;
}

/// Errors returned by this library.
#[derive(Debug, Error)]
pub enum Error {
    #[error("unable to deserialize YAML file '{0:?}': '{1:?}")]
    CannotDeserializeYaml(String, serde_yaml::Error),
    #[error("failed to read file: {0:?}")]
    InvalidFile(io::Error),
}

/// The Result type used by this library.
pub type Result<T> = std::result::Result<T, Error>;

/// parse_yaml_test_file deserializes the file at the provided path into a YamlTestFile of `T`s.
pub fn parse_yaml_test_file<T: DeserializeOwned>(path: &str) -> Result<YamlTestFile<T>> {
    let f = fs::File::open(path).map_err(Error::InvalidFile)?;
    let test_file: YamlTestFile<T> = serde_yaml::from_reader(f)
        .map_err(|e| Error::CannotDeserializeYaml(path.to_string(), e))?;
    Ok(test_file)
}

/// generate_tests should be used in build scripts that need to generate individual Rust test cases
/// for YAML-specified test cases. The arguments to this function are:
///   - generated_dir_path: the path where the generated test files are written
///   - generated_mod_path: the path where the generated mod file is written
///   - test_dir_path: the path to the YAML test files (can contain subdirectories)
///   - test_generator_factory: an implementation of the TestGeneratorFactory trait that can create
///                             TestGenerator implementations that are appropriate for the tests in
///                             the test_dir_path.
///
/// This function removes any files existing at the generated paths before generating and writing
/// any new files. It finds all YAML files in the test directory path, including any YAML files in
/// subdirectories nested at any depth.
pub fn generate_tests(
    _generated_dir_path: &str,
    _generated_mod_path: &str,
    _test_dir_path: &str,
    _test_generator_factory: &impl TestGeneratorFactory,
) {
    todo!()
}
