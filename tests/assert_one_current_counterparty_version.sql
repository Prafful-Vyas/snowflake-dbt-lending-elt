select counterparty_id, count(*) as current_versions
from {{ ref('dim_counterparty') }}
where is_current
group by counterparty_id
having count(*) <> 1
