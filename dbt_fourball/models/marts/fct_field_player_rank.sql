-- One row per player per side: WAGR rank in effect on the qualifier date, pro-equivalent rank, and strength-of-field points.
-- Player points = 1/sqrt(rank) (#1 = 1.0, #100 = 0.1, #2500 = 0.02, unranked = 0).
-- Pros/reinstated amateurs (no WAGR) get an equivalent rank from tour starts (seeds/pro_experience.csv, reviewed rows only).
-- A player with both counts at the better of the two. Rolled up per qualifier in agg_qualifier_field_strength.
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
)

select
    s.qualifier_key,
    s.championship_year,
    b.side_id,
    b.player_name,
    b.player_from,
    -- WAGR publishes Wednesdays, labelled one ISO week back: release in effect = ISO week of (date - 9 days). Same as wagr.py.
    yearofweekiso(dateadd(day, -9, s.qualifier_date)) * 100 + weekiso(dateadd(day, -9, s.qualifier_date)) as wagr_week,
    w.wagr_rank,
    pro.pro_equiv_rank,
    least(coalesce(w.wagr_rank, pro.pro_equiv_rank), coalesce(pro.pro_equiv_rank, w.wagr_rank)) as effective_rank,
    pro.pro_equiv_rank is not null and (w.wagr_rank is null or pro.pro_equiv_rank < w.wagr_rank) as is_pro_rank,   -- pro tier set their points
    coalesce(1 / sqrt(effective_rank), 0) as points
from {{ ref('bridge_side_player') }} b
join {{ ref('stg_scores') }} s using (side_id)
-- ponytail: name-only match; a common name can hit a ranked namesake. Upgrade: WAGR profile hometown.
left join {{ ref('stg_wagr') }} w
    on w.wagr_week = yearofweekiso(dateadd(day, -9, s.qualifier_date)) * 100 + weekiso(dateadd(day, -9, s.qualifier_date))
   and lower(w.player_name) = lower(b.player_name)
left join pro on pro.name_key = lower(b.player_name)
