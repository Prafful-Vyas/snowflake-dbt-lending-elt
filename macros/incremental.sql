{#- Snowflake gets MERGE; DuckDB (local/CI) uses delete+insert. Same unique_key semantics. -#}
{% macro incremental_strategy() -%}
    {{ return('merge' if target.type == 'snowflake' else 'delete+insert') }}
{%- endmacro %}

{#- Rows to (re)process on an incremental run: anything loaded since the latest load
    already in {{ this }}, minus a lookback window for late arrivals.
    `column` is the (possibly aliased) column in the model query; `target_column`
    is its name in the existing table. -#}
{% macro incremental_window(column, target_column) -%}
    {{ column }} >= (
        select {{ dbt.dateadd('day', -1 * var('lookback_days'), 'max(' ~ target_column ~ ')') }} from {{ this }}
    )
{%- endmacro %}
