-- "I shot 61 and didn't qualify." Compile with your site, then run the SQL in target/compiled/:
--   dbt compile -s my_61 --vars "{course_id: <course-id>, qualifier_date: 'YYYY-MM-DD', gross: 61}"
with me as (
    select s.*
    from {{ ref('fct_side_score_stats') }} s
    where s.course_id = '{{ var("course_id") }}'
      and s.qualifier_date = '{{ var("qualifier_date") }}'
      and s.gross = {{ var("gross", 61) }}
),
non_qualifiers as (
    select to_par, rank() over (order by to_par) as nq_rank, count(*) over () as nq_total
    from {{ ref('fct_side_score_stats') }}
    where outcome in ('alternate', 'cut')
)
select
    me.gross, me.to_par, me.outcome,
    me.rank_in_field, me.field_size_scored, me.z_score, me.robust_z, me.gross_vs_mean, me.gross_vs_median,
    me.strokes_from_qualifying, me.season_z_score, me.all_time_percentile,
    r.sides_at_or_better, r.pct_at_or_better, r.non_qualifiers_at_or_better,
    r.pct_sites_would_qualify,                     -- "would have qualified at N% of sites"
    (select min(nq_rank) from non_qualifiers n where n.to_par = me.to_par) as rank_among_non_qualifiers,
    (select max(nq_total) from non_qualifiers) as non_qualifiers_total,
    q.qualifying_score, q.mean_gross as field_mean, q.field_strength
from me
join {{ ref('agg_score_rarity') }} r using (to_par)
join {{ ref('agg_qualifier_score_stats') }} q using (qualifier_key)
