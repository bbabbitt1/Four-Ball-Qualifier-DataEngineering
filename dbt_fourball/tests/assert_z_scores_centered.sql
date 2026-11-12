-- Within every field, deviations from the mean must sum to ~0 and z-scores average ~0.
select qualifier_key, sum(gross_vs_mean) as sum_dev, avg(z_score) as avg_z
from {{ ref('fct_side_score_stats') }}
group by qualifier_key
having abs(sum(gross_vs_mean)) > 0.001 or abs(avg(z_score)) > 0.001
