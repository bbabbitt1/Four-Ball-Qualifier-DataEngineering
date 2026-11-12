-- No player IDs exist in any source: natural key = name + hometown.
-- ponytail: same person with a different/blank hometown = 2 players. Fuzzy dedupe if reports need it.
select
    player_key,
    any_value(player_name) as player_name,
    any_value(player_from) as player_from,
    any_value(trim(split_part(player_from, ',', -1))) as player_state,
    count(*) as sides_played
from {{ ref('bridge_side_player') }}
group by player_key
