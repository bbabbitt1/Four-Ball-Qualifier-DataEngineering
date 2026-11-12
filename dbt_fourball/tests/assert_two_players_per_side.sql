select side_id, count(*) as players
from {{ ref('bridge_side_player') }}
group by side_id
having count(*) != 2
