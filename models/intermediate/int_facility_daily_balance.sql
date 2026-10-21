-- One row per facility per calendar day while the facility is live. The drawn
-- balance is carried forward on days without movements.
with spine as (
    {{ dbt.date_spine(
        'day',
        "cast('2025-01-01' as date)",
        dbt.dateadd('day', 1, "cast('" ~ var('as_of_date') ~ "' as date)")
    ) }}
),

moves as (
    select facility_id, value_date, sum(principal_delta) as principal_delta
    from {{ ref('stg_loan_transactions') }}
    group by facility_id, value_date
),

grid as (
    select
        f.facility_id,
        f.counterparty_id,
        f.currency,
        f.committed_limit,
        cast(s.date_day as date) as balance_date
    from {{ ref('stg_facilities') }} f
    inner join spine s
        on cast(s.date_day as date) >= f.start_date
       and cast(s.date_day as date) <= f.maturity_date
)

select
    g.facility_id,
    g.counterparty_id,
    g.currency,
    g.committed_limit,
    g.balance_date,
    sum(coalesce(m.principal_delta, 0)) over (
        partition by g.facility_id order by g.balance_date
        rows between unbounded preceding and current row
    ) as drawn_balance
from grid g
left join moves m
    on m.facility_id = g.facility_id
   and m.value_date = g.balance_date
