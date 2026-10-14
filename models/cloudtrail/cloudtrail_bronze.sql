{{ config(materialized='incremental', incremental_strategy='append', partition_by=['day(event_time)']) }}

{#- One row per CloudTrail event. The Etleap pipeline loads each CloudTrail file as one row, with the whole
    file's JSON in `data`, because splitting the Records array into rows isn't supported in Flink pipelines.
    Each run only reads files that earlier runs haven't loaded, identified by file_path_hash. CloudTrail never
    rewrites a delivered file, so a file is either fully loaded or not loaded at all. -#}
with files as (
    select file_path_hash, data
    from {{ source('glue', 'cloudtrail_raw') }}
    where not coalesce(_is_delete, false)
    {% if is_incremental() %}
    and file_path_hash not in (select distinct source_file_hash from {{ this }})
    {% endif %}
),

records as (
    select file_path_hash, unnest(json_extract(data, '$.Records')::json[]) as r
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
    '{{ invocation_id }}' as dbt_invocation_id
from records
