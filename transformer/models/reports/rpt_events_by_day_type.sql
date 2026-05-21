select
    event_date
    , type
    , count(*) as event_count
from {{ ref('fct_events') }}
group by 1, 2
order by 3 desc