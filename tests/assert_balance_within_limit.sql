-- Drawn balance must stay between zero and the committed limit on every day.
select facility_id, balance_date, drawn_balance, committed_limit
from {{ ref('fct_facility_balance_daily') }}
where drawn_balance < 0
   or drawn_balance > committed_limit
