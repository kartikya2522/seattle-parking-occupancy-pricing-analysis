-- =============================================================
-- 01_raw_load.sql
-- Seattle Paid Parking Occupancy: raw layer + profiling checks
-- Database: PostgreSQL (database name: parking_analysis)
--
-- HOW TO RUN
--   Section 1 -> pgAdmin Query Tool
--   Section 2 -> psql ("SQL Shell (psql)"), because \copy is a psql command
--   Section 3 -> pgAdmin Query Tool, run each check on its own
-- =============================================================


-- =============================================================
-- SECTION 1: Schemas and raw table (run in pgAdmin)
-- =============================================================

CREATE SCHEMA IF NOT EXISTS raw;        -- untouched copy of source files
CREATE SCHEMA IF NOT EXISTS clean;      -- validated, typed data
CREATE SCHEMA IF NOT EXISTS analytics;  -- views and tables for analysis

-- Every source column is TEXT on purpose: loading can never fail on a bad
-- value, and every cleaning decision is made later in SQL, with row counts.
-- source_file records which download each row came from.
CREATE TABLE IF NOT EXISTS raw.parking_occupancy (
    occupancydatetime         TEXT,
    paidoccupancy             TEXT,
    blockfacename             TEXT,
    sideofstreet              TEXT,
    sourceelementkey          TEXT,
    parkingtimelimitcategory  TEXT,
    parkingspacecount         TEXT,
    paidparkingarea           TEXT,
    paidparkingsubarea        TEXT,
    paidparkingrate           TEXT,
    parkingcategory           TEXT,
    location                  TEXT,
    source_file               TEXT
);


-- =============================================================
-- SECTION 2: Load the CSV (run in psql, NOT in pgAdmin)
-- Connect to parking_analysis first, then run both lines.
-- Edit the file path if your file is somewhere else.
-- Use forward slashes even on Windows.
-- =============================================================

-- ALTER TABLE raw.parking_occupancy
--     ALTER COLUMN source_file SET DEFAULT 'week1_2025-06-02';
--
-- \copy raw.parking_occupancy (occupancydatetime, paidoccupancy, blockfacename, sideofstreet, sourceelementkey, parkingtimelimitcategory, parkingspacecount, paidparkingarea, paidparkingsubarea, paidparkingrate, parkingcategory, location) FROM 'C:/Users/karti/Downloads/seattle_week1_2025-06-02.csv' WITH (FORMAT csv, HEADER true)

-- For week 2 later, change the default to 'week2_2025-06-30' and load that file.
-- Run the load only ONCE per file, or you will create duplicate rows.


-- =============================================================
-- SECTION 3: Profiling checks (run each in pgAdmin)
-- =============================================================

-- CHECK 1: Row count per source file (expect 1,921,428 for week 1)
SELECT source_file, COUNT(*) AS row_count
FROM raw.parking_occupancy
GROUP BY source_file;


-- CHECK 2: Values of parkingcategory (are there restricted rows?)
SELECT parkingcategory, COUNT(*) AS row_count
FROM raw.parking_occupancy
GROUP BY parkingcategory
ORDER BY row_count DESC;


-- CHECK 3: Date range actually loaded
SELECT MIN(occupancydatetime) AS first_ts,
       MAX(occupancydatetime) AS last_ts
FROM raw.parking_occupancy;


-- CHECK 4: Rows per day (do all 7 days exist? what happens on Sunday?)
SELECT SUBSTRING(occupancydatetime, 1, 10) AS day,
       COUNT(*) AS row_count
FROM raw.parking_occupancy
GROUP BY 1
ORDER BY 1;


-- CHECK 5: Rows per hour of day (which hours are covered?)
SELECT SUBSTRING(occupancydatetime, 12, 2) AS hour_of_day,
       COUNT(*) AS row_count
FROM raw.parking_occupancy
GROUP BY 1
ORDER BY 1;


-- CHECK 6: Null / empty count for every column
SELECT
    COUNT(*)                                                    AS total_rows,
    COUNT(*) FILTER (WHERE occupancydatetime        IS NULL)    AS null_datetime,
    COUNT(*) FILTER (WHERE paidoccupancy            IS NULL)    AS null_paidoccupancy,
    COUNT(*) FILTER (WHERE blockfacename            IS NULL)    AS null_blockface,
    COUNT(*) FILTER (WHERE sideofstreet             IS NULL)    AS null_side,
    COUNT(*) FILTER (WHERE sourceelementkey         IS NULL)    AS null_key,
    COUNT(*) FILTER (WHERE parkingtimelimitcategory IS NULL)    AS null_timelimit,
    COUNT(*) FILTER (WHERE parkingspacecount        IS NULL)    AS null_spacecount,
    COUNT(*) FILTER (WHERE paidparkingarea          IS NULL)    AS null_area,
    COUNT(*) FILTER (WHERE paidparkingsubarea       IS NULL)    AS null_subarea,
    COUNT(*) FILTER (WHERE paidparkingrate          IS NULL)    AS null_rate,
    COUNT(*) FILTER (WHERE parkingcategory          IS NULL)    AS null_category,
    COUNT(*) FILTER (WHERE location                 IS NULL)    AS null_location
FROM raw.parking_occupancy;


-- CHECK 7: Does paidparkingrate ever contain a value?
SELECT paidparkingrate, COUNT(*) AS row_count
FROM raw.parking_occupancy
GROUP BY paidparkingrate
ORDER BY row_count DESC
LIMIT 10;


-- CHECK 8: Area and sub-area combinations (this becomes the rate-table key)
SELECT paidparkingarea, paidparkingsubarea, COUNT(*) AS row_count,
       COUNT(DISTINCT sourceelementkey) AS blockfaces
FROM raw.parking_occupancy
GROUP BY 1, 2
ORDER BY 1, 2;


-- CHECK 9: Non-numeric values in the two numeric columns
SELECT
    COUNT(*) FILTER (WHERE paidoccupancy     !~ '^-?\d+$') AS bad_paidoccupancy,
    COUNT(*) FILTER (WHERE parkingspacecount !~ '^\d+$')   AS bad_spacecount
FROM raw.parking_occupancy;


-- CHECK 10: Occupancy above capacity, or negative
SELECT
    COUNT(*) FILTER (WHERE ok AND occ > spaces) AS over_capacity,
    COUNT(*) FILTER (WHERE ok AND occ < 0)      AS negative_occupancy,
    COUNT(*) FILTER (WHERE ok AND spaces = 0)   AS zero_capacity
FROM (
    SELECT
        (paidoccupancy ~ '^-?\d+$' AND parkingspacecount ~ '^\d+$') AS ok,
        CASE WHEN paidoccupancy     ~ '^-?\d+$' THEN paidoccupancy::INT     END AS occ,
        CASE WHEN parkingspacecount ~ '^\d+$'   THEN parkingspacecount::INT END AS spaces
    FROM raw.parking_occupancy
) t;


-- CHECK 11: Duplicate observations (same blockface and same timestamp)
SELECT COUNT(*) AS duplicate_groups,
       SUM(n - 1) AS extra_rows
FROM (
    SELECT sourceelementkey, occupancydatetime, COUNT(*) AS n
    FROM raw.parking_occupancy
    GROUP BY 1, 2
    HAVING COUNT(*) > 1
) d;


-- CHECK 12: Block faces and snapshots per block face
SELECT COUNT(DISTINCT sourceelementkey)                              AS blockfaces,
       ROUND(COUNT(*)::NUMERIC / COUNT(DISTINCT sourceelementkey), 1) AS avg_snapshots_per_blockface
FROM raw.parking_occupancy;
