-- every row in the events report must have a positive count
select event_date, type, event_count
from {{ ref('rpt_events_by_day_type') }}
where event_count <= 0