{#- Ratings and sector re-classifications change exposure reporting, so every
    change is versioned (SCD2). check strategy: the source has no reliable
    change timestamp for these attributes. -#}
{% snapshot counterparties_snapshot %}
{{ config(
    unique_key='counterparty_id',
    strategy='check',
    check_cols=['legal_name', 'sector', 'country', 'internal_rating'],
    invalidate_hard_deletes=True
) }}
select * from {{ ref('stg_counterparties') }}
{% endsnapshot %}
