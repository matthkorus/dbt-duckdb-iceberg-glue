{{
    config(
        materialized = 'table',
        catalog_name = 'glue_catalog',
        partition_by = ['day(time)'],
        static_analysis = 'off'
    )
}}

{#- Rula: deep OCSF-style nesting, arrays of structs, and `metadata.processed_time` (ingestion time,
    added by Cribl today). Their tables nest up to 12 levels; this goes 6 deep plus lists of structs. -#}
select
    timestamptz '2026-10-01 00:00:00+00' + to_hours(i * 7) as time,
    6003::integer as class_uid,
    {
        'product': {'name': 'CloudTrail', 'vendor_name': 'AWS'},
        'version': '1.7.0',
        'processed_time': current_timestamp
    } as metadata,
    {
        'user': {
            'name': 'user_' || i,
            'account': {
                'uid': '123456789012',
                'org': {
                    'name': 'example_org',
                    'ou': {'uid': 'ou-' || i, 'name': 'level 6'}
                }
            }
        },
        'session': {'uid': 'session_' || i, 'is_mfa': i % 2 = 0}
    } as actor,
    [
        {'name': 'resource_a', 'type': 'bucket', 'tags': [{'key': 'env', 'value': 'test'}]},
        {'name': 'resource_b', 'type': 'role', 'tags': []::struct("key" varchar, "value" varchar)[]}
    ] as resources
from range(10) as t(i)
