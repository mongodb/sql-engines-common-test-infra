use crate::{
    generate_tests, sanitize_description, test::parse_yaml_file::SampleTestCase, Error, Result,
    TestGenerator, TestGeneratorFactory,
};
use std::fs;
use std::fs::File;
use std::io::Write;

struct TestTestGenerator {}

impl TestGenerator for TestTestGenerator {
    type YamlTestCase = SampleTestCase;

    fn generate_test_file_header(&self, generated_test_file: &mut File, _: String) -> Result<()> {
        // Note that the canonicalized path is absolute, which is obviously dependent on where the
        // test is run, therefore we use the hard-coded string "test-path" for the path value.
        write!(
            generated_test_file,
            include_str!("./testdata/templates/sample_test_header"),
            path = "test/path",
        )
        .map_err(|e| Error::Io("failed to write header".to_string(), e))
    }

    fn generate_test_case(
        &self,
        generated_test_file: &mut File,
        index: usize,
        test_case: &Self::YamlTestCase,
    ) -> Result<()> {
        let sanitized_name = sanitize_description(&test_case.description);
        if test_case.skip_reason.is_some() {
            write!(
                generated_test_file,
                include_str!("./testdata/templates/ignore_body_template"),
                name = sanitized_name,
                skip_reason = test_case.skip_reason.as_ref().unwrap(),
                feature = "sample"
            )
            .map_err(|e| Error::Io("failed to write".to_string(), e))?
        } else {
            write!(
                generated_test_file,
                include_str!("./testdata/templates/sample_test_body"),
                name = sanitized_name,
                index = index,
            )
            .map_err(|e| Error::Io("failed to write".to_string(), e))?
        }
        Ok(())
    }
}

struct TestTestGeneratorFactory {}

impl TestGeneratorFactory for TestTestGeneratorFactory {
    fn create_test_generator(&self, _: String) -> Result<impl TestGenerator> {
        Ok(TestTestGenerator {})
    }
}

#[test]
fn test_generate_tests() {
    let actual = generate_tests(
        "./generated_tests",
        "./generated_tests/mod.rs",
        "src/test/testdata",
        &TestTestGeneratorFactory {},
    );

    assert!(
        actual.is_ok(),
        "expected generate_tests to succeed but it failed: {actual:?}"
    );

    let expected_generated_mod_file = r#"#![cfg_attr(rustfmt, rustfmt_skip)]
#![allow(clippy::all)]
pub mod src_test_testdata_sample_test_file;
"#;

    let actual_generated_mod_file = fs::read_to_string("./generated_tests/mod.rs")
        .expect("failed to read actual generated mod file");

    assert_eq!(expected_generated_mod_file, actual_generated_mod_file,);

    let expected_generated_test_file = r#"#![cfg_attr(rustfmt, rustfmt_skip)]
#![allow(clippy::all)]
#![allow(non_snake_case, dead_code, unused_variables, unused_imports)]

use crate::{parse_yaml_test_file, test::parse_yaml_file::SampleTestCase, YamlTestFile};
use std::{collections::HashSet, fs, io::Read, path::PathBuf, string::ToString, sync::Once};

static INIT: Once = Once::new();

pub fn initialize_test() -> (&'static Client, &'static QueryYamlTestFile) {
    static mut TEST_FILE: Option<YamlTestFile<SampleTestCase>> = None;

    INIT.call_once(|| {
        unsafe {
            TEST_FILE = Some(parse_yaml_test_file(PathBuf::from("test/path")).unwrap());
        }
    });

    unsafe {
        TEST_FILE.as_ref().unwrap()
    }
}
#[cfg(feature = "sample")]
#[test]
pub fn Test_with_no_skip_reason__no_options__and_a_single_expectation() {
    let test_file = initialize_test();
    let test = test_file.tests.get(0).unwrap();

    assert_eq!("test input", test.input);
    assert!(test.expectations.expected_1.contains("expectation"));

    if let Some(option_1) = test.options.option_1.as_ref() {
        assert!(option_1.contains("option"));
    }
}

#[cfg(feature = "sample")]
#[test]
#[ignore = "skip reason: test"]
pub fn Test_with_skip_reason() {
    assert_eq!(1, 1);
}
#[cfg(feature = "sample")]
#[test]
pub fn Test_with_no_options_and_multiple_expectations() {
    let test_file = initialize_test();
    let test = test_file.tests.get(2).unwrap();

    assert_eq!("test input", test.input);
    assert!(test.expectations.expected_1.contains("expectation"));

    if let Some(option_1) = test.options.option_1.as_ref() {
        assert!(option_1.contains("option"));
    }
}
#[cfg(feature = "sample")]
#[test]
pub fn Test_with_one_option() {
    let test_file = initialize_test();
    let test = test_file.tests.get(3).unwrap();

    assert_eq!("test input", test.input);
    assert!(test.expectations.expected_1.contains("expectation"));

    if let Some(option_1) = test.options.option_1.as_ref() {
        assert!(option_1.contains("option"));
    }
}
#[cfg(feature = "sample")]
#[test]
pub fn Test_with_two_options() {
    let test_file = initialize_test();
    let test = test_file.tests.get(4).unwrap();

    assert_eq!("test input", test.input);
    assert!(test.expectations.expected_1.contains("expectation"));

    if let Some(option_1) = test.options.option_1.as_ref() {
        assert!(option_1.contains("option"));
    }
}
"#;

    let actual_generated_test_file =
        fs::read_to_string("./generated_tests/src_test_testdata_sample_test_file.rs")
            .expect("failed to read actual generated test file");

    assert_eq!(expected_generated_test_file, actual_generated_test_file);
}
