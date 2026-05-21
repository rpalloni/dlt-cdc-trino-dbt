select
    country
    , count(*) as company_count
from {{ ref('dim_companies') }}
group by 1
order by 2 desc