-- =============================================================
-- 03_clean_layer.sql
-- Builds the clean + analytics layers from raw.parking_occupancy.
--
-- Principles
--   * raw.parking_occupancy is NEVER modified.
--   * Flag, don't delete: problem rows stay in the clean layer with a flag;
--     the analytics view decides what to exclude.
--   * Every rule is logged with the number of rows it touched.
--
-- Safe to re-run: clean tables are dropped and rebuilt each time.
-- Run in pgAdmin Query Tool (whole file at once). On 1.9M rows expect a
-- few minutes; the de-duplication step sorts every row.
-- =============================================================

CREATE SCHEMA IF NOT EXISTS clean;
CREATE SCHEMA IF NOT EXISTS analytics;


-- =============================================================
-- SECTION 0: Cleaning log (rules 1-6 are measured on raw rows)
-- =============================================================

DROP TABLE IF EXISTS clean.cleaning_log;
CREATE TABLE clean.cleaning_log (
    step_no      INT PRIMARY KEY,
    rule_name    TEXT,
    unit         TEXT,
    affected     BIGINT,
    out_of       BIGINT,
    pct          NUMERIC(6,2),
    action_taken TEXT
);

-- Rule 1: reference count
INSERT INTO clean.cleaning_log
SELECT 1, 'Raw rows loaded', 'raw rows', COUNT(*), COUNT(*), 100.00,
       'Reference count; raw layer left untouched'
FROM raw.parking_occupancy;

-- Rule 2: invalid numeric values or keys (script stops if any exist)
INSERT INTO clean.cleaning_log
SELECT 2, 'Non-numeric occupancy, capacity or block-face key', 'raw rows',
       COUNT(*) FILTER (WHERE paidoccupancy     !~ '^-?\d+$'
                           OR parkingspacecount !~ '^\d+$'
                           OR sourceelementkey  !~ '^\d+$'),
       COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE paidoccupancy     !~ '^-?\d+$'
                                         OR parkingspacecount !~ '^\d+$'
                                         OR sourceelementkey  !~ '^\d+$') / COUNT(*), 2),
       'Stop and investigate if any are found'
FROM raw.parking_occupancy;

DO $$
DECLARE bad BIGINT;
BEGIN
    SELECT affected INTO bad FROM clean.cleaning_log WHERE step_no = 2;
    IF bad > 0 THEN
        RAISE EXCEPTION 'Found % rows with non-numeric values. Fix before continuing.', bad;
    END IF;
END $$;

-- Rule 3: duplicate readings (same file + block face + timestamp)
INSERT INTO clean.cleaning_log
SELECT 3, 'Duplicate readings (same block face and timestamp)', 'raw rows',
       COALESCE(SUM(n - 1), 0),
       (SELECT COUNT(*) FROM raw.parking_occupancy),
       ROUND(100.0 * COALESCE(SUM(n - 1), 0) / (SELECT COUNT(*) FROM raw.parking_occupancy), 2),
       'Keep one reading per block face and timestamp'
FROM (
    SELECT COUNT(*) AS n
    FROM raw.parking_occupancy
    GROUP BY source_file, sourceelementkey, occupancydatetime
    HAVING COUNT(*) > 1
) d;

-- Rule 4: restricted parking zone rows
INSERT INTO clean.cleaning_log
SELECT 4, 'Restricted Parking Zone readings', 'raw rows',
       COUNT(*) FILTER (WHERE parkingcategory = 'Restricted Parking Zone'),
       COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE parkingcategory = 'Restricted Parking Zone') / COUNT(*), 2),
       'Flagged is_restricted; excluded from analytics view (near-zero paid occupancy)'
FROM raw.parking_occupancy;

-- Rule 5: occupancy above capacity
INSERT INTO clean.cleaning_log
SELECT 5, 'Paid occupancy above space count', 'raw rows',
       COUNT(*) FILTER (WHERE paidoccupancy::INT > parkingspacecount::INT),
       COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE paidoccupancy::INT > parkingspacecount::INT) / COUNT(*), 2),
       'Kept and flagged; headline occupancy is capped at 100%, uncapped kept for sensitivity'
FROM raw.parking_occupancy;

-- Rule 6: missing sub-area
INSERT INTO clean.cleaning_log
SELECT 6, 'Missing paid sub-area (area has no sub-areas)', 'raw rows',
       COUNT(*) FILTER (WHERE paidparkingsubarea IS NULL),
       COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE paidparkingsubarea IS NULL) / COUNT(*), 2),
       'Filled with ''None''; not an error'
