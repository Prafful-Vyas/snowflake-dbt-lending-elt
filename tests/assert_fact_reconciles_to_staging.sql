-- Reconciliation: the fact table holds exactly the staged transactions, by type,
-- in count and amount. Any difference is returned as a failing row.
with src as (
    select txn_type, count(*) as n, sum(amount) as amount
    from {{ ref('stg_loan_transactions') }}
    group by txn_type
),
tgt as (
    select txn_type, count(*) as n, sum(amount) as amount
    from {{ ref('fct_loan_transactions') }}
    group by txn_type
)
select coalesce(s.txn_type, t.txn_type) as txn_type, s.n as src_n, t.n as tgt_n, s.amount as src_amount, t.amount as tgt_amount
from src s
full outer join tgt t on s.txn_type = t.txn_type
where s.n is distinct from t.n or s.amount is distinct from t.amount
