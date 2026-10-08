{{
    config(
        materialized = 'incremental',
        incremental_strategy = 'append',
        catalog_name = 'glue_catalog',
        partition_by = ['day(time)']
    )
}}

{#- Rula: ongoing append-only loads into a partitioned table. Each run appends 5 rows tagged with
    the run's invocation_id, so the row count should grow by 5 per `dbt run`. -#}
select
    '{{ invocation_id }}' as run_id,
    i as id,
    current_timestamp as time
from range(5) as t(i)
