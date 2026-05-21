select
    cast(id as bigint)  as company_id
    , name              as company_name
    , vat_number
    , country
    , cast(created_at as timestamp(6)) as created_at
    , cast(updated_at as timestamp(6)) as updated_at
from {{ source('pgsource', 'companies') }}