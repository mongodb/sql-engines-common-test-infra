///
/// This library is intended for use with other Rust repositories owned by the SQL Engines team. It
/// provides primitives for generating Rust test cases from YAML files. It is intended for use with
/// build scripts that execute as part of a `cargo test` invocation.
///
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
    let f = fs::File::open(path).map_err(|e| Error::InvalidFile(e))?;
    let test_file: YamlTestFile<T> = serde_yaml::from_reader(f)
        .map_err(|e| Error::CannotDeserializeYaml(path.to_string(), e))?;
    Ok(test_file)
}
