{#- static_analysis off: dbt can't infer the struct type json_transform returns, so record.<field> fails strict analysis -#}
{{
    config(
        materialized = 'table',
        catalog_name = 'glue_catalog',
        static_analysis = 'off'
    )
}}

{#- Name of the JSON string column in struct_string_test -#}
{%- set json_column = 'a' -%}

with source as (

    select * from {{ source('glue', 'struct_string_test') }}

),

parsed as (

    select
        json_transform({{ json_column }}, '{
            "id": "INTEGER",
            "name": "VARCHAR",
            "active": "BOOLEAN",
            "score": "DOUBLE",
            "created_at": "TIMESTAMPTZ",
            "address": {"street": "VARCHAR", "city": "VARCHAR", "zip": "VARCHAR"},
            "tags": ["VARCHAR"]
        }') as record
    from source

)

select
    record.id,
    record
from parsed
