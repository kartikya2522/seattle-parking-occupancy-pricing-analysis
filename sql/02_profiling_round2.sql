-- =============================================================
-- 02_profiling_round2.sql
-- Run each check on its own in pgAdmin.
-- These checks decide the cleaning rules.
-- =============================================================


-- CHECK R1: What are the "Restricted Parking Zone" rows?
-- (decides: exclude them from paid-parking analysis, or keep?)
SELECT paidparkingarea,
       paidparkingsubarea,
       COUNT(DISTINCT sourceelementkey)        AS blockfaces,
       COUNT(*)                                AS row_count,
       MIN(SUBSTRING(occupancydatetime, 12, 2)) AS first_hour,
       MAX(SUBSTRING(occupancydatetime, 12, 2)) AS last_hour,
       ROUND(AVG(paidoccupancy::INT), 2)       AS avg_paid_occupancy
FROM raw.parking_occupancy
WHERE parkingcategory = 'Restricted Parking Zone'
GROUP BY 1, 2
ORDER BY 1, 2;


-- CHECK R2: Paid hours by area (why do rows drop after 6 PM?)
SELECT paidparkingarea,
       MIN(SUBSTRING(occupancydatetime, 12, 2)) AS first_hour,
       MAX(SUBSTRING(occupancydatetime, 12, 2)) AS last_hour,
       COUNT(DISTINCT sourceelementkey)         AS blockfaces
FROM raw.parking_occupancy
WHERE parkingcategory = 'Paid Parking'
GROUP BY 1
ORDER BY 1;


-- CHECK R3: Over-capacity rows by area (is it spread out or concentrated?)
SELECT paidparkingarea,
       COUNT(*)                                                         AS total_rows,
       COUNT(*) FILTER (WHERE paidoccupancy::INT > parkingspacecount::INT) AS over_rows,
       ROUND(100.0 * COUNT(*) FILTER (WHERE paidoccupancy::INT > parkingspacecount::INT)
             / COUNT(*), 2)                                             AS pct_of_area_rows,
       COUNT(DISTINCT sourceelementkey)
             FILTER (WHERE paidoccupancy::INT > parkingspacecount::INT) AS blockfaces_affected,
       MAX(paidoccupancy::INT - parkingspacecount::INT)                 AS max_excess,
       ROUND(AVG(paidoccupancy::INT - parkingspacecount::INT)
             FILTER (WHERE paidoccupancy::INT > parkingspacecount::INT), 2) AS avg_excess
FROM raw.parking_occupancy
GROUP BY 1
ORDER BY over_rows DESC;


-- CHECK R4: Top 10 block faces by over-capacity rows
SELECT sourceelementkey,
       MAX(blockfacename)               AS blockface,
       MAX(parkingspacecount::INT)      AS spaces,
       MAX(parkingcategory)             AS category,
       COUNT(*) FILTER (WHERE paidoccupancy::INT > parkingspacecount::INT) AS over_rows,
       COUNT(*)                         AS total_rows
FROM raw.parking_occupancy
GROUP BY 1
HAVING COUNT(*) FILTER (WHERE paidoccupancy::INT > parkingspacecount::INT) > 0
ORDER BY over_rows DESC
LIMIT 10;


-- CHECK R5: Do block-face attributes stay constant? (name, capacity, area...)
SELECT
    COUNT(*)                            AS blockface_keys,
    COUNT(*) FILTER (WHERE n_names  > 1) AS keys_with_multiple_names,
    COUNT(*) FILTER (WHERE n_spaces > 1) AS keys_with_changing_capacity,
    COUNT(*) FILTER (WHERE n_limits > 1) AS keys_with_changing_timelimit,
    COUNT(*) FILTER (WHERE n_areas  > 1) AS keys_with_multiple_areas,
    COUNT(*) FILTER (WHERE n_sides  > 1) AS keys_with_multiple_sides,
    COUNT(*) FILTER (WHERE n_cats   > 1) AS keys_switching_category
FROM (
    SELECT sourceelementkey,
           COUNT(DISTINCT blockfacename)            AS n_names,
           COUNT(DISTINCT parkingspacecount)        AS n_spaces,
           COUNT(DISTINCT parkingtimelimitcategory) AS n_limits,
           COUNT(DISTINCT paidparkingarea || '|' || COALESCE(paidparkingsubarea, '')) AS n_areas,
           COUNT(DISTINCT sideofstreet)             AS n_sides,
           COUNT(DISTINCT parkingcategory)          AS n_cats
    FROM raw.parking_occupancy
    GROUP BY 1
) k;


-- CHECK R6: Readings per block face per hour (is hourly grain safe?)
WITH bh AS (
    SELECT sourceelementkey,
           SUBSTRING(occupancydatetime, 1, 13) AS hour_bucket,
           COUNT(*)                            AS n
    FROM raw.parking_occupancy
    GROUP BY 1, 2
)
SELECT COUNT(*)                        AS blockface_hours,
       MIN(n)                          AS min_readings,
       ROUND(AVG(n), 1)                AS avg_readings,
       MAX(n)                          AS max_readings,
       COUNT(*) FILTER (WHERE n < 30)  AS hours_under_30_readings,
       COUNT(*) FILTER (WHERE n = 60)  AS hours_with_exactly_60
FROM bh;


-- CHECK R7: Sanity check of overall occupancy (paid parking only, uncapped)
SELECT ROUND(100.0 * SUM(paidoccupancy::INT) / SUM(parkingspacecount::INT), 1) AS weighted_occupancy_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE paidoccupancy::INT = 0) / COUNT(*), 1) AS pct_rows_empty,
       ROUND(100.0 * COUNT(*) FILTER (WHERE paidoccupancy::INT >= parkingspacecount::INT)
             / COUNT(*), 1)                                                    AS pct_rows_full_or_over
FROM raw.parking_occupancy
WHERE parkingcategory = 'Paid Parking';
