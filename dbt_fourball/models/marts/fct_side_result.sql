select
    side_id, team_key, team_name, qualifier_key, course_id, championship_year, qualifier_date,
    gross, to_par, position, is_tied, position_raw, outcome, is_completed
from {{ ref('stg_scores') }}
