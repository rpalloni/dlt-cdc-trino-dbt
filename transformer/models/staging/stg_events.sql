select
    message_id
    , type
    , user_id
    , anonymous_id
    , cast(timestamp as timestamp(6)) as event_at
    , cast(date_trunc('day', cast(timestamp as timestamp(6))) as date) as event_date
    , event
    , name as page_name
from {{ source('events', 'events') }}