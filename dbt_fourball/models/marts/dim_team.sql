select
    team_key,
    any_value(team_name) as team_name,
    count(*) as qualifiers_played,
    min(championship_year) as first_year,
    max(championship_year) as last_year
from {{ ref('fct_side_result') }}
group by team_key
