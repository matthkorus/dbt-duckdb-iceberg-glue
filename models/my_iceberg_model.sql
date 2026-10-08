{{
    config(
        materialized = 'table',
        catalog_name = 'glue_catalog'
    )
}}

select 1 as id, 'hello iceberg' as message
