-- One row per qualifier: strength of field from WAGR-ranked entrants, using the ranking in effect on the qualifier date.
-- Per-player ranks and points come from fct_field_player_rank (1/sqrt(rank), pros at a tour-starts equivalent). Both partners count fully.
with sides as (
    select
        qualifier_key, side_id,
        any_value(championship_year) as championship_year,
        any_value(wagr_week) as wagr_week,
        count(*) as players,
        count(wagr_rank) as ranked_players,
        count_if(is_pro_rank) as pro_players,
        count(effective_rank) as rated_players,
        min(wagr_rank) as best_rank,
        sum(points) as side_points
    from {{ ref('fct_field_player_rank') }}
    group by qualifier_key, side_id
),

per_qualifier as (
    select
        qualifier_key,
        any_value(championship_year) as championship_year,
        any_value(wagr_week) as wagr_week,
        count(*) as field_sides,          -- every entered side, incl. WD/NS
        sum(players) as field_players,
        sum(ranked_players) as ranked_players,
        sum(pro_players) as pro_players,
        count_if(rated_players > 0) as ranked_sides,        -- WAGR or pro tier
        count_if(rated_players = 2) as sides_with_two_ranked,
        min(best_rank) as best_rank,
        sum(side_points) as wagr_points,
        avg(side_points) as wagr_points_per_side
    from sides
    group by qualifier_key
)

select
    *,
    ranked_players / field_players as pct_players_ranked,
    -- per-side so big fields aren't "stronger" just for being big; vs same-season qualifiers. > 0 = stronger than usual.
    (wagr_points_per_side - avg(wagr_points_per_side) over (partition by championship_year))
        / nullif(stddev_samp(wagr_points_per_side) over (partition by championship_year), 0) as wagr_strength_z
from per_qualifier
