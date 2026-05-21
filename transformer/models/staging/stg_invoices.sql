select
    cast(id as bigint) as invoice_id
    , cast(company_id as bigint) as company_id
    , invoice_number
    , cast(amount as decimal(12,2)) as amount
    , currency
    , status
    , cast(issued_at as date) as issued_at
    , cast(due_at as date) as due_at
    , cast(created_at as timestamp(6)) as created_at
    , cast(updated_at as timestamp(6)) as updated_at
from {{ source('pgsource', 'invoices') }}