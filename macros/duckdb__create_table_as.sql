{#- Creates Iceberg tables in a Glue catalog, which dbt's DuckDB adapter can't do on its own yet
    (https://github.com/dbt-labs/dbt/issues/15268):
      - Glue's Iceberg REST endpoint requires a table location on create table. `location_root` adds
        WITH ('location' = '<location_root>/<table>').
      - The adapter writes the column types of the create table in its own form, which narrows bigint to integer
        and writes structs in a form DuckDB rejects. The column types come from DuckDB instead (DESCRIBE of the
        model query).
      - `partition_by`, for example ['day(time)'], adds PARTITIONED BY (...). DuckDB requires it before WITH.
      - `tblproperties`, for example {'format-version': '2'}, adds table properties to the same WITH (...).
    Temporary tables, contract-enforced models and tables outside an Iceberg catalog use the built-in macro. -#}
{% macro duckdb__create_table_as(temporary, relation, compiled_code, language='sql') -%}
  {%- if not temporary and language == 'sql' and not config.get('contract').enforced
        and adapter.build_catalog_relation(config.model).duckdb_write_strategy == 'direct_create' -%}
    {{ iceberg_create_table_as(relation, compiled_code) }}
  {%- else -%}
    {{ dbt.duckdb__create_table_as(temporary, relation, compiled_code, language) }}
  {%- endif -%}
{%- endmacro %}

{% macro iceberg_create_table_as(relation, compiled_code) -%}
  {%- set sql_header = config.get('sql_header', none) -%}
  {%- set columns = [] -%}
  {%- if execute -%}
    {%- for row in run_query('describe select * from (\n' ~ compiled_code ~ '\n)') -%}
      {%- do columns.append({'name': row['column_name'], 'type': row['column_type']}) -%}
    {%- endfor -%}
  {%- endif -%}
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

  {{ sql_header if sql_header is not none }}
  create table {{ relation.include(database=True, schema=True) }} (
    {%- for column in columns %}
    {{ adapter.quote(column.name) }} {{ column.type }}{{ "," if not loop.last }}
    {%- endfor %}
  ) {{ clauses | join(' ') }};
  insert into {{ relation }} (
    {%- for column in columns %}
    {{ adapter.quote(column.name) }}{{ "," if not loop.last }}
    {%- endfor %}
  ) (
    {{ compiled_code }}
  );
{%- endmacro %}
