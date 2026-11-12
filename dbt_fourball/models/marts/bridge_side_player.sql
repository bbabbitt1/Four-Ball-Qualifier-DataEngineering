with slots as (
    select side_id, 1 as player_slot, player1 as player_name, player1_from as player_from from {{ ref('stg_scores') }}
    union all
    select side_id, 2, player2, player2_from from {{ ref('stg_scores') }}
)
select
    side_id,
    {{ dbt_utils.generate_surrogate_key(['lower(player_name)', "lower(coalesce(player_from, ''))"]) }} as player_key,
    player_slot, player_name, player_from
from slots
where player_name is not null
