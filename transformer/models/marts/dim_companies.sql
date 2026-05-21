select
    company_id
    , company_name
    , vat_number
    , country
    , created_at
    , updated_at
from {{ ref('stg_companies') }}