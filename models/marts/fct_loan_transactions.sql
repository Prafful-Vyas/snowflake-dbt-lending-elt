{{ config(
    materialized='incremental',
    unique_key='txn_id',
    incremental_strategy=incremental_strategy(),
    on_schema_change='append_new_columns'
) }}

select
    t.txn_id,
    t.facility_id,
    c.counterparty_sk,
    t.value_date,
    t.txn_type,
    t.amount,
    t.currency,
    t.fx_rate_to_gbp,
    t.amount_gbp,
    t.principal_delta,
    t.loaded_at
from {{ ref('int_loan_transactions_gbp') }} t
inner join {{ ref('stg_facilities') }} f
    on f.facility_id = t.facility_id
-- As-of join: the counterparty version that was valid on the value date.
left join {{ ref('dim_counterparty') }} c
    on c.counterparty_id = f.counterparty_id
   and cast(t.value_date as timestamp) >= c.valid_from
   and cast(t.value_date as timestamp) < c.valid_to
{% if is_incremental() %}
where {{ incremental_window('t.loaded_at', 'loaded_at') }}
{% endif %}