FROM raw.parking_occupancy;


-- =============================================================
-- SECTION 1: Block-face dimension (one row per block face)
-- Attributes were constant for every block face in week 1 (profiling R5).
-- =============================================================

DROP TABLE IF EXISTS clean.dim_blockface CASCADE;
CREATE TABLE clean.dim_blockface AS
SELECT DISTINCT ON (sourceelementkey)
       sourceelementkey::INT                          AS blockface_id,
       blockfacename                                  AS blockface_name,
       sideofstreet                                   AS side_of_street,
       parkingtimelimitcategory                       AS time_limit_category,
       parkingspacecount::INT                         AS space_count,
       paidparkingarea                                AS paid_area,
       COALESCE(paidparkingsubarea, 'None')           AS paid_subarea,
       parkingcategory                                AS parking_category,
       (parkingcategory = 'Restricted Parking Zone')  AS is_restricted,
       (regexp_match(location, 'POINT \((-?[0-9.]+) (-?[0-9.]+)\)'))[1]::NUMERIC AS longitude,
       (regexp_match(location, 'POINT \((-?[0-9.]+) (-?[0-9.]+)\)'))[2]::NUMERIC AS latitude
FROM raw.parking_occupancy
ORDER BY sourceelementkey, source_file DESC;

ALTER TABLE clean.dim_blockface ADD PRIMARY KEY (blockface_id);


-- =============================================================
-- SECTION 2: Hourly fact table (one row per block face per hour)
-- Raw readings arrive about once per minute, so each hour has up to 60.
-- =============================================================

DROP TABLE IF EXISTS clean.fact_blockface_hour CASCADE;
CREATE TABLE clean.fact_blockface_hour AS
WITH dedup AS (
    SELECT DISTINCT ON (source_file, sourceelementkey, occupancydatetime)
           source_file,
           sourceelementkey::INT        AS blockface_id,
           occupancydatetime::TIMESTAMP AS reading_ts,
           paidoccupancy::INT           AS occupied,
           parkingspacecount::INT       AS spaces
    FROM raw.parking_occupancy
    ORDER BY source_file, sourceelementkey, occupancydatetime
),
hourly AS (
    SELECT source_file,
           blockface_id,
           date_trunc('hour', reading_ts)                AS hour_start,
           COUNT(*)                                      AS n_readings,
           MAX(spaces)                                   AS space_count,
           ROUND(AVG(occupied), 3)                       AS avg_occupied,
           ROUND(AVG(LEAST(occupied, spaces)), 3)        AS avg_occupied_capped,
           COUNT(*) FILTER (WHERE occupied > spaces)     AS n_over_capacity,
           -- minute-level states; the three counts below add up to n_readings
           COUNT(*) FILTER (WHERE occupied >= spaces)                AS n_full,
           COUNT(*) FILTER (WHERE spaces - occupied BETWEEN 1 AND 2) AS n_open_1_2,
           COUNT(*) FILTER (WHERE spaces - occupied >= 3)            AS n_open_3plus
    FROM dedup
    GROUP BY source_file, blockface_id, date_trunc('hour', reading_ts)
)
SELECT h.*,
       h.hour_start::DATE                                         AS reading_date,
       EXTRACT(HOUR FROM h.hour_start)::INT                       AS hour_of_day,
       TO_CHAR(h.hour_start, 'FMDay')                             AS day_name,
       EXTRACT(ISODOW FROM h.hour_start)::INT                     AS iso_dow,
       (h.n_readings < 30)                                        AS is_low_coverage,
       (h.n_over_capacity > 0)                                    AS has_over_capacity,
       ROUND(h.avg_occupied_capped / NULLIF(h.space_count, 0), 4) AS occupancy_rate,
       ROUND(h.avg_occupied        / NULLIF(h.space_count, 0), 4) AS occupancy_rate_uncapped
FROM hourly h;

ALTER TABLE clean.fact_blockface_hour
    ADD PRIMARY KEY (source_file, blockface_id, hour_start);
ALTER TABLE clean.fact_blockface_hour
    ADD FOREIGN KEY (blockface_id) REFERENCES clean.dim_blockface (blockface_id);
