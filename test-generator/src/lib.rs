///
/// This library is intended for use with other Rust repositories owned by the SQL Engines team. It
/// provides primitives for generating Rust test cases from YAML files. It is intended for use with
/// build scripts that execute as part of a `cargo test` invocation.
///
#[cfg(test)]
mod test;

use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::{
    fs::{self, read_dir, File, ReadDir},
    io::{self, Write},
    path::PathBuf,
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
    #[error("{0}: {1:?}")]
    Io(&'static str, io::Error),
    #[error("encountered multiple errors: {0:?}")]
    Multiple(Vec<Error>),
    #[error("cannot create TestGenerator for unknown test type at path: {0}")]
    UnknownTestType(String),
}

/// The Result type used by this library.
pub type Result<T> = std::result::Result<T, Error>;

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

    /// Generates a test file based on a path to a YAML file
    fn generate_test_file(
        &self,
        _path: String,
        _mod_file: &File,
        _generated_dir_path: &str,
    ) -> Result<()> {
        todo!()
        // todo:
        //  1. write mod entry
        //  2. create writable test file handle
        //  3. parse file at this path
        //  4. for each test:
        //    4a. write test based on test-type-specific rules (based on impl)
    }
}

/// A factory for creating TestGenerators. Implementors should know which test types they need to
/// support and should have implementations of TestGenerator for each.
pub trait TestGeneratorFactory {
    /// Given a path to a test file, create the appropriate TestGenerator for handling that
    /// file. Should return Error::UnknownTestType(path) if the implementation cannot create
    /// a TestGenerator for the test type described by path.
    fn create_test_generator(&self, path: String) -> Result<impl TestGenerator>;
}

/// parse_yaml_test_file deserializes the file at the provided path into a YamlTestFile of `T`s.
pub fn parse_yaml_test_file<T: DeserializeOwned>(path: &str) -> Result<YamlTestFile<T>> {
    let f = File::open(path).map_err(|e| Error::Io("failed to open test file", e))?;
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
///     TestGenerator implementations that are appropriate for the tests in the test_dir_path.
///
/// This function removes any files existing at the generated paths before generating and writing
/// any new files. It finds all YAML files in the test directory path, including any YAML files in
/// subdirectories nested at any depth.
pub fn generate_tests(
    generated_dir_path: &str,
    generated_mod_path: &str,
    test_dir_path: &str,
    test_generator_factory: &impl TestGeneratorFactory,
) -> Result<()> {
    let remove = fs::remove_dir_all(generated_dir_path);
    let create = fs::create_dir(generated_dir_path);
    match (remove, create) {
        (Ok(_), Ok(_)) => {}
        // in this case, it may be the first time run so there is nothing to delete.
        // No reason to panic here.
        (Err(_), Ok(_)) => {}
        (Ok(_), Err(why)) => {
            return Err(Error::Io("failed to create generated test directory", why))
        }
        (Err(delete_err), Err(create_err)) => {
            return Err(Error::Multiple(vec![
                Error::Io("failed to delete generated test directory", delete_err),
                Error::Io("failed to create generated test directory", create_err),
            ]))
        }
    }

    let mut mod_file = fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(generated_mod_path)
        .map_err(|e| Error::Io("failed to create or open generated mod file", e))?;
    write!(mod_file, include_str!("templates/mod_header")).unwrap();

    let test_dir =
        read_dir(test_dir_path).map_err(|e| Error::Io("failed to read test directory", e))?;

    traverse(
        test_dir,
        generated_dir_path,
        &mod_file,
        test_generator_factory,
    )
}

/// traverse the test directory, finding all YAML files. Create a test file for each YAML file.
fn traverse(
    test_dir: ReadDir,
    generated_dir_path: &str,
    mod_file: &File,
    test_generator_factory: &impl TestGeneratorFactory,
) -> Result<()> {
    for entry in test_dir {
        let entry = entry.map_err(|e| Error::Io("failed to open test directory entry", e))?;

        let file_type = entry
            .file_type()
            .map_err(|e| Error::Io("failed to get test directory entry file type", e))?;

        let path = entry.path();

        if file_type.is_dir() {
            // Traverse subdirectories
            let sub_dir =
                read_dir(path).map_err(|e| Error::Io("failed to read test subdirectory", e))?;
            traverse(
                sub_dir,
                generated_dir_path,
                mod_file,
                test_generator_factory,
            )?;
        } else if file_type.is_file() {
            let ext = path.extension();
            if ext == Some("yml".as_ref()) || ext == Some("yaml".as_ref()) {
                // Process YAML files
                let test_generator = test_generator_factory
                    .create_test_generator(path.clone().to_string_lossy().to_string())?;
                let normalized_path = normalize_path(path);
                test_generator.generate_test_file(normalized_path, mod_file, generated_dir_path)?;
            }
        }
    }
    Ok(())
}

/// normalize_path strips the path of unnecessary information and accounts for OS-specific encoding.
/// This function is used for generating test file names.
fn normalize_path(path: PathBuf) -> String {
    path.into_os_string()
        .into_string()
        .unwrap()
        .replace("../tests/", "")
        .replace("../tests\\", "")
        .replace('/', "_")
        .replace("\\\\", "_")
        .replace('\\', "_")
        .replace(".yml", "")
}
