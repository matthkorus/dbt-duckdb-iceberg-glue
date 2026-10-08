{{
    config(
        materialized = 'table',
        catalog_name = 'glue_catalog',
        static_analysis = 'off'
    )
}}

{#- Rula: `int` vs `bigint`. Their tables use Iceberg `int`; check each column (including inside
    structs and arrays of structs) lands in Glue with the type cast here.
    No smallint/tinyint: Iceberg only has int and long, and DuckDB rejects them
    ("Column type SMALLINT is not a valid Iceberg Type"). -#}
select
    1::integer as int_col,
    1::bigint as bigint_col,
    1.5::float as float_col,
    1.5::double as double_col,
    12.34::decimal(10, 2) as decimal_col,
    date '2026-10-01' as date_col,
    timestamptz '2026-10-01 12:00:00+00' as timestamptz_col,
    true as boolean_col,
    {'port': 443::integer, 'bytes': 1024::bigint} as struct_col,
    [{'code': 200::integer, 'count': 5::bigint}] as list_of_struct_col
