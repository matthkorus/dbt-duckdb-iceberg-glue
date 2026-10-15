{{ config(materialized='incremental', incremental_strategy='append', partition_by=['day(time)']) }}

{#- CloudTrail events as OCSF API Activity. Each run maps only the bronze rows past the largest
    `source_sequence` already in this table, inlined as a literal so DuckDB can skip older bronze data files.

    CloudTrail delivers some events more than once, sometimes in different files, so events are deduplicated
    within the run and against events already loaded. That check only reads loaded events from the earliest
    event time in the new rows onward, so it is limited to the recent day(time) partitions. -#}
{% set events = ref('cloudtrail_events_v2') %}
{% set watermark = none %}
{% set earliest_new_time = none %}
{% if execute and is_incremental() %}
    {% set watermark = run_query('select max(source_sequence) from ' ~ this).columns[0].values()[0] %}
    {% if watermark %}
        {% set earliest_new_time = run_query(
            "select min(event_time) from " ~ events ~ " where source_sequence > '" ~ watermark ~ "'"
        ).columns[0].values()[0] %}
    {% endif %}
{% endif %}

with new_events as (
    select *
    from {{ ref('ocsf_api_activity_mapped') }}
    {% if watermark %}
    where source_sequence > '{{ watermark }}'
    {% endif %}
)

select
    *,
    '{{ invocation_id }}' as dbt_invocation_id
from new_events
{% if is_incremental() %}
where not exists (
    select 1
    from {{ this }} as loaded
    where loaded.metadata.uid = new_events.metadata.uid
    {% if earliest_new_time %}
    and loaded.time >= '{{ earliest_new_time }}'::timestamptz
    {% endif %}
)
{% endif %}
qualify row_number() over (partition by metadata.uid order by time) = 1
