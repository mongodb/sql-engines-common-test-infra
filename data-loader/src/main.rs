use clap::Parser;
use mongodb::{
    bson::{datetime, doc, Bson, Document},
    Client, Database, IndexModel,
};
use serde::{Deserialize, Serialize};
use std::{env, fs, io};
use thiserror::Error;

/// This is a standalone executable that loads test data for SQL Engines integration tests. This
/// tool must connect to a mongod to write data, and may connect to an ADF to write schema. Test
/// data must be specified in YAML or JSON files (using the .y[a]ml or .json extensions), and they
/// must follow the format described by the TestDataFile and TestDataEntry types. See those types
/// for more details.
///
/// When run with the adf flag enabled, or with an adf_uri provided, this tool connects to an ADF
/// instance in addition to a mongod. In this mode, data and indexes are written to the mongod, and
/// schemas are written to ADF (via sqlSetSchema or sqlGenerateSchema, depending on the presence of
/// schema info in the data files). In this mode, views are not written to mongod, as they are
/// assumed to be ADF views which are specified separately, in the ADF config.
///
/// When run without the adf flag enabled, and without an adf_uri provided, this tool only connects
/// to a mongod. In this mode, documents, indexes, views, and schema are written directly to the
/// mongod.
#[derive(Parser, Debug)]
#[command(version)]
struct Args {
    /// mongod URI. Optional.
    /// Defaults to "mongodb://$MDB_TEST_LOCAL_HOST:$MDB_TEST_LOCAL_PORT".
    #[arg(long)]
    mongod_uri: Option<String>,

    /// ADF URI. Optional.
    /// Defaults to "mongodb://$ADF_TEST_LOCAL_USER:$ADF_TEST_LOCAL_PASSWORD@$ADF_TEST_LOCAL_HOST:$ADF_TEST_LOCAL_PORT".
    /// If an adf_uri is provided, the adf flag is assumed to be true. A user can choose to omit the
    /// adf_uri option and still connect to ADF by providing the adf flag; in this case, the ADF URI
    /// will use the default value described previously.
    #[arg(long)]
    adf_uri: Option<String>,

    /// Path to directory containing test data files
    #[arg(short = 'd', long = "testDataDirectory")]
    test_data_directory: String,

    /// Indicates whether the data loader needs to connect to ADF
    #[arg(long)]
    adf: bool,
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

    #[serde(flatten)]
    definition: Option<ViewDefinition>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
struct ViewDefinition {
    /// The collection on which to create the view. Optional.
    ///
    /// When run against ADF, this field will be ignored even if provided.
    view_on: String,

