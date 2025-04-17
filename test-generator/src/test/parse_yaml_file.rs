use crate::{parse_yaml_test_file, Result, YamlTestCase, YamlTestFile};
use serde::{Deserialize, Serialize};

#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
struct TestExpectations {
    expected_1: String,
    expected_2: Option<String>,
}

#[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
struct TestOptions {
    option_1: Option<String>,
    option_2: Option<String>,
}

type SampleTestCase = YamlTestCase<String, TestExpectations, TestOptions>;

#[test]
fn test_sample_file() {
    let expected_tests = vec![
        SampleTestCase {
            description: "Test with no skip_reason, no options, and a single expectation"
                .to_string(),
            skip_reason: None,
            input: "test input".to_string(),
            expectations: TestExpectations {
                expected_1: "test expectation".to_string(),
                expected_2: None,
            },
            options: TestOptions {
                option_1: None,
                option_2: None,
            },
        },
        SampleTestCase {
            description: "Test with skip_reason".to_string(),
            skip_reason: Some("skip reason: test".to_string()),
            input: "test input".to_string(),
            expectations: TestExpectations {
                expected_1: "test expectation".to_string(),
                expected_2: None,
            },
            options: TestOptions {
                option_1: None,
                option_2: None,
            },
        },
        SampleTestCase {
            description: "Test with no options and multiple expectations".to_string(),
            skip_reason: None,
            input: "test input".to_string(),
            expectations: TestExpectations {
                expected_1: "first expectation".to_string(),
                expected_2: Some("second expectation".to_string()),
            },
            options: TestOptions {
                option_1: None,
                option_2: None,
            },
        },
        SampleTestCase {
            description: "Test with one option".to_string(),
            skip_reason: None,
            input: "test input".to_string(),
            expectations: TestExpectations {
                expected_1: "test expectation".to_string(),
                expected_2: None,
            },
            options: TestOptions {
                option_1: Some("test option".to_string()),
                option_2: None,
            },
        },
        SampleTestCase {
            description: "Test with one option".to_string(),
            skip_reason: None,
            input: "test input".to_string(),
            expectations: TestExpectations {
                expected_1: "test expectation".to_string(),
                expected_2: None,
            },
            options: TestOptions {
                option_1: Some("first option".to_string()),
                option_2: Some("second option".to_string()),
            },
        },
    ];
    let expected_file: YamlTestFile<SampleTestCase> = YamlTestFile {
        tests: expected_tests,
    };

    let path = "src/test/testdata/sample_test_file.yml";

    let actual_result: Result<YamlTestFile<SampleTestCase>> = parse_yaml_test_file(path);

    match actual_result {
        Err(e) => panic!("unexpected error: {e:?}"),
        Ok(actual_file) => assert_eq!(expected_file, actual_file),
    }
}
