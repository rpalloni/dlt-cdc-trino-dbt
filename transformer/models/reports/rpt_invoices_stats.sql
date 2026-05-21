select
    status
    , currency
    , count(*) as invoice_count
    , sum(amount) as total_amount
    , avg(amount) as avg_amount
from  {{ ref('fct_invoices') }}
group by 1, 2
order by 4 desc