-- Every known qualifier (inventory), including sites with no results yet (upcoming / manual / source_gone).
with scored as (
    select
        qualifier_key,
        count(*) as field_size,
        count_if(is_completed) as field_size_scored
    from {{ ref('stg_scores') }}
    group by qualifier_key
)

select
    q.qualifier_key,
    q.championship_year,
    q.qualifier_date,
    q.course_id,
    q.site_name,
    q.city,
    q.state,
    q.platform,
    q.scoring_url,
    q.scrape_status,
    s.qualifier_key is not null as has_results,
    q.qualifier_date > current_date() as is_upcoming,
    q.usga_field_size_players,
    q.usga_field_size_players / 2 as usga_field_size_sides,
    s.field_size,
    s.field_size_scored
from {{ ref('stg_qualifiers') }} q
left join scored s using (qualifier_key)
