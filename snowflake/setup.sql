-- One-time setup for the raw layer. Safe to re-run: everything uses IF NOT EXISTS.
-- AWS side lives in snowflake/iam/ (read policy, role trust policy, S3 -> Snowpipe notification).

------------------------------------------------------------------------
-- 1. Role, warehouse, database
------------------------------------------------------------------------
USE ROLE SECURITYADMIN;
CREATE ROLE IF NOT EXISTS LOADER;
GRANT ROLE LOADER TO ROLE SYSADMIN;        -- SYSADMIN inherits LOADER's privileges
GRANT ROLE LOADER TO USER <your_user>;     -- SELECT CURRENT_USER(); to find it

USE ROLE SYSADMIN;
-- XS + auto-suspend 60s: billed per second, stops a minute after the last query
CREATE WAREHOUSE IF NOT EXISTS LOADING_WH
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
-- RAW is shared by dev and prod; only the loader writes here
CREATE DATABASE IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS RAW.FOURBALL;

GRANT USAGE ON WAREHOUSE LOADING_WH TO ROLE LOADER;
GRANT USAGE ON DATABASE RAW TO ROLE LOADER;
GRANT ALL ON SCHEMA RAW.FOURBALL TO ROLE LOADER;

------------------------------------------------------------------------
-- 2. S3 connection (storage integration)
-- WARNING: re-CREATING the integration changes STORAGE_AWS_EXTERNAL_ID.
-- If that happens, update snowflake/iam/trust-policy.json and run:
--   aws iam update-assume-role-policy --role-name snowflake-fourball --policy-document file://snowflake/iam/trust-policy.json
------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
CREATE STORAGE INTEGRATION IF NOT EXISTS S3_FOURBALL
  TYPE = EXTERNAL_STAGE STORAGE_PROVIDER = 'S3' ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::342262164553:role/snowflake-fourball'
  STORAGE_ALLOWED_LOCATIONS = ('s3://fourball-qualifying-342262164553-us-east-1-an/');
DESC INTEGRATION S3_FOURBALL;              -- STORAGE_AWS_IAM_USER_ARN + STORAGE_AWS_EXTERNAL_ID go in the trust policy
GRANT USAGE ON INTEGRATION S3_FOURBALL TO ROLE SYSADMIN;

------------------------------------------------------------------------
-- 3. File formats + stage
------------------------------------------------------------------------
USE ROLE SYSADMIN;
USE SCHEMA RAW.FOURBALL;
-- PARSE_HEADER reads each file's own header, so files with different layouts load into one table
CREATE FILE FORMAT IF NOT EXISTS CSV_HEADER TYPE = CSV PARSE_HEADER = TRUE
  FIELD_OPTIONALLY_ENCLOSED_BY = '"' ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;
CREATE FILE FORMAT IF NOT EXISTS JSON_FMT TYPE = JSON;
CREATE STAGE IF NOT EXISTS S3_BRONZE STORAGE_INTEGRATION = S3_FOURBALL
  URL = 's3://fourball-qualifying-342262164553-us-east-1-an/';

GRANT USAGE ON STAGE S3_BRONZE TO ROLE LOADER;
GRANT USAGE ON FILE FORMAT CSV_HEADER TO ROLE LOADER;
GRANT USAGE ON FILE FORMAT JSON_FMT TO ROLE LOADER;

LIST @S3_BRONZE/scores/;                   -- works = IAM setup works

------------------------------------------------------------------------
-- 4. Raw tables: all VARCHAR so a load never fails on type; casting happens in dbt.
-- _FILE / _LOADED_AT trace every row back to its source file and load.
------------------------------------------------------------------------
-- Union of every header variant across the score files
CREATE TABLE IF NOT EXISTS SCORES (
  "Pos." VARCHAR, "Pos" VARCHAR, "Players" VARCHAR, "Team" VARCHAR, "Thru" VARCHAR,
  "To ParGross" VARCHAR, "To Par" VARCHAR, "To Par Today" VARCHAR, "+/-" VARCHAR, "Total Tot" VARCHAR,
  "TotalGross" VARCHAR, "Total" VARCHAR, "Total Score" VARCHAR, "Final Total" VARCHAR, "Strokes Tot" VARCHAR,
  "Details" VARCHAR, "section" VARCHAR, "Purse" VARCHAR, "Points" VARCHAR,
  "player1" VARCHAR, "player1_from" VARCHAR, "player2" VARCHAR, "player2_from" VARCHAR,
  "gg_aggregate_id" VARCHAR, "bg_scorecard" VARCHAR,
  "qualifier_date" VARCHAR, "course_id" VARCHAR, "site_name" VARCHAR, "source_url" VARCHAR,
  _FILE VARCHAR, _LOADED_AT TIMESTAMP_LTZ);

-- Quoted uppercase names avoid keyword clashes (e.g. LONG); same as unquoted to queries
CREATE TABLE IF NOT EXISTS DIM_GOLF_COURSE (
  "COURSE_ID" VARCHAR, "COURSE_NAME" VARCHAR, "CITY" VARCHAR, "STATE" VARCHAR, "ADDRESS" VARCHAR,
  "LAT" VARCHAR, "LONG" VARCHAR, "TEES" VARCHAR, "PAR" VARCHAR, "RATING" VARCHAR, "SLOPE" VARCHAR,
  "NCRDB_COURSE_ID" VARCHAR, "NCRDB_NAME" VARCHAR, "NCRDB_MATCH_SCORE" VARCHAR, "GEO_PRECISION" VARCHAR,
  "_FILE" VARCHAR, "_LOADED_AT" TIMESTAMP_LTZ);

