{{ config(
    materialized='incremental',
    unique_key=['facility_id', 'balance_date'],
    incremental_strategy=incremental_strategy()
) }}

select
    b.facility_id,
    b.counterparty_id,
    b.balance_date,
    b.currency,
    b.committed_limit,
    b.drawn_balance,
    b.committed_limit - b.drawn_balance                                    as undrawn_amount,
    cast(100.0 * b.drawn_balance / nullif(b.committed_limit, 0) as numeric(9, 4)) as utilisation_pct,
    cast(cast(b.drawn_balance as numeric(38, 10)) * fx.rate as numeric(18, 2))                      as drawn_balance_gbp,
    cast(cast(b.committed_limit as numeric(38, 10)) * fx.rate as numeric(18, 2))                    as committed_limit_gbp
from {{ ref('int_facility_daily_balance') }} b
inner join {{ ref('stg_fx_rates') }} fx
    on fx.rate_date = b.balance_date
   and fx.from_currency = b.currency
   and fx.to_currency = 'GBP'
where b.balance_date <= cast('{{ var("as_of_date") }}' as date)
{% if is_incremental() %}
  and b.balance_date >= (select {{ dbt.dateadd('day', -1 * var('lookback_days'), 'max(balance_date)') }} from {{ this }})
{% endif %}
