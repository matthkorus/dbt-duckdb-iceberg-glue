{{
    config(
        materialized = 'table',
        catalog_name = 'glue_catalog',
        partition_by = ['day(time)']
    )
}}

{#- Tests Rula's partition spec: PARTITIONED BY (day(time)), 3 days of data -#}
select
    i as id,
    timestamptz '2026-10-01 00:00:00+00' + to_hours(i * 7) as time,
    'event ' || i as message
from range(10) as t(i)
