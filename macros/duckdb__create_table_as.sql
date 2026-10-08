{#- Workaround for https://github.com/dbt-labs/dbt/issues/15268
    dbt's DuckDB adapter sends a bare `create table (...)` to Iceberg catalogs, with no way to add
    table clauses. This wraps the built-in macro and adds them to the create-then-insert path used
    for Glue:
      - `location_root`: Glue's Iceberg REST endpoint requires a table location on createTable.
        Adds WITH ('location' = '<location_root>/<table>').
      - `partition_by`: list of Iceberg partition transforms, e.g. ['day(time)'].
        Adds PARTITIONED BY (...). DuckDB requires it before WITH.
      - `tblproperties`: dict of Iceberg table properties, e.g. {'format-version': '2'}.
        Added to the same WITH (...) as the location.
    Remove once the adapter supports these natively. -#}
{% macro duckdb__create_table_as(temporary, relation, compiled_code, language='sql') -%}
  {%- set sql = dbt.duckdb__create_table_as(temporary, relation, compiled_code, language) -%}
  {%- if not temporary and language == 'sql'
        and adapter.build_catalog_relation(config.model).duckdb_write_strategy == 'direct_create' -%}
    {%- set clauses = [] -%}
    {%- set partition_by = config.get('partition_by') -%}
    {%- if partition_by -%}
      {%- set partition_by = [partition_by] if partition_by is string else partition_by -%}
      {%- do clauses.append('partitioned by (' ~ partition_by | join(', ') ~ ')') -%}
    {%- endif -%}
    {%- set properties = [] -%}
    {%- set location_root = config.get('location_root') -%}
    {%- if location_root -%}
      {%- do properties.append("'location' = '" ~ location_root.rstrip('/') ~ '/' ~ relation.identifier ~ "'") -%}
    {%- endif -%}
    {%- for key, value in (config.get('tblproperties') or {}).items() -%}
      {%- do properties.append("'" ~ key ~ "' = '" ~ value ~ "'") -%}
    {%- endfor -%}
    {%- if properties -%}
      {%- do clauses.append('with (' ~ properties | join(', ') ~ ')') -%}
    {%- endif -%}
    {%- if clauses -%}
      {%- set sql = add_iceberg_create_clauses(sql, clauses | join(' ')) -%}
    {%- endif -%}
  {%- endif -%}
  {{ sql }}
{%- endmacro %}

{#- Appends clauses after the column list of the first `create table ... (<columns>);` statement -#}
{% macro add_iceberg_create_clauses(sql, clauses) -%}
  {{ modules.re.sub("(create\\s+table\\s+[^;]*?\\))\\s*;", "\\1 " ~ clauses ~ ";", sql, count=1, flags=modules.re.IGNORECASE) }}
{%- endmacro %}
