-- One row per qualifier: distribution of completed-side scores + the qualifying line.
with scored as (
    select *, median(gross) over (partition by qualifier_key) as qualifier_median
    from {{ ref('fct_side_result') }}
    where is_completed
),

per_qualifier as (
    select
        qualifier_key,
        any_value(championship_year) as championship_year,
        any_value(course_id) as course_id,
        any_value(qualifier_date) as qualifier_date,
        count(*) as field_size_scored,
        avg(gross) as mean_gross,
        median(gross) as median_gross,
        stddev_samp(gross) as stddev_gross,
        min(gross) as min_gross,
        max(gross) as max_gross,
        max(gross) - min(gross) as spread_gross,
        percentile_cont(0.25) within group (order by gross) as p25_gross,
        percentile_cont(0.75) within group (order by gross) as p75_gross,
        median(abs(gross - qualifier_median)) as mad_gross,
        skew(gross) as skew_gross,          -- > 0 = long tail of blow-ups
        kurtosis(gross) as kurtosis_gross,
        avg(to_par) as mean_to_par,
        count_if(outcome = 'qualified') as spots,
        max(iff(outcome = 'qualified', gross, null)) as qualifying_score,       -- the number you had to match
        max(iff(outcome = 'qualified', to_par, null)) as qualifying_to_par,
        min(iff(outcome in ('alternate', 'cut'), gross, null)) as best_non_qualifying_score,
        min(iff(outcome in ('alternate', 'cut'), to_par, null)) as best_non_qualifying_to_par
    from scored
    group by qualifier_key
)

select
    *,
    spots / field_size_scored as qualify_rate,
    -- negative = this field scored better than the season average (tougher to get through)
    mean_to_par - sum(mean_to_par * field_size_scored) over (partition by championship_year)
                  / sum(field_size_scored) over (partition by championship_year) as field_strength
from per_qualifier
