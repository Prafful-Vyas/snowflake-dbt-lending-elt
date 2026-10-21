select
    trim(facility_id)                           as facility_id,
    trim(counterparty_id)                       as counterparty_id,
    upper(facility_type)                        as facility_type,
    upper(currency)                             as currency,
    cast(committed_limit as numeric(18, 2))     as committed_limit,
    cast(start_date as date)                    as start_date,
    cast(maturity_date as date)                 as maturity_date,
    cast(margin_bps as integer)                 as margin_bps
from {{ source('raw', 'raw_facilities') }}
