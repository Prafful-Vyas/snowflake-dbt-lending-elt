with spine as (
    {{ dbt.date_spine('day', "cast('2025-01-01' as date)", "cast('2027-12-31' as date)") }}
)

select
    cast(date_day as date)                                                as date_day,
    cast({{ dbt.date_trunc('month', 'date_day') }} as date)               as month_start,
    cast({{ dbt.last_day('date_day', 'month') }} as date)                 as month_end,
    extract(year from date_day)                                           as calendar_year,
    extract(quarter from date_day)                                        as calendar_quarter,
    extract(month from date_day)                                          as calendar_month,
    cast(date_day as date) = cast({{ dbt.last_day('date_day', 'month') }} as date) as is_month_end
from spine
