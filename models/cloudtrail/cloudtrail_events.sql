{{ config(materialized='incremental', incremental_strategy='append', partition_by=['day(event_time)']) }}

{#- One row per CloudTrail event. The Etleap pipeline loads each CloudTrail file as one row, with the whole
    file's JSON in `data`, because splitting the Records array into rows isn't supported in Flink pipelines.

    Etleap gives every row a `_sequence`, a UUIDv7 taken when the row is loaded, so later loads have larger
    values. Each run reads only rows past the largest `_sequence` already in this table. The watermark is
    fetched first and inlined as a literal so that DuckDB can skip the Iceberg data files whose `_sequence`
    bounds are below it, instead of reading the whole source table.

    A run takes at most `max_files_per_run` files, oldest first. One CloudTrail file can hold tens of MB of
    JSON, and unpacking a whole backlog at once runs out of memory, so a backlog is worked off over several
    runs. -#}
{% set watermark = none %}
{% if execute and is_incremental() %}
    {% set watermark = run_query('select max(source_sequence) from ' ~ this).columns[0].values()[0] %}
{% endif %}

with files as (
    select file_path_hash, _sequence, data
    from {{ source('glue', 'cloudtrail_raw') }}
    where not coalesce(_is_delete, false)
    {% if watermark %}
    and _sequence > '{{ watermark }}'
    {% endif %}
    order by _sequence
    limit {{ var('max_files_per_run', 10) }}
),

records as (
    select file_path_hash, _sequence, unnest(json_extract(data, '$.Records')::json[]) as r
    from files
)

select
    json_extract_string(r, '$.eventID') as event_id,
    json_extract_string(r, '$.eventTime')::timestamptz as event_time,
    json_extract_string(r, '$.eventSource') as event_source,
    json_extract_string(r, '$.eventName') as event_name,
    json_extract_string(r, '$.awsRegion') as aws_region,
    json_extract_string(r, '$.sourceIPAddress') as source_ip_address,
    json_extract_string(r, '$.userAgent') as user_agent,
    json_extract_string(r, '$.recipientAccountId') as recipient_account_id,
    json_extract(r, '$.userIdentity')::varchar as user_identity,
    json_extract(r, '$.requestParameters')::varchar as request_parameters,
    json_extract(r, '$.resources')::varchar as resources,
    file_path_hash as source_file_hash,
    _sequence as source_sequence,
    '{{ invocation_id }}' as dbt_invocation_id
from records
