-- Month-end drawn and committed exposure (GBP) by sector and internal rating, using
-- the rating that was in force at each month end.
select
    d.month_end,
    c.sector,
    c.internal_rating,
    count(distinct b.facility_id)                                          as facilities,
    count(distinct b.counterparty_id)                                      as counterparties,
    sum(b.drawn_balance_gbp)                                               as drawn_gbp,
    sum(b.committed_limit_gbp)                                             as committed_gbp,
    cast(100.0 * sum(b.drawn_balance_gbp) / nullif(sum(b.committed_limit_gbp), 0) as numeric(9, 4)) as utilisation_pct
from {{ ref('fct_facility_balance_daily') }} b
inner join {{ ref('dim_date') }} d
    on d.date_day = b.balance_date
   and d.is_month_end
inner join {{ ref('dim_counterparty') }} c
    on c.counterparty_id = b.counterparty_id
   and cast(b.balance_date as timestamp) >= c.valid_from
   and cast(b.balance_date as timestamp) < c.valid_to
group by d.month_end, c.sector, c.internal_rating
