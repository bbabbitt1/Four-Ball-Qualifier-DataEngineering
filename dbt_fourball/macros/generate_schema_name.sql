{# Use +schema as-is (STAGING / MARTS) instead of dbt's default <target_schema>_<custom>. #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ custom_schema_name | trim if custom_schema_name else target.schema }}
{%- endmacro %}
