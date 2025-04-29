///
/// This library is intended for use with other Rust repositories owned by the SQL Engines team. It
/// provides primitives for generating Rust test cases from YAML files. It is intended for use with
/// build scripts that execute as part of a `cargo test` invocation.
///
#[cfg(test)]
mod test;

use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::{
    fs::{self, read_dir, File, OpenOptions, ReadDir},
    io::{self, Write},
    path::{Path, PathBuf},
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
    Io(String, io::Error),
    #[error("encountered multiple errors: {0:?}")]
    Multiple(Vec<Error>),
    #[error("cannot create TestGenerator for unknown test type at path: {0}")]
    UnknownTestType(String),
}

/// The Result type used by this library.
pub type Result<T> = std::result::Result<T, Error>;

/// TestGenerator defines how a Rust test file should be generated from a YAML test file.
/// Implementors must provide a YamlFileType definition, in addition to implementations for writing
/// the header of the test file and writing the body of the test file. The trait provides a standard
/// parse_yaml method that utilizes the implementor's YamlTestCase definition. It also provides a
/// generate_test_file method which handles the boilerplate code for writing a test file, and
/// dispatches to the generate_test_file_header and generate_test_case methods for writing the
/// actual test cases.
pub trait TestGenerator {
    /// The target type for parsing YAML files.
    type YamlTestCase: DeserializeOwned;

    /// Write the appropriate header to the generated test file, given the canonicalized path to
    /// the YAML test file.
    fn generate_test_file_header(
        &self,
        generated_test_file: &mut File,
        canonicalized_path: String,
    ) -> Result<()>;

    /// Generate a single test case from the current YAML file. The arguments are the generated test
    /// file to write to, the index of the test from the YAML file, and the test case itself from
    /// the YAML file. Implementors have access to the underlying YamlTestCase type. If implementors
    /// want to use test case descriptions as test function names, it is advised they use this
    /// library's `sanitize_description` function.
    fn generate_test_case(
        &self,
        generated_test_file: &mut File,
        index: usize,
        test_case: &Self::YamlTestCase,
    ) -> Result<()>;

    /// Parses the YAML file at path into the implementation's YamlFileType.
    fn parse_yaml(&self, path: PathBuf) -> Result<YamlTestFile<Self::YamlTestCase>> {
        parse_yaml_test_file(path)
    }

    /// Generates a Rust test file from a YAML test file.
    fn generate_test_file(
        &self,
        original_path: PathBuf,
        normalized_path: String,
        mod_file: &mut File,
        generated_dir_path: &str,
    ) -> Result<()> {
        // Step 1: Create a mod entry in the mod file. At this point, the "path" has been normalized
        // therefore it can safely be used as a module name.
        write_mod_entry(mod_file, normalized_path.clone())?;

        // Step 2: Create writable test file handle.
        let test_file_name = format!("{normalized_path}.rs");
        let test_file_path = Path::new(generated_dir_path).join(test_file_name.clone());
        let mut generated_test_file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(test_file_path)
            .map_err(|e| Error::Io(format!("failed to create test file {test_file_name}"), e))?;

        // Step 3: Write the appropriate test header.
        let canonicalized_path = original_path
            .clone()
            .canonicalize()
            .map_err(|e| {
                Error::Io(
                    format!("failed to canonicalize path '{}'", original_path.display()),
                    e,
                )
            })?
            .to_string_lossy()
            .to_string();
        self.generate_test_file_header(&mut generated_test_file, canonicalized_path)?;

        // Step 4: Parse the test file using this TestGenerator's YamlTestCase type.
        let parsed_test_file = self.parse_yaml(original_path)?;

        // Step 5: Write the parsed YAML tests as Rust tests in the generated file, using this
        // test type's template and feature name.
        for (index, test) in parsed_test_file.tests.iter().enumerate() {
            self.generate_test_case(&mut generated_test_file, index, test)?
        }

        Ok(())
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
/// <P: AsRef<Path>>
pub fn parse_yaml_test_file<T: DeserializeOwned, P: AsRef<Path> + Clone>(
    path: P,
) -> Result<YamlTestFile<T>> {
    let path_name = path.clone().as_ref().to_string_lossy().to_string();
    let f = File::open(path)
        .map_err(|e| Error::Io(format!("failed to open test file '{path_name}'"), e))?;
    let test_file: YamlTestFile<T> =
        serde_yaml::from_reader(f).map_err(|e| Error::CannotDeserializeYaml(path_name, e))?;
    Ok(test_file)
}

/// sanitize_description sanitizes test names such that they may be used as function names in
/// generated test files.
pub fn sanitize_description(description: &str) -> String {
    let mut description = description.replace([' ', '-', '(', ')', '\'', ',', '.', ';'], "_");
    description = description.replace("=>", "arrow");
    description = description.replace('$', "dollar_sign");
    description = description.replace('/', "or");
    description = description.replace('?', "question_mark");
    description = description.replace('=', "equals");
    description = description.replace('*', "star");
    description.replace('|', "pipe_")
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
            return Err(Error::Io(
                "failed to create generated test directory".to_string(),
                why,
            ))
        }
        (Err(delete_err), Err(create_err)) => {
            return Err(Error::Multiple(vec![
                Error::Io(
                    "failed to delete generated test directory".to_string(),
                    delete_err,
                ),
                Error::Io(
                    "failed to create generated test directory".to_string(),
                    create_err,
                ),
            ]))
        }
    }

    let mut mod_file = OpenOptions::new()
        .append(true)
        .create(true)
        .open(generated_mod_path)
        .map_err(|e| Error::Io("failed to create or open generated mod file".to_string(), e))?;
    write!(mod_file, include_str!("templates/mod_header")).unwrap();

    let test_dir = read_dir(test_dir_path)
        .map_err(|e| Error::Io("failed to read test directory".to_string(), e))?;

    traverse(
        test_dir,
        generated_dir_path,
        &mut mod_file,
        test_generator_factory,
    )
}

/// traverse the test directory, finding all YAML files. Create a test file for each YAML file.
fn traverse(
    test_dir: ReadDir,
    generated_dir_path: &str,
    mod_file: &mut File,
    test_generator_factory: &impl TestGeneratorFactory,
) -> Result<()> {
    for entry in test_dir {
        let entry =
            entry.map_err(|e| Error::Io("failed to open test directory entry".to_string(), e))?;

        let file_type = entry.file_type().map_err(|e| {
            Error::Io(
                "failed to get test directory entry file type".to_string(),
                e,
            )
        })?;

        let path = entry.path();

        if file_type.is_dir() {
            // Traverse subdirectories
            let sub_dir = read_dir(path.clone()).map_err(|e| {
                Error::Io(
                    format!(
                        "failed to read test subdirectory '{}'",
                        path.to_string_lossy()
                    ),
                    e,
                )
            })?;
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
                let normalized_path = normalize_path(path.clone());
                test_generator.generate_test_file(
                    path,
                    normalized_path,
                    mod_file,
                    generated_dir_path,
                )?;
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

fn write_mod_entry(mod_file: &mut File, path: String) -> Result<()> {
    writeln!(mod_file, "pub mod {path};")
        .map_err(|e| Error::Io(format!("failed to write '{path}' to mod file"), e))
}
