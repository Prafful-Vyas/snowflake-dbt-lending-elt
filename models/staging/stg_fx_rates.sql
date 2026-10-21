select
    cast(rate_date as date)                     as rate_date,
    upper(from_currency)                        as from_currency,
    upper(to_currency)                          as to_currency,
    cast(rate as numeric(18, 8))                as rate
from {{ source('raw', 'raw_fx_rates') }}

union all

-- GBP->GBP identity rate for every date, so conversions are a plain inner join.
select distinct
    cast(rate_date as date), 'GBP', 'GBP', cast(1 as numeric(18, 8))
from {{ source('raw', 'raw_fx_rates') }}
