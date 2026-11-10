-- Repeatable loads + checks. Run after uploading to S3.
USE ROLE LOADER;
USE WAREHOUSE LOADING_WH;
USE SCHEMA RAW.FOURBALL;

------------------------------------------------------------------------
-- Scores: SCORES_PIPE loads new files automatically.
-- Manual fallback (also used for the initial bulk load). COPY skips files it already
-- loaded in the last 64 days, so re-running only picks up new ones.
------------------------------------------------------------------------
-- COPY INTO SCORES FROM @S3_BRONZE/scores/
--   FILE_FORMAT = CSV_HEADER MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
--   INCLUDE_METADATA = (_FILE = METADATA$FILENAME, _LOADED_AT = METADATA$START_SCAN_TIME);

SELECT SYSTEM$PIPE_STATUS('SCORES_PIPE');  -- executionState should be RUNNING

------------------------------------------------------------------------
-- Dims: files are overwritten in S3, so replace the tables in full.
-- FORCE reloads even though the file name was seen before.
------------------------------------------------------------------------
TRUNCATE DIM_GOLF_COURSE;
COPY INTO DIM_GOLF_COURSE FROM @S3_BRONZE/dims/dim_golf_course.csv
  FILE_FORMAT = CSV_HEADER MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE FORCE = TRUE
  INCLUDE_METADATA = (_FILE = METADATA$FILENAME, _LOADED_AT = METADATA$START_SCAN_TIME);

TRUNCATE DIM_GOLF_COURSE_HOLES;
COPY INTO DIM_GOLF_COURSE_HOLES FROM @S3_BRONZE/dims/dim_golf_course_holes.csv
  FILE_FORMAT = CSV_HEADER MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE FORCE = TRUE
  INCLUDE_METADATA = (_FILE = METADATA$FILENAME, _LOADED_AT = METADATA$START_SCAN_TIME);

------------------------------------------------------------------------
-- Checks. Compare with the local CSVs (2026-11-10 baseline: 218 files / 10,108 rows; 190; 3,132).
------------------------------------------------------------------------
SELECT 'scores' AS tbl, COUNT(DISTINCT _FILE) AS files, COUNT(*) AS row_count FROM SCORES
UNION ALL SELECT 'courses', COUNT(DISTINCT _FILE), COUNT(*) FROM DIM_GOLF_COURSE
UNION ALL SELECT 'holes',   COUNT(DISTINCT _FILE), COUNT(*) FROM DIM_GOLF_COURSE_HOLES;

-- All should be 0; a non-zero means a header didn't match a column
SELECT COUNT_IF("Pos." IS NULL AND "Pos" IS NULL) AS no_position,
       COUNT_IF("player1" IS NULL)                AS no_player,
       COUNT_IF("course_id" IS NULL)              AS no_course
FROM SCORES;

-- Files with suspiciously few rows (truncated scrape / empty page)
SELECT _FILE, COUNT(*) AS row_count FROM SCORES GROUP BY 1 ORDER BY 2 LIMIT 5;

-- Duplicate loads (same file loaded twice, e.g. after the 64-day history window)
SELECT _FILE, COUNT(DISTINCT _LOADED_AT) AS loads FROM SCORES GROUP BY 1 HAVING loads > 1;
