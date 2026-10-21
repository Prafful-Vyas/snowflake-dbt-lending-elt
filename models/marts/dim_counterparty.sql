-- SCD2 counterparty dimension built from the snapshot. Each counterparty's first
-- version is back-dated to 1900-01-01, so transactions dated before the first
-- snapshot run still resolve to a version.
with versions as (
    select
        *,
        row_number() over (partition by counterparty_id order by dbt_valid_from) as version_no
    from {{ ref('counterparties_snapshot') }}
)

select
    dbt_scd_id                                                            as counterparty_sk,
    counterparty_id,
    legal_name,
    sector,
    country,
    internal_rating,
    tax_id,
    version_no,
    case when version_no = 1 then cast('1900-01-01' as timestamp) else dbt_valid_from end as valid_from,
    coalesce(dbt_valid_to, cast('9999-12-31' as timestamp))              as valid_to,
    dbt_valid_to is null                                                  as is_current
from versions
