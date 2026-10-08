{{
    config(
        materialized = 'table',
        catalog_name = 'glue_catalog',
        partition_by = ['hour(event_hour)', 'month(event_month)', 'bucket(4, id)', 'category'],
        static_analysis = 'off'
    )
}}

{#- Rula: partition transforms beyond day(): hour, month, bucket, identity. Separate source columns,
    since Iceberg doesn't allow two time transforms on the same column. -#}
select
    i as id,
    timestamptz '2026-10-01 00:00:00+00' + to_minutes(i * 37) as event_hour,
    timestamptz '2026-08-15 00:00:00+00' + to_days(i * 11) as event_month,
    case when i % 3 = 0 then 'auth' when i % 3 = 1 then 'network' else 'api' end as category
from range(20) as t(i)
