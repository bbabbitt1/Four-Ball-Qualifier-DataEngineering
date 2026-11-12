-- One row per to-par value: how rare it is and how often it would have gotten through.
with sides as (
    select to_par, outcome from {{ ref('fct_side_result') }} where is_completed
),
quals as (
    select qualifying_to_par, best_non_qualifying_to_par
    from {{ ref('agg_qualifier_score_stats') }}
    where qualifying_to_par is not null
),
vals as (select distinct to_par from sides),

tail as (
    select
        v.to_par,
        count(*) as sides_at_or_better,
        count_if(s.outcome in ('alternate', 'cut')) as non_qualifiers_at_or_better
    from vals v
    join sides s on s.to_par <= v.to_par
    group by v.to_par
),

sites as (
    select
        v.to_par,
        count(*) as qualifiers_compared,
        -- <= : at least tied the last spot (ties may have gone to a playoff)
        avg(iff(v.to_par <= q.qualifying_to_par, 1, 0)) as pct_sites_would_qualify,
        avg(iff(v.to_par < q.best_non_qualifying_to_par, 1, 0)) as pct_sites_would_be_low_non_qualifier
    from vals v
    cross join quals q
    group by v.to_par
)

select
    t.to_par,
    t.sides_at_or_better,
    t.sides_at_or_better / (select count(*) from sides) as pct_at_or_better,
    t.non_qualifiers_at_or_better,
    s.qualifiers_compared,
    s.pct_sites_would_qualify,
    s.pct_sites_would_be_low_non_qualifier
from tail t
join sites s using (to_par)
