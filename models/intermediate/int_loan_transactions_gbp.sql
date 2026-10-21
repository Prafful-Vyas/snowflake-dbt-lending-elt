select
    t.txn_id,
    t.facility_id,
    t.txn_type,
    t.value_date,
    t.amount,
    t.currency,
    t.principal_delta,
    fx.rate                                         as fx_rate_to_gbp,
    cast(cast(t.amount as numeric(38, 10)) * fx.rate as numeric(18, 2))      as amount_gbp,
    t.loaded_at
from {{ ref('stg_loan_transactions') }} t
inner join {{ ref('stg_fx_rates') }} fx
    on fx.rate_date = t.value_date
   and fx.from_currency = t.currency
   and fx.to_currency = 'GBP'
