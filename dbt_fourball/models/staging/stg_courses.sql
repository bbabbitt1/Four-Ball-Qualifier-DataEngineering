select
    course_id, course_name, city, state, address,
    try_to_double(lat) as lat,
    try_to_double(long) as long,
    nullif(tees, '') as tees,
    try_to_number(par) as par,
    try_to_double(rating) as rating,
    try_to_number(slope) as slope,
    nullif(ncrdb_course_id, '') as ncrdb_course_id,
    nullif(ncrdb_name, '') as ncrdb_name,
    try_to_double(ncrdb_match_score) as ncrdb_match_score,
    geo_precision
from {{ source('raw', 'dim_golf_course') }}
