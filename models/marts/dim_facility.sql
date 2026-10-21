select
    facility_id,
    counterparty_id,
    facility_type,
    currency,
    committed_limit,
    start_date,
    maturity_date,
    margin_bps,
    {{ dbt.datediff('start_date', 'maturity_date', 'day') }} as tenor_days
from {{ ref('stg_facilities') }}
