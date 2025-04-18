use clap::Parser;
use mongodb::{bson::Bson, IndexModel};
use serde::{Deserialize, Serialize};
use std::io;
use thiserror::Error;

/// This is a standalone executable that loads test data for SQL Engines integration tests. The
/// data must be specified in YAML or JSON files (using the .y[a]ml or .json extensions), and they
/// must follow the format described by the TestDataFile and TestDataEntry types. See those types
/// for more details.
#[derive(Parser, Debug)]
#[command(version)]
struct Args {
    /// mongod URI. Optional.
    /// Defaults to "mongodb://$MDB_TEST_LOCAL_HOST:$MDB_TEST_LOCAL_PORT".
    #[arg(long)]
    mongod_uri: Option<String>,

    /// ADF URI. Optional.
    /// Defaults to "mongodb://$ADF_TEST_LOCAL_USER:$ADF_TEST_LOCAL_PASSWORD@$ADF_TEST_LOCAL_HOST:$ADF_TEST_LOCAL_PORT".
    #[arg(long)]
    adf_uri: Option<String>,

    /// Path to directory containing test data files
    #[arg(short = 'd', long = "testDataDirectory")]
    test_data_directory: String,

    /// Indicates whether schema is written to ADF or mongod
    #[arg(long = "adf")]
    write_schema_to_adf: bool,
}

fn main() {
    let args = Args::parse();
    println!("Hello, world!");
}

/// A struct representing a YAML file that contains test data. All YAML test data files contain a
/// top-level `dataset` key. The value of `dataset` is a list of TestDataEntries.
#[derive(Serialize, Deserialize, Debug, Clone)]
struct TestDataFile {
    dataset: Vec<TestDataEntry>,
}

/// A struct representing a YAML-specified test data entry. See the fields for what a test data
/// entry may include. Most fields are optional.
#[derive(Serialize, Deserialize, Debug, Clone)]
struct TestDataEntry {
    /// db specifies the database for this test entry. Required.
    db: String,

    /// collection specifies the collection for this entry. Conditional.
    /// Exactly one of 'collection' or 'view' must be specified for every test entry.
    collection: Option<CollectionData>,

    /// view specifies the view for this test entry. Conditional.
    /// Exactly one of 'collection' or 'view' must be specified for every test entry.
    ///
    /// Note that ADF views are defined in ADF itself, not on the underlying datasource(s) -- in
    /// this case, not on the mongod. They are defined in the ADF config file, separate from the
    /// test data. Therefore, when run against ADF, this data loader ignores the pipeline field; it
    /// only sets schema for views when run against ADF.
    ///
    /// When run against mongod directly, this data loader will not only set the schema for the view
    /// it will also create it on the mongod using the provided pipeline field.
    view: Option<ViewData>,

    /// schema specifies the schema for this test entry. Optional.
    ///
    /// When run against ADF:
    /// If provided, this data loader sets the collection or view schema using the sqlSetSchema
    /// command. If not provided, this data loader sets the collection or view schema using the
    /// sqlGenerateSchema command.
    ///
    /// When run against mongod:
    /// If provided, this data loader sets the collection or view schema directly in the
    /// __sql_schemas collection. If not provided, no schema is set for the collection or view. This
    /// may lead to limited test functionality.
    schema: Option<Bson>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct CollectionData {
    /// name specifies the name of the collection. Required.
    name: String,

    /// docs specifies the documents to insert into the collection. Required.
    ///
    /// The documents can be specified in extended JSON format.
    docs: Vec<Bson>,

    /// indexes specifies the indexes for this test entry. Optional.
    ///
    /// These must be specified following the Rust driver's IndexModel format:
    ///   { key: <key document>, options: <options document> }
    ///
    /// Example:
    ///   indexes:
    ///     - { key: {b: 1, a: -1}}
    ///
    /// See the docs for more details on possible options.
    indexes: Option<Vec<IndexModel>>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct ViewData {
    /// The name of the view. Required.
    name: String,

    /// The pipeline definition of the view. Optional.
    ///
    /// When run against ADF, this field will be ignored even if provided.
    pipeline: Option<Bson>,
}

type Result<T> = std::result::Result<T, DataLoaderError>;

#[derive(Error, Debug)]
pub enum DataLoaderError {
    #[error(transparent)]
    FileSystem(#[from] io::Error),
    #[error(transparent)]
    Mongo(#[from] mongodb::error::Error),
    #[error(transparent)]
    Serde(#[from] serde_yaml::Error),
    #[error("Each entry must specify exactly one of 'view' or 'collection', but at least one entry in {0} does not")]
    MissingViewOrCollection(String),
}