CREATE TABLE IF NOT EXISTS DIM_GOLF_COURSE_HOLES (
  "COURSE_ID" VARCHAR, "TEES" VARCHAR, "HOLE" VARCHAR, "PAR" VARCHAR, "YARDAGE" VARCHAR, "HANDICAP" VARCHAR,
  "_FILE" VARCHAR, "_LOADED_AT" TIMESTAMP_LTZ);

-- One row per inventory file (one per season); dbt flattens sites[]
CREATE TABLE IF NOT EXISTS INVENTORY (V VARIANT, "_FILE" VARCHAR, "_LOADED_AT" TIMESTAMP_LTZ);

-- One file per WAGR ranking week (wagr.py); one row per ranked man
CREATE TABLE IF NOT EXISTS WAGR (
  "WAGR_WEEK" VARCHAR, "PLAYER_ID" VARCHAR, "RANK" VARCHAR, "FIRST_NAME" VARCHAR, "LAST_NAME" VARCHAR,
  "FULL_NAME" VARCHAR, "NATIONALITY" VARCHAR, "POINTS_AVG" VARCHAR,
  "_FILE" VARCHAR, "_LOADED_AT" TIMESTAMP_LTZ);

GRANT ALL ON ALL TABLES IN SCHEMA RAW.FOURBALL TO ROLE LOADER;

------------------------------------------------------------------------
-- 5. Snowpipe: auto-loads new score files ~1 min after they land in S3.
-- After creating, copy notification_channel from SHOW PIPES into snowflake/iam/s3-notification.json and run:
--   aws s3api put-bucket-notification-configuration --bucket fourball-qualifying-342262164553-us-east-1-an --notification-configuration file://snowflake/iam/s3-notification.json
-- DO NOT run ALTER PIPE SCORES_PIPE REFRESH: the pipe has its own load history and would reload files already loaded by COPY.
------------------------------------------------------------------------
USE ROLE LOADER;
USE SCHEMA RAW.FOURBALL;
CREATE PIPE IF NOT EXISTS SCORES_PIPE AUTO_INGEST = TRUE AS
  COPY INTO SCORES FROM @S3_BRONZE/scores/
    FILE_FORMAT = CSV_HEADER
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
    INCLUDE_METADATA = (_FILE = METADATA$FILENAME, _LOADED_AT = METADATA$START_SCAN_TIME);
SHOW PIPES;

------------------------------------------------------------------------
-- 6. Fabric reader: read-only login that Fabric mirroring uses on FOURBALL_PROD.MARTS.
-- Own role + warehouse so reporting can't write anything and its compute cost shows up on its own.
-- Mirroring reads changes through Snowflake streams, so it needs CREATE STREAM, and the marts
-- need CHANGE_TRACKING (set by a dbt post-hook in dbt_project.yml, because dbt recreates the tables).
------------------------------------------------------------------------
USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS REPORTING_WH
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;

USE ROLE SECURITYADMIN;
CREATE ROLE IF NOT EXISTS FABRIC_READER;
GRANT ROLE FABRIC_READER TO ROLE SYSADMIN;

GRANT USAGE ON WAREHOUSE REPORTING_WH TO ROLE FABRIC_READER;
GRANT USAGE ON DATABASE FOURBALL_PROD TO ROLE FABRIC_READER;
GRANT USAGE ON SCHEMA FOURBALL_PROD.MARTS TO ROLE FABRIC_READER;
GRANT CREATE STREAM ON SCHEMA FOURBALL_PROD.MARTS TO ROLE FABRIC_READER;
GRANT SELECT ON ALL TABLES IN SCHEMA FOURBALL_PROD.MARTS TO ROLE FABRIC_READER;
-- dbt drops and recreates every mart on each build; future grants re-apply SELECT to the new table
GRANT SELECT ON FUTURE TABLES IN SCHEMA FOURBALL_PROD.MARTS TO ROLE FABRIC_READER;

-- Service user (no interactive login). Key-pair auth, like the dbt user:
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 des3 -inform PEM -out fabric_reader.p8
--   openssl rsa -in fabric_reader.p8 -pubout -out fabric_reader.pub
-- Paste the .pub body (no BEGIN/END lines) below. Keep the .p8 out of the repo.
-- If the Fabric Snowflake connection only offers username/password, use TYPE = LEGACY_SERVICE and
-- PASSWORD = '...' instead, but Snowflake is phasing out password-only logins.
CREATE USER IF NOT EXISTS FABRIC_SVC
  TYPE = SERVICE
  RSA_PUBLIC_KEY = '<paste fabric_reader.pub body>'
  DEFAULT_ROLE = FABRIC_READER
  DEFAULT_WAREHOUSE = REPORTING_WH
  DEFAULT_NAMESPACE = FOURBALL_PROD.MARTS
  COMMENT = 'Fabric mirroring of FOURBALL_PROD.MARTS (read-only)';
GRANT ROLE FABRIC_READER TO USER FABRIC_SVC;

-- Check: should list SELECT on every mart + CREATE STREAM on the schema
SHOW GRANTS TO ROLE FABRIC_READER;
