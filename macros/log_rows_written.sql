{#- Logs how many rows an incremental model appended in this run, so the count shows up in the dbt output. dbt's
    DuckDB adapter doesn't report rows affected for Iceberg tables. Relies on the model writing the run's
    invocation_id to a dbt_invocation_id column. -#}
{% macro log_rows_written() %}
  {%- if execute and config.get('materialized') == 'incremental' -%}
    {%- set rows_written = run_query(
      "select count(*) from " ~ this ~ " where dbt_invocation_id = '" ~ invocation_id ~ "'"
    ).columns[0].values()[0] -%}
    {%- do log(this.identifier ~ ": " ~ rows_written ~ " rows written", info=True) -%}
  {%- endif -%}
{% endmacro %}
