-- One row per qualifier: strength of field from WAGR-ranked entrants, using the ranking in effect on the qualifier date.
-- Player points = 1/sqrt(rank) (#1 = 1.0, #100 = 0.1, #2500 = 0.02, unranked = 0). Both partners count fully.
-- Pros/reinstated amateurs (no WAGR) get an equivalent rank from tour starts (seeds/pro_experience.csv, reviewed rows only).
-- A player with both counts at the better of the two.
with pro as (
    select
        lower(player_name) as name_key,
        min(case
            when pga_tour_starts >= 50 then 25
            when pga_tour_starts >= 1 or korn_ferry_starts >= 25 then 100
            when korn_ferry_starts >= 1 or americas_starts >= 10 then 500
        end) as pro_equiv_rank            -- null = too light to count (e.g. a few PGA Tour Americas starts)
    from {{ ref('pro_experience') }}
    where is_match = 'y'
    group by 1
),

players as (
    select
        s.qualifier_key,
        s.championship_year,
        b.side_id,
        -- WAGR publishes Wednesdays, labelled one ISO week back: release in effect = ISO week of (date - 9 days). Same as wagr.py.
        yearofweekiso(dateadd(day, -9, s.qualifier_date)) * 100 + weekiso(dateadd(day, -9, s.qualifier_date)) as wagr_week,
        w.wagr_rank,
        pro.pro_equiv_rank,
        least(coalesce(w.wagr_rank, pro.pro_equiv_rank), coalesce(pro.pro_equiv_rank, w.wagr_rank)) as effective_rank
    from {{ ref('bridge_side_player') }} b
    join {{ ref('stg_scores') }} s using (side_id)
    -- ponytail: name-only match; a common name can hit a ranked namesake. Upgrade: WAGR profile hometown.
    left join {{ ref('stg_wagr') }} w
        on w.wagr_week = yearofweekiso(dateadd(day, -9, s.qualifier_date)) * 100 + weekiso(dateadd(day, -9, s.qualifier_date))
       and lower(w.player_name) = lower(b.player_name)
    left join pro on pro.name_key = lower(b.player_name)
),

sides as (
    select
        qualifier_key, side_id,
        any_value(championship_year) as championship_year,
        any_value(wagr_week) as wagr_week,
        count(*) as players,
        count(wagr_rank) as ranked_players,
        count_if(pro_equiv_rank is not null and (wagr_rank is null or pro_equiv_rank < wagr_rank)) as pro_players,   -- pro tier set their points
        count(effective_rank) as rated_players,
        min(wagr_rank) as best_rank,
        coalesce(sum(1 / sqrt(effective_rank)), 0) as side_points
    from players
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
