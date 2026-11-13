-- One row per completed side: where the score sits vs its own field, its season, and all time.
-- Negative "vs" values / z-scores = better than the field.
with f as (
    select f.*, c.rating
    from {{ ref('fct_side_result') }} f
    left join {{ ref('dim_course') }} c using (course_id)
    where f.is_completed
)

select
    f.side_id, f.team_key, f.team_name, f.qualifier_key, f.course_id, f.championship_year, f.qualifier_date,
    f.gross, f.to_par, f.outcome, f.alternate_number,

    -- vs own field (same course, same day)
    q.field_size_scored,
    q.mean_gross as field_mean_gross,
    q.median_gross as field_median_gross,
    q.stddev_gross as field_stddev_gross,
    f.gross - q.mean_gross as gross_vs_mean,
    f.gross - q.median_gross as gross_vs_median,
    (f.gross - q.mean_gross) / nullif(q.stddev_gross, 0) as z_score,
    -- 1.4826 * MAD ~ stddev for normal data, but ignores the blow-up tail
    (f.gross - q.median_gross) / nullif(1.4826 * q.mad_gross, 0) as robust_z,
    rank() over (partition by f.qualifier_key order by f.gross) as rank_in_field,
    percent_rank() over (partition by f.qualifier_key order by f.gross) as percentile_in_field,   -- 0 = best
    f.gross - q.qualifying_score as strokes_from_qualifying,   -- +1 = missed by one
    f.gross - f.rating as score_vs_rating,

    -- vs season, on to-par so different courses compare
    avg(f.to_par) over (partition by f.championship_year) as season_mean_to_par,
    median(f.to_par) over (partition by f.championship_year) as season_median_to_par,
    stddev_samp(f.to_par) over (partition by f.championship_year) as season_stddev_to_par,
    f.to_par - season_mean_to_par as to_par_vs_season_mean,
    f.to_par - season_median_to_par as to_par_vs_season_median,
    (f.to_par - season_mean_to_par) / nullif(season_stddev_to_par, 0) as season_z_score,

    -- vs every scored side ever
    percent_rank() over (order by f.to_par) as all_time_percentile
from f
join {{ ref('agg_qualifier_score_stats') }} q using (qualifier_key)
