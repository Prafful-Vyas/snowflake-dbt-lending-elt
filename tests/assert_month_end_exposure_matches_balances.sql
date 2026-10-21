-- The exposure mart must add up to the facility balances it aggregates.
with mart as (
    select month_end, sum(drawn_gbp) as drawn_gbp from {{ ref('mart_exposure_by_sector_rating') }} group by month_end
),
bal as (
    select b.balance_date as month_end, sum(b.drawn_balance_gbp) as drawn_gbp
    from {{ ref('fct_facility_balance_daily') }} b
    inner join {{ ref('dim_date') }} d on d.date_day = b.balance_date and d.is_month_end
    group by b.balance_date
)
select m.month_end, m.drawn_gbp, b.drawn_gbp as balance_drawn_gbp
from mart m full outer join bal b on m.month_end = b.month_end
where m.drawn_gbp is distinct from b.drawn_gbp
