-- =============================================================
-- 09_week_comparison.sql
-- Does week 1's weekday-vs-Saturday pattern repeat in week 2?
-- Does July 4 (a Friday, inside week 2) show a holiday effect?
-- Run each query on its own in pgAdmin.
-- =============================================================


-- =============================================================
-- W1. Weekday vs Saturday occupancy, split by week, matched block
-- faces and hours of day only (same logic as Q4, but per source_file
-- instead of pooling both weeks together).
-- =============================================================
WITH agg AS (
    SELECT source_file,
           blockface_id,
           paid_area,
           hour_of_day,
           space_count,
           CASE WHEN iso_dow = 6 THEN 'Saturday' ELSE 'Weekday' END AS day_type,
           AVG(avg_occupied_capped)                                 AS occ
    FROM analytics.v_hourly_revenue
    GROUP BY source_file, blockface_id, paid_area, hour_of_day, space_count,
             CASE WHEN iso_dow = 6 THEN 'Saturday' ELSE 'Weekday' END
),
pairs AS (
    SELECT w.source_file, w.paid_area, w.hour_of_day, w.space_count,
           w.occ AS weekday_occ,
           s.occ AS saturday_occ
    FROM agg w
    JOIN agg s
      ON s.source_file  = w.source_file
     AND s.blockface_id = w.blockface_id
     AND s.hour_of_day  = w.hour_of_day
     AND s.day_type     = 'Saturday'
    WHERE w.day_type = 'Weekday'
)
SELECT source_file,
       paid_area,
       COUNT(*)                                                                   AS matched_hour_slots,
       ROUND(100.0 * SUM(weekday_occ)  / SUM(space_count), 1)                     AS weekday_occupancy_pct,
       ROUND(100.0 * SUM(saturday_occ) / SUM(space_count), 1)                     AS saturday_occupancy_pct,
       ROUND(100.0 * (SUM(saturday_occ) - SUM(weekday_occ)) / SUM(space_count), 1) AS saturday_minus_weekday_pts
FROM pairs
GROUP BY source_file, paid_area
ORDER BY paid_area, source_file;


-- =============================================================
-- W2. Daily trend split by week, so July 4 (Friday) stands out
-- if there's a holiday effect. Uses the raw table directly so a
-- total gap (zero paid rows that day) is visible, not just low
-- occupancy on the hours that do exist.
-- =============================================================
SELECT source_file,
       SUBSTRING(occupancydatetime, 1, 10) AS calendar_date,
       TO_CHAR(SUBSTRING(occupancydatetime, 1, 10)::DATE, 'FMDay') AS day_name,
       COUNT(*)                                                     AS raw_readings,
       COUNT(*) FILTER (WHERE parkingcategory = 'Paid Parking')     AS paid_readings,
       ROUND(AVG(paidoccupancy::NUMERIC) FILTER (WHERE parkingcategory = 'Paid Parking'), 2)
            AS avg_paid_occupancy_per_reading
FROM raw.parking_occupancy
GROUP BY source_file, calendar_date
ORDER BY calendar_date;
