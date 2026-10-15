{{ config(materialized='incremental', incremental_strategy='append', partition_by=['day(event_time)']) }}

{#- One row per CloudTrail event, from the Etleap pipeline that splits each CloudTrail file's Records array into
    rows, so this model only renames and types columns. Nested objects such as userIdentity arrive as JSON strings.

    Etleap gives every row a `_sequence`, a UUIDv7 taken when the row is loaded, so later loads have larger
    values. Each run reads only rows past the largest `_sequence` already in this table. The watermark is
    fetched first and inlined as a literal so that DuckDB can skip the Iceberg data files whose `_sequence`
    bounds are below it, instead of reading the whole source table. -#}
{% set watermark = none %}
{% if execute and is_incremental() %}
    {% set watermark = run_query('select max(source_sequence) from ' ~ this).columns[0].values()[0] %}
{% endif %}

select
    eventid as event_id,
    eventtime::timestamptz as event_time,
    eventsource as event_source,
    eventname as event_name,
    awsregion as aws_region,
    sourceipaddress as source_ip_address,
    useragent as user_agent,
    recipientaccountid as recipient_account_id,
    useridentity as user_identity,
    requestparameters as request_parameters,
    resources,
    file_path_hash as source_file_hash,
    _sequence as source_sequence,
    '{{ invocation_id }}' as dbt_invocation_id
from {{ source('etleap_cloudtrail', 'cloudtrail_events_raw') }}
where not coalesce(_is_delete, false)
{% if watermark %}
and _sequence > '{{ watermark }}'
{% endif %}
