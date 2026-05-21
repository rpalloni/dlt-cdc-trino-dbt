select
    i.invoice_id
    , i.company_id
    , c.company_name
    , i.invoice_number
    , i.amount
    , i.currency
    , i.status
    , i.issued_at
    , i.due_at
    , date_diff('day', i.issued_at, coalesce(i.due_at, i.issued_at)) as payment_terms_days
    , i.created_at
    , i.updated_at
from {{ ref('stg_invoices') }} i
left join {{ ref('stg_companies') }} c
    on c.company_id = i.company_id