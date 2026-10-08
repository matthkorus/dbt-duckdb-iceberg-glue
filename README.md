# dbt + DuckDB → Apache Iceberg on AWS Glue

A working example of **dbt v2 (Fusion)** using its **native DuckDB adapter** to build Apache Iceberg tables in the **AWS Glue Data Catalog** (via Glue's Iceberg REST endpoint). Tables are queryable from Athena, Spark, or anything else that reads Glue Iceberg tables.

Getting this working needed several settings and one workaround macro that aren't in the dbt docs yet. They're all explained below.

Tested with dbt 2.0.4, 2.0.6 and 2.0.8 (macOS).

## Setup

1. **dbt v2:** `brew install dbt` (or `dbt system update`). `dbt --version` should print `dbt 2.x`. The DuckDB adapter is built in, with no `pip install`.
2. **Config:** copy `.env.example` to `.env` and fill in your Glue account ID, S3 location root and Glue database. dbt loads `.env` automatically. The Glue database must already exist.
3. **AWS credentials:** anything the AWS SDK credential chain understands works: env vars, `AWS_PROFILE`, SSO, or an ECS credential server. With aws-vault, use `aws-vault exec --ecs-server <profile>` so credentials refresh instead of expiring after an hour.
4. **Run:** `dbt build`

## What's needed for Glue (and why)

| Where | Setting | Why |
|---|---|---|
| `dbt_project.yml` | `flags: use_catalogs_v2: true` | `catalogs.yml` support for DuckDB |
| `catalogs.yml` | `type: iceberg_rest` + explicit `endpoint` + `authorization_type: SIGV4` | `type: glue` and `endpoint_type: GLUE` are rejected for DuckDB (tested through dbt 2.0.8) |
| `catalogs.yml` | `stage_create_tables: false` | Glue: `400 Stage create is not supported` |
| `catalogs.yml` | `disable_multi_table_commit: true` | Without it, builds "succeed" but **rows are never committed** (empty tables) |
| `catalogs.yml` | no `default_region` | DuckDB's ATTACH rejects it |
| `profiles.yml` | `type: s3` secret with `provider: credential_chain` | Glue uses SigV4, not the OAuth2 `iceberg` secret from the docs |
| `profiles.yml` | target `schema` = Glue database | Models are created in that Glue database |
| `dbt_project.yml` | `+sql_header: "set TimeZone = 'UTC';"` | dbt creates `timestamptz` columns as `timestamp`, converting with the machine's local time zone. Without this, timestamps and `day()` partitions shift. `profiles.yml` `settings:` and pre-hooks don't work for this |
| `macros/duckdb__create_table_as.sql` | wrapper macro | See below |

### The macro workaround

Glue's Iceberg REST API requires a `location` on every create table, and dbt's DuckDB adapter doesn't send one ([dbt-labs/dbt#15268](https://github.com/dbt-labs/dbt/issues/15268)). It also has no partitioning or table-properties config for Iceberg. [`macros/duckdb__create_table_as.sql`](macros/duckdb__create_table_as.sql) wraps the built-in macro and appends DuckDB table clauses to the `create table`, driven by model config:

| Config | Adds | Example |
|---|---|---|
| `location_root` | `with ('location' = '<root>/<table>')` | set project-wide in `dbt_project.yml` |
| `partition_by` | `partitioned by (...)` | `partition_by = ['day(time)']` |
| `tblproperties` | extra `with (...)` properties | `tblproperties = {'format-version': '2'}` |

It only applies to Iceberg catalog tables, so local DuckDB tables are unaffected. Remove it once the issue is fixed.

## Models

| Model | Tests |
|---|---|
| `my_iceberg_model` | Basic table in Glue |
| `struct_string_parsed` | Parsing a JSON string column (from an existing Glue table) into a typed struct |
| `partition_test` | `day(time)` partitioning |
| `partition_transforms_test` | `hour`, `month`, `bucket`, identity partitioning |
| `types_test` | Iceberg type mapping (`int` vs `long`, decimals, timestamps, nested) |
| `nested_deep_test` | Deep nesting, arrays of structs, `metadata.processed_time` |
| `table_properties_test` | Format version + table properties |
| `incremental_append_test` | Append-only incremental loads into a partitioned table |

`struct_string_parsed` reads an existing table (`struct_string_test`) with a JSON string column `a`, so exclude it if you don't have one.

## Gotchas

- Iceberg has no `smallint`/`tinyint`. Cast to `integer`, or DuckDB fails with `Column type SMALLINT is not a valid Iceberg Type`.
- Fusion rejects unknown keys in `config()`. The macro uses keys Fusion already knows from other adapters.
- Models that build or read struct fields need `static_analysis = 'off'` (Fusion can't infer `json_transform` / struct literal types).
- DuckDB names partition fields `<transform>_<column>_<id>` (e.g. `day_time_2`), not Iceberg Java's `<column>_day`. It's cosmetic.
- Setting a Location on the Glue database doesn't help with the location requirement. Glue's REST API doesn't fall back to it.
