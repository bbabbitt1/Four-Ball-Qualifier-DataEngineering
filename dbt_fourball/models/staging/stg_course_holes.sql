select
    course_id, tees,
    try_to_number(hole) as hole,
    try_to_number(par) as par,
    try_to_number(yardage) as yardage,
    try_to_number(handicap) as handicap
from {{ source('raw', 'dim_golf_course_holes') }}
