{{ config(materialized='ephemeral') }}

{#- CloudTrail to OCSF API Activity (class 6003). Iceberg has no smallint or tinyint, so the OCSF integer
    fields are integer and the long ones bigint. -#}
with events as (
    select
        *,
        case
            when regexp_matches(event_name, '^(Create|Put|Run)') then 1
            when regexp_matches(event_name, '^(Get|List|Describe|Decrypt)') then 2
            when regexp_matches(event_name, '^(Update|Modify)') then 3
            when regexp_matches(event_name, '^Delete') then 4
            else 99
        end::integer as activity_id
    from {{ ref('cloudtrail_events_v2') }}
)

select
    event_time as time,
    6003::integer as class_uid,
    activity_id,
    (600300 + activity_id)::bigint as type_uid,
    1::integer as severity_id,
    {
        'uid': event_id,
        'version': '1.7.0',
        'product': {'name': 'CloudTrail', 'vendor_name': 'AWS'},
        'processed_time': current_timestamp
    } as metadata,
    {
        'user': {
            'name': json_extract_string(user_identity, '$.principalId'),
            'type': json_extract_string(user_identity, '$.type'),
            'uid': json_extract_string(user_identity, '$.arn'),
            'account': {
                'uid': json_extract_string(user_identity, '$.accountId'),
                'org': {
                    'name': 'example-org',
                    'ou': {
                        'uid': 'ou-' || json_extract_string(user_identity, '$.accountId'),
                        'name': json_extract_string(user_identity, '$.sessionContext.sessionIssuer.userName')
                    }
                }
            }
        }
    } as actor,
    {'operation': event_name, 'service': {'name': event_source}} as api,
    {'ip': source_ip_address} as src_endpoint,
    list_transform(
        json_transform(resources, '[{"ARN": "VARCHAR", "type": "VARCHAR", "accountId": "VARCHAR"}]'),
        lambda r: {'uid': r.ARN, 'type': r.type, 'account_uid': r.accountId}
    ) as resources,
    {'provider': 'AWS', 'region': aws_region} as cloud,
    source_sequence
from events
