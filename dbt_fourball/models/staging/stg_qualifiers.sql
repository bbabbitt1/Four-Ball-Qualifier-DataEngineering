with sites as (
    select
        i.v:championship_year::int as championship_year,
        s.value:qualifier_date::date as qualifier_date,
        s.value:course_id::string as course_id,
        s.value:site_name::string as site_name,
        s.value:city::string as city,
        s.value:state::string as state,
        s.value:platform::string as platform,
        s.value:scoring_url::string as scoring_url,
        nullif(s.value:usga_field_size_players::int, 0) as usga_field_size_players,   -- USGA reports 0 until the field is set
        s.value:status::string as scrape_status,
        s.value:rows::int as scraped_rows
    from {{ source('raw', 'inventory') }} i,
        lateral flatten(input => i.v:sites) s
)

select
    {{ dbt_utils.generate_surrogate_key(['qualifier_date', 'course_id']) }} as qualifier_key,   -- same hash as stg_scores
    *
from sites
