{{
    config(
        materialized = 'table',
        catalog_name = 'glue_catalog',
        tblproperties = {
            'format-version': '2',
            'vacuum_max_snapshot_age_seconds': '300',
            'vacuum_max_metadata_files_to_keep': '10'
        }
    )
}}

{#- Rula: Iceberg format v2 and table properties (their tables set Athena's vacuum_* properties).
    Compare against my_iceberg_model, which sets nothing, to see DuckDB's default format version. -#}
select 1 as id
