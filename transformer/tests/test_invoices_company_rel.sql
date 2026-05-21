-- every invoice must resolve to a company name (the join in fct_invoices must never produce a null)
select invoice_id
from {{ ref('fct_invoices') }}
where company_name is null