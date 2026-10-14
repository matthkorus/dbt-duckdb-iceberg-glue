{{ config(materialized='incremental', incremental_strategy='append', partition_by=['day(time)']) }}

{#- CloudTrail events as OCSF API Activity. Appends only events that earlier runs have not loaded. CloudTrail
    delivers some events more than once, so events are also deduplicated within a run. -#}
select
    *,
    '{{ invocation_id }}' as dbt_invocation_id
from {{ ref('ocsf_api_activity_mapped') }} as new_events
{% if is_incremental() %}
where not exists (select 1 from {{ this }} as loaded where loaded.metadata.uid = new_events.metadata.uid)
{% endif %}
qualify row_number() over (partition by metadata.uid order by time) = 1
