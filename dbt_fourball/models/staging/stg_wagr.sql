-- Men's WAGR, one row per ranked player per ranking week (wagr.py -> RAW.FOURBALL.WAGR).
with src as (
    select
        wagr_week::int as wagr_week,
        player_id::int as wagr_player_id,
        rank::int as wagr_rank,
        {{ clean_person_name('full_name') }} as player_name,
        nationality,
        points_avg::float as points_avg
    from {{ source('raw', 'wagr') }}
)

select * from src
-- Scores only give a name, so a name must map to one ranked player per week.
-- Same name twice: keep the US player; still tied = ambiguous, drop it (that entrant counts as unranked).
qualify count(*) over (partition by wagr_week, lower(player_name), nationality = 'United States') = 1
    and row_number() over (partition by wagr_week, lower(player_name) order by (nationality = 'United States') desc) = 1
