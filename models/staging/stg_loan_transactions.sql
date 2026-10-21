-- Source can resend a transaction (corrections); keep the latest load per txn_id.
with ranked as (
    select
        trim(txn_id)                            as txn_id,
        trim(facility_id)                       as facility_id,
        upper(txn_type)                         as txn_type,
        cast(value_date as date)                as value_date,
        cast(amount as numeric(18, 2))          as amount,
        upper(currency)                         as currency,
        cast(loaded_at as timestamp)            as loaded_at,
        row_number() over (partition by txn_id order by loaded_at desc) as rn
    from {{ source('raw', 'raw_loan_transactions') }}
)

select
    txn_id,
    facility_id,
    txn_type,
    value_date,
    amount,
    currency,
    -- Principal movement: drawdowns increase the drawn balance, repayments reduce it.
    -- Interest and fees are income and never touch principal.
    case txn_type
        when 'DRAWDOWN' then amount
        when 'REPAYMENT' then -amount
        else 0
    end                                         as principal_delta,
    loaded_at
from ranked
where rn = 1