    /// The pipeline definition of the view. Optional.
    ///
    /// When run against ADF, this field will be ignored even if provided.
    pipeline: Vec<Document>,
}

type Result<T> = std::result::Result<T, DataLoaderError>;

#[derive(Error, Debug)]
pub enum DataLoaderError {
    #[error(transparent)]
    FileSystem(#[from] io::Error),
    #[error(transparent)]
    Mongo(#[from] mongodb::error::Error),
    #[error(transparent)]
    SerdeJson(#[from] serde_json::Error),
    #[error(transparent)]
    SerdeYaml(#[from] serde_yaml::Error),
    #[error("Each entry must specify exactly one of 'view' or 'collection', but at least one entry in {0} does not")]
    InvalidViewOrCollectionDataEntry(String),
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let args = Args::parse();

    println!("Step 1: Connecting to mongod.");
    let mdb_uri = args.mongod_uri.unwrap_or_else(|| {
        format!(
            "mongodb://{}:{}",
            env::var("MDB_TEST_LOCAL_HOST")
                .expect("no mongod_uri provided and MDB_TEST_LOCAL_HOST is not set"),
            env::var("MDB_TEST_LOCAL_PORT")
                .expect("no mongod_uri provided and MDB_TEST_LOCAL_PORT is not set"),
        )
    });
    let mdb_client = Client::with_uri_str(mdb_uri).await?;

    println!("Step 2: Reading data files.");
    let test_data_files = read_data_files(args.test_data_directory)?;

    println!("Step 3: Dropping existing data based on namespaces in data files.");
    drop_collections(mdb_client.clone(), test_data_files.clone()).await?;

    // Step 4: Load data into mongod. Drop everything if an error occurs.
    println!("Step 4: Loading data into mongod.");
    if let Err(e) = load_test_data(mdb_client.clone(), test_data_files.clone()).await {
        println!("Error encountered while loading data. Dropping all previously loaded data.");
        drop_collections(mdb_client, test_data_files).await?;
        return Err(e);
    }

    if args.adf || args.adf_uri.is_some() {
        // If the adf flag is enabled, or an adf_uri is provided, we need to
        // set the schema in ADF.
        println!("Step 5: ADF mode detected. Connecting to ADF.");
        let adf_uri = args.adf_uri.unwrap_or_else(|| {
            format!(
                "mongodb://{}:{}@{}:{}",
                env::var("ADF_TEST_LOCAL_USER")
                    .expect("no mongod_uri provided and ADF_TEST_LOCAL_USER is not set"),
                env::var("ADF_TEST_LOCAL_PASSWORD")
                    .expect("no mongod_uri provided and ADF_TEST_LOCAL_PASSWORD is not set"),
                env::var("ADF_TEST_LOCAL_HOST")
                    .expect("no mongod_uri provided and ADF_TEST_LOCAL_HOST is not set"),
                env::var("ADF_TEST_LOCAL_PORT")
                    .expect("no mongod_uri provided and ADF_TEST_LOCAL_PORT is not set"),
            )
        });
        let adf_client = Client::with_uri_str(adf_uri).await?;

        println!("Step 6: Writing schema to ADF.");
        set_schemas_in_adf(adf_client, test_data_files).await
    } else {
        // Otherwise, we need to write the schema directly to mongod.
        println!("Step 5: Writing schema directly to mongod.");
        set_schemas_in_mongod(mdb_client, test_data_files).await
    }
}

fn read_data_files(dir_path: String) -> Result<Vec<TestDataFile>> {
    let mut test_data_files = vec![];
    for file in fs::read_dir(dir_path)? {
        let path = file?.path();

        println!("\tReading file {path:?}");

        if let Some(ext) = path.extension() {
            // Only parse paths to '.y[a]ml' or '.json' files
            let test_data_file: TestDataFile = if ext == "yml" || ext == "yaml" {
                let f = fs::File::open(path.clone())?;
                serde_yaml::from_reader(f).map_err(DataLoaderError::SerdeYaml)?
            } else if ext == "json" {
                let f = fs::File::open(path.clone())?;
                serde_json::from_reader(f).map_err(DataLoaderError::SerdeJson)?
            } else {
                println!("\tIgnoring file without '.y[a]ml' or '.json' extension: {path:?}");
                continue;
            };

            if test_data_file
                .clone()
                .dataset
                .into_iter()
                .filter(|entry| entry.collection.is_some() == entry.view.is_some())
                .count()
                > 0
            {
                return Err(DataLoaderError::InvalidViewOrCollectionDataEntry(
                    path.into_os_string().into_string().unwrap(),
                ));
            }

            test_data_files.push(test_data_file);
        }
    }

    Ok(test_data_files)
}

async fn drop_collections(client: Client, test_data_files: Vec<TestDataFile>) -> Result<()> {
    for tdf in test_data_files {
        for entry in tdf.dataset {
            let db = client.database(entry.db.as_str());
            match (entry.collection, entry.view) {
                (Some(CollectionData { name, .. }), _) | (_, Some(ViewData { name, .. })) => {
                    db.collection::<Bson>(name.as_str()).drop().await?;
                    println!("\tDropped {}.{}", entry.db, name);
                }
                _ => (),
            }

            // We should also drop the schema db. We may attempt to drop the
            // same schema collection multiple times but that is a safe thing
            // to do. This is more simple than ensuring we only ever attempt
            // to drop a schema collection exactly once.
            db.collection::<Bson>("__sql_schemas").drop().await?;
        }
    }

    Ok(())
}

async fn load_test_data(client: Client, test_data_files: Vec<TestDataFile>) -> Result<()> {
    for tdf in test_data_files {
        for entry in tdf.dataset {
            let db = client.database(entry.db.as_str());

            // If the entry specifies a collection, insert the documents.
            if let Some(c) = entry.collection {
                let collection = db.collection::<Bson>(c.name.as_str());

                if c.docs.is_empty() {
                    println!(
                        "No documents specified for {}.{}, not inserting anything",
                        entry.db, c.name
                    );
                } else {
                    println!(
                        "\tAttempting to insert documents into {}.{}",
                        entry.db, c.name
                    );
                    let res = collection.insert_many(c.docs).await?;
                    println!(
                        "\tInserted {} documents into {}.{}",
                        res.inserted_ids.len(),
                        entry.db,
                        c.name,
                    );
                }

                // Also write indexes for this collection if any are specified.
                if let Some(indexes) = c.indexes {
                    println!("\tAttempting to create indexes for {}.{}", entry.db, c.name);
                    let res = collection.create_indexes(indexes).await?;
                    println!(
                        "\tCreated indexes {:?} for {}.{}",
                        res.index_names, entry.db, c.name
                    );
                }
            } else if let Some(v) = entry.view {
                if let Some(d) = v.definition {
                    // If this data entry describes a view and a definition is
                    // provided, then create the view.
                    println!(
                        "\tAttempting to create view {} on {}.{}",
                        v.name, entry.db, d.view_on,
                    );
                    db.create_collection(v.name.clone())
                        .view_on(d.view_on.clone())
                        .pipeline(d.pipeline)
                        .await?;
                    println!(
                        "\tSuccessfully created view {} on {}.{}",
                        v.name, entry.db, d.view_on,
                    );
                }
            }
        }
    }

    Ok(())
}

async fn set_schemas_in_adf(client: Client, test_data_files: Vec<TestDataFile>) -> Result<()> {
    for tdf in test_data_files {
        for entry in tdf.dataset {
            // Determine the name of the test data entry collection or view.
            let datasource_name = match (entry.collection, entry.view) {
                (Some(c), None) => c.name,
                (None, Some(v)) => v.name,
                _ => unreachable!("Invariant failed: Each entry must specify exactly one of 'view' or 'collection'."),
            };

            let db: Database;
            let command_doc: Document;
            let command_name: &str;

            match entry.schema {
                Some(schema) => {
                    // If schema is provided, write the schema using sqlSetSchema.
                    db = client.database(entry.db.as_str());
                    command_doc = doc! {"sqlSetSchema": datasource_name.clone(), "schema": {"jsonSchema": schema, "version": 1}};
                    command_name = "sqlSetSchema";
                }
                _ => {
                    // Otherwise, write the schema using sqlGenerateSchema. Note
                    // this must be run against the admin db.
                    db = client.database("admin");
                    command_doc = doc! {"sqlGenerateSchema": 1, "setSchemas": true, "sampleNamespaces": vec![format!("{}.{}", entry.db, datasource_name.clone())]};
                    command_name = "sqlGenerateSchema";
                }
            }

            let res = db.run_command(command_doc).await?;
            println!(
                "\tSet schema for {}.{} via {}\n\t\tResult: {:?}",
                entry.db, datasource_name, command_name, res
            );
        }
    }

    Ok(())
}

async fn set_schemas_in_mongod(client: Client, test_data_files: Vec<TestDataFile>) -> Result<()> {
    for tdf in test_data_files {
        for entry in tdf.dataset {
            // Determine the name of the test data entry collection or view.
            let (datasource_name, datasource_type) = match (entry.collection, entry.view) {
                (Some(c), None) => (c.name, "collection"),
                (None, Some(v)) => (v.name, "view"),
                _ => unreachable!("Invariant failed: Each entry must specify exactly one of 'view' or 'collection'."),
            };

            // Only write schema for entries where it is specified
            match entry.schema {
                Some(schema) => {
                    let db = client.database(entry.db.as_str());
                    let schema_collection = db.collection::<Document>("__sql_schemas");

                    let schema_doc = doc! {
                        "_id": datasource_name.clone(),
                        "type": datasource_type,
                        "schema": schema,
                        "lastUpdated": datetime::DateTime::now(),
                    };

                    let res = schema_collection.insert_one(schema_doc).await?;
                    println!(
                        "\tSet schema for {}.{}\n\t\tResult: {:?}",
                        entry.db, datasource_name, res
                    );
                }
                _ => {
                    println!(
                        "\tSkipping {}.{}: no schema specified",
                        entry.db, datasource_name
                    );
                }
            }
        }
    }
    Ok(())
}