CREATE INDEX idx_fact_hour ON clean.fact_blockface_hour (hour_start);


-- =============================================================
-- SECTION 3: Analytics view (what analysis queries should use)
-- Excludes: restricted zones, hours with fewer than 30 readings, and
-- Uptown 20:00-21:59. In week 1 those two Uptown hours showed 0.4% and 0.0%
-- paid occupancy across 116 block faces (profiling Q2b), so they are
-- outside the standard paid window; keeping them would drag Uptown
-- occupancy down and inflate its unused-capacity value. A possible
-- explanation is event-only pricing in the evening (unverified).
-- =============================================================

DROP VIEW IF EXISTS analytics.v_hourly;
CREATE VIEW analytics.v_hourly AS
SELECT f.*,
       d.blockface_name,
       d.side_of_street,
       d.time_limit_category,
       d.paid_area,
       d.paid_subarea,
       d.latitude,
       d.longitude
FROM clean.fact_blockface_hour f
JOIN clean.dim_blockface d USING (blockface_id)
WHERE NOT d.is_restricted
  AND NOT f.is_low_coverage
  AND NOT (d.paid_area = 'Uptown' AND f.hour_of_day >= 20);


-- Rules 7-10: measured on the hourly table
INSERT INTO clean.cleaning_log
SELECT 7, 'Hourly block-face rows built from raw readings', 'block-face-hours',
       COUNT(*), COUNT(*), 100.00,
       'Reference count of the hourly grain'
FROM clean.fact_blockface_hour;

INSERT INTO clean.cleaning_log
SELECT 8, 'Low-coverage hours (fewer than 30 readings)', 'block-face-hours',
       COUNT(*) FILTER (WHERE is_low_coverage),
       COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_low_coverage) / COUNT(*), 2),
       'Flagged is_low_coverage; excluded from analytics view'
FROM clean.fact_blockface_hour;

INSERT INTO clean.cleaning_log
SELECT 9, 'Uptown hours 20:00-21:59 (no paid activity outside standard window)', 'block-face-hours',
       COUNT(*) FILTER (WHERE d.paid_area = 'Uptown' AND f.hour_of_day >= 20
                          AND NOT d.is_restricted AND NOT f.is_low_coverage),
       COUNT(*),
       ROUND(100.0 * COUNT(*) FILTER (WHERE d.paid_area = 'Uptown' AND f.hour_of_day >= 20
                                        AND NOT d.is_restricted AND NOT f.is_low_coverage)
             / COUNT(*), 2),
       'Excluded from analytics view (0.4% / 0.0% paid occupancy in week 1)'
FROM clean.fact_blockface_hour f
JOIN clean.dim_blockface d USING (blockface_id);

INSERT INTO clean.cleaning_log
SELECT 10, 'Hourly rows available for analysis', 'block-face-hours',
       (SELECT COUNT(*) FROM analytics.v_hourly),
       (SELECT COUNT(*) FROM clean.fact_blockface_hour),
       ROUND(100.0 * (SELECT COUNT(*) FROM analytics.v_hourly)
             / (SELECT COUNT(*) FROM clean.fact_blockface_hour), 2),
       'Rows in analytics.v_hourly';


-- =============================================================
-- SECTION 4: Verification (run each query and review the output)
-- =============================================================

-- V1: the cleaning log
SELECT * FROM clean.cleaning_log ORDER BY step_no;

-- V2: block faces in the dimension (week 1 expectation: 492)
SELECT COUNT(*) AS blockfaces,
       COUNT(*) FILTER (WHERE is_restricted) AS restricted_blockfaces,
       COUNT(*) FILTER (WHERE latitude IS NULL) AS missing_coordinates
FROM clean.dim_blockface;

-- V3: hourly rows (week 1 expectation: 32,113 before exclusions)
SELECT COUNT(*) AS hourly_rows FROM clean.fact_blockface_hour;

-- V4: first look at occupancy (capped at 100%), 08:00-17:59 so all areas
--     are compared over the same hours
SELECT paid_area,
       COUNT(DISTINCT blockface_id)                                   AS blockfaces,
       ROUND(100.0 * SUM(avg_occupied_capped) / SUM(space_count), 1)  AS weighted_occupancy_pct
FROM analytics.v_hourly
WHERE hour_of_day BETWEEN 8 AND 17
GROUP BY paid_area
ORDER BY weighted_occupancy_pct DESC;
