{#- Use the configured schema name as-is (raw, staging, marts, ...) rather than
    dbt's default "<target_schema>_<custom>". In CI each PR still gets its own
    database-level isolation via the snowflake_ci target. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}{{ target.schema }}{%- else -%}{{ custom_schema_name | trim }}{%- endif -%}
{%- endmacro %}
