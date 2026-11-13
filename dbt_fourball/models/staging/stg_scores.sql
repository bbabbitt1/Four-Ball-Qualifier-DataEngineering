with src as (
    select
        _file,
        _loaded_at,
        split_part(split_part(_file, '/', 2), '-', 1)::int as championship_year,   -- scores/2026-fourball/...
        try_to_date("qualifier_date") as qualifier_date,
        "course_id" as course_id,
        "site_name" as site_name,
        "source_url" as source_url,
        iff("source_url" ilike '%bluegolf%', 'bluegolf', 'golfgenius') as platform,
        coalesce("Pos.", "Pos") as position_raw,
        lower(coalesce("Details", "section", '')) as outcome_text,
        try_to_number(coalesce("TotalGross", "Total", "Total Score", "Final Total", "Strokes Tot")) as gross,
        -- BlueGolf "Total Tot" is to-par, not gross. 'E' = even, '-' = no score.
        try_to_number(replace(replace(coalesce("To ParGross", "To Par", "To Par Today", "+/-", "Total Tot"), '+', ''), 'E', '0')) as to_par,
        -- No player2 column -> both names sit in player1: "A + B", "A / B", "A|B", "Smith/Jones" (BlueGolf), "Smith  -  Jones".
        -- Swap the first separator for a tab, then split. Hyphenated names have no spaces around '-', so they survive.
        iff("player2" is null, regexp_replace("player1", '[[:space:]]*[|+/][[:space:]]*|[[:space:]]+-[[:space:]]+', '	', 1, 1), null) as _pair,
        trim(iff(_pair is null, "player1", split_part(_pair, '	', 1))) as player1,
        nullif(trim(iff(_pair is null, "player2", split_part(_pair, '	', 2))), '') as player2,
        nullif(trim("player1_from"), '') as player1_from,
        nullif(trim("player2_from"), '') as player2_from
    from {{ source('raw', 'scores') }}
),

flagged as (
    select
        * replace ({{ clean_person_name('player1') }} as player1, {{ clean_person_name('player2') }} as player2),
        regexp_like(position_raw, 'T?[0-9]+') as has_position,
        try_to_number(ltrim(position_raw, 'T')) as position,
        startswith(position_raw, 'T') as is_tied,
        -- implied par sanity check drops partial rounds (e.g. one 9-hole row with gross 46)
        coalesce(gross - to_par between 68 and 74, false) as is_completed,
        count_if(regexp_like(position_raw, 'T?[0-9]+')) over (partition by _file) as advancing_rows
    from src
),

outcome_pass1 as (
    select
        *,
        -- Text wins. Golf Genius marks alternates as CUT and puts "Alternate" in Details;
        -- BlueGolf puts QUALIFIERS / ALTERNATES / DID NOT QUALIFY in section.
        -- Files with <= 5 non-CUT rows use CUT for everyone who didn't advance, so a numeric position there = qualified.
        case
            when outcome_text like '%alternate%' then 'alternate'
            when outcome_text like '%did not qualify%' then 'cut'
            when outcome_text like '%qualif%' or outcome_text like '%medalist%' then 'qualified'
            when position_raw in ('WD', 'NS', 'DQ', 'DNF', 'NC') then 'no_score'
            when position_raw = 'CUT' then 'cut'
            when advancing_rows <= 5 then 'qualified'
            else 'unknown'
        end as outcome_pass1
    from flagged
)

select
    {{ dbt_utils.generate_surrogate_key(['qualifier_date', 'course_id', 'player1', 'player2']) }} as side_id,
    {{ dbt_utils.generate_surrogate_key(['qualifier_date', 'course_id']) }} as qualifier_key,
    championship_year, qualifier_date, course_id, site_name, source_url, platform,
    player1, player1_from, player2, player2_from,
    -- Standard team name: alphabetical so "A / B" and "B / A" in different years are the same team.
    -- team_key ignores hometown (players move); bridge_side_player.player_key keeps it.
    least(player1, player2) || ' / ' || greatest(player1, player2) as team_name,
    {{ dbt_utils.generate_surrogate_key(['lower(least(player1, player2))', 'lower(greatest(player1, player2))']) }} as team_key,
    position_raw, iff(has_position, position, null) as position, coalesce(is_tied, false) as is_tied,
    iff(is_completed, gross, null) as gross,
    iff(is_completed, to_par, null) as to_par,
    is_completed,
    -- Qualifiers are always labelled in files that have any, so leftover unlabelled sides there didn't qualify.
    -- ponytail: text heuristic; 7 qualifiers stay 'unknown'. Upgrade: USGA API qualifyingStatus (2025+).
    -- Exception: an unlabelled side that beat a labelled qualifier is itself a qualifier (e.g. an unlabelled medalist).
    case
        when outcome_pass1 = 'unknown' and is_completed
             and gross < max(iff(outcome_pass1 = 'qualified' and is_completed, gross, null)) over (partition by _file) then 'qualified'
        when outcome_pass1 = 'unknown' and count_if(outcome_pass1 = 'qualified') over (partition by _file) > 0 then 'cut'
        else outcome_pass1
    end as outcome,
    -- 1st / 2nd alternate from the label ("Alternate 1", "2nd Alternate", "First Alternate", ...).
    -- BlueGolf "ALTERNATES - IN ORDER" has no number: order by score then position (a playoff shows as 2 vs 3);
    -- a full tie (T3 / T3) stays null since row order isn't kept.
    -- ponytail: the USGA API (2025+) has ALTERNATE_1 / ALTERNATE_2 and would settle those ties.
    case when outcome_pass1 = 'alternate' then coalesce(
        case
            when regexp_instr(outcome_text, '(1st|first)[[:space:]]+alternate|alternate[[:space:]]+1') > 0 then 1
            when regexp_instr(outcome_text, '(2nd|second)[[:space:]]+alternate|alternate[[:space:]]+2') > 0 then 2
        end,
        iff(count(*) over (partition by _file, outcome_pass1, gross, position) = 1,
            rank() over (partition by _file, outcome_pass1 order by gross, position), null)
    ) end as alternate_number,
    _file, _loaded_at
from outcome_pass1
