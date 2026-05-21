select
    message_id
    , type
    , user_id
    , anonymous_id
    , event_at
    , event_date
    , case
        when type = 'track' then event
        when type = 'identify' then 'identify'
        when type = 'page' then 'page_view'
        else 'unknown'
    end as event_category
    , page_name
from {{ ref('stg_events') }}