-- =============================================================
-- 06_analysis_queries.sql 
-- Business questions answered from analytics.v_hourly_revenue
-- (one row per block face per hour; restricted zones, low-coverage
--  hours and Uptown 20:00-21:59 already excluded; occupancy capped
--  at 100%). Revenue figures are MODEL estimates at posted rates.
--
-- Run each query on its own in pgAdmin.
-- =============================================================


-- =============================================================
-- Q1. How do the five areas compare overall?
-- Occupancy is weighted by capacity. The uncapped column shows how
-- much the over-capacity rule changes the answer.
-- =============================================================
SELECT COALESCE(paid_area, 'ALL AREAS')                                  AS paid_area,
       COUNT(DISTINCT blockface_id)                                      AS blockfaces,
       COUNT(*)                                                          AS block_hours,
       ROUND(100.0 * SUM(avg_occupied_capped) / SUM(space_count), 1)     AS occupancy_capped_pct,
       ROUND(100.0 * SUM(avg_occupied)        / SUM(space_count), 1)     AS occupancy_uncapped_pct,
       ROUND(SUM(est_revenue_capped))                                    AS est_revenue_usd,
       ROUND(SUM(est_revenue_capped) / COUNT(DISTINCT blockface_id)
             / COUNT(DISTINCT reading_date))                             AS est_revenue_per_blockface_day,
       ROUND(SUM(unused_capacity_value))                                 AS unused_capacity_ceiling_usd
FROM analytics.v_hourly_revenue
GROUP BY ROLLUP (paid_area)
ORDER BY GROUPING(paid_area), paid_area;


-- =============================================================
-- Q2a. Which hours are the busiest in each area? (RANK window function)
-- =============================================================
WITH hourly AS (
    SELECT paid_area,
           hour_of_day,
           COUNT(DISTINCT blockface_id)                                  AS blockfaces,
           ROUND(100.0 * SUM(avg_occupied_capped) / SUM(space_count), 1) AS occupancy_pct,
           ROUND(SUM(est_revenue_capped))                                AS est_revenue_usd
    FROM analytics.v_hourly_revenue
    GROUP BY paid_area, hour_of_day
),
ranked AS (
    SELECT *,
           RANK() OVER (PARTITION BY paid_area ORDER BY occupancy_pct DESC) AS occupancy_rank
    FROM hourly
)
SELECT paid_area, occupancy_rank, hour_of_day, blockfaces, occupancy_pct, est_revenue_usd
FROM ranked
WHERE occupancy_rank <= 3
ORDER BY paid_area, occupancy_rank;


-- =============================================================
-- Q2b. Pooled hourly curve (all areas). areas_reporting shows why
-- the hours after 18:00 are not comparable with the daytime ones:
-- the set of areas changes, which moves the pooled average.
-- =============================================================
SELECT hour_of_day,
       COUNT(DISTINCT paid_area)                                     AS areas_reporting,
       COUNT(DISTINCT blockface_id)                                  AS blockfaces,
       ROUND(100.0 * SUM(avg_occupied_capped) / SUM(space_count), 1) AS occupancy_pct,
       ROUND(SUM(est_revenue_capped))                                AS est_revenue_usd
FROM analytics.v_hourly_revenue
GROUP BY hour_of_day
ORDER BY hour_of_day;


-- =============================================================
-- Q3a. Does each area hit SDOT's stated goal of roughly 1-2 open
-- spaces per block "at any given time"? Share of block-MINUTES in
-- each state: full (0 open), target (1-2 open), under-used (3+ open).
-- =============================================================
SELECT paid_area,
       band,
       COUNT(*)                                                     AS block_hours,
       ROUND(100.0 * SUM(n_full)       / SUM(n_readings), 1)        AS pct_minutes_full,
       ROUND(100.0 * SUM(n_open_1_2)   / SUM(n_readings), 1)        AS pct_minutes_1_to_2_open,
       ROUND(100.0 * SUM(n_open_3plus) / SUM(n_readings), 1)        AS pct_minutes_3plus_open
FROM analytics.v_hourly_revenue
GROUP BY paid_area, band
ORDER BY paid_area, MIN(hour_of_day);


-- =============================================================
-- Q3b. Same states, split by block size. Blocks with 1-3 spaces
-- behave differently: one car changes their state completely, and on
-- blocks with 8+ spaces "1-2 open" already means 75%+ occupancy.
-- =============================================================
WITH sized AS (
    SELECT *,
           CASE WHEN space_count <= 3 THEN '1-3 spaces'
                WHEN space_count <= 7 THEN '4-7 spaces'
                ELSE '8+ spaces' END AS block_size
    FROM analytics.v_hourly_revenue
)
SELECT COALESCE(block_size, 'ALL BLOCKS')                              AS block_size,
       COUNT(DISTINCT blockface_id)                                    AS blockfaces,
       COUNT(*)                                                        AS block_hours,
       ROUND(100.0 * SUM(avg_occupied_capped) / SUM(space_count), 1)   AS occupancy_pct,
       ROUND(100.0 * SUM(n_full)       / SUM(n_readings), 1)           AS pct_minutes_full,
       ROUND(100.0 * SUM(n_open_1_2)   / SUM(n_readings), 1)           AS pct_minutes_1_to_2_open,
       ROUND(100.0 * SUM(n_open_3plus) / SUM(n_readings), 1)           AS pct_minutes_3plus_open
FROM sized
GROUP BY ROLLUP (block_size)
ORDER BY GROUPING(block_size), block_size;


-- =============================================================
-- Q4. Weekday vs Saturday, MATCHED: only block faces and hours of day
-- that exist on both, so the different set of open blocks cannot
-- distort the comparison. Saturday is a single day: treat with care.
-- =============================================================
WITH agg AS (
    SELECT blockface_id,
           paid_area,
           hour_of_day,
           space_count,
           CASE WHEN iso_dow = 6 THEN 'Saturday' ELSE 'Weekday' END AS day_type,
           AVG(avg_occupied_capped)                                 AS occ
    FROM analytics.v_hourly_revenue
    GROUP BY blockface_id, paid_area, hour_of_day, space_count,
             CASE WHEN iso_dow = 6 THEN 'Saturday' ELSE 'Weekday' END
),
pairs AS (
    SELECT w.blockface_id, w.paid_area, w.hour_of_day, w.space_count,
           w.occ AS weekday_occ,
           s.occ AS saturday_occ
    FROM agg w
    JOIN agg s
      ON s.blockface_id = w.blockface_id
     AND s.hour_of_day  = w.hour_of_day
     AND s.day_type     = 'Saturday'
    WHERE w.day_type = 'Weekday'
)
SELECT COALESCE(paid_area, 'ALL AREAS')                                   AS paid_area,
       COUNT(DISTINCT blockface_id)                                       AS matched_blockfaces,
       COUNT(*)                                                           AS matched_hour_slots,
       ROUND(100.0 * SUM(weekday_occ)  / SUM(space_count), 1)             AS weekday_occupancy_pct,
       ROUND(100.0 * SUM(saturday_occ) / SUM(space_count), 1)             AS saturday_occupancy_pct,
       ROUND(100.0 * (SUM(saturday_occ) - SUM(weekday_occ)) / SUM(space_count), 1)
            AS saturday_minus_weekday_pts
FROM pairs
GROUP BY ROLLUP (paid_area)
ORDER BY GROUPING(paid_area), paid_area;


-- =============================================================
-- Q5. Day-by-day trend with change versus the previous day (LAG)
-- =============================================================
WITH daily AS (
    SELECT reading_date,
           day_name,
           COUNT(DISTINCT blockface_id)                                  AS blockfaces,
           COUNT(*)                                                      AS block_hours,
           ROUND(100.0 * SUM(avg_occupied_capped) / SUM(space_count), 1) AS occupancy_pct,
           ROUND(SUM(est_revenue_capped))                                AS est_revenue_usd
    FROM analytics.v_hourly_revenue
    GROUP BY reading_date, day_name
)
SELECT daily.*,
       est_revenue_usd - LAG(est_revenue_usd) OVER w                     AS revenue_change_vs_prev_day,
       ROUND(100.0 * (est_revenue_usd - LAG(est_revenue_usd) OVER w)
             / NULLIF(LAG(est_revenue_usd) OVER w, 0), 1)                AS pct_change_vs_prev_day
FROM daily
WINDOW w AS (ORDER BY reading_date)
ORDER BY reading_date;


-- =============================================================
-- Q6. Hot blocks: the 10 busiest block faces by capacity-weighted
-- occupancy. Only blocks with 3+ spaces and at least 24 hours of data
-- (a 1-2 space block is dominated by a single car).
-- =============================================================
SELECT paid_area,
       paid_subarea,
       blockface_name,
       side_of_street,
       MAX(space_count)                                                  AS spaces,
       COUNT(*)                                                          AS block_hours,
       ROUND(100.0 * SUM(avg_occupied_capped) / SUM(space_count), 1)     AS occupancy_pct,
       ROUND(100.0 * SUM(n_full) / SUM(n_readings), 1)                   AS pct_minutes_full,
       ROUND(SUM(est_revenue_capped))                                    AS est_revenue_usd
FROM analytics.v_hourly_revenue
GROUP BY blockface_id, paid_area, paid_subarea, blockface_name, side_of_street
HAVING COUNT(*) >= 24 AND MAX(space_count) >= 3
ORDER BY occupancy_pct DESC, est_revenue_usd DESC
LIMIT 10;


-- =============================================================
-- Q7. Sustained overcrowding: runs of 3 or more consecutive hours in
-- which the block was completely full for at least half of the
-- minutes (blocks with 3+ spaces). A missing hour breaks a run.
-- (gaps-and-islands with ROW_NUMBER)
-- =============================================================
WITH full_hours AS (
    SELECT blockface_id, reading_date, hour_of_day,
           hour_of_day - ROW_NUMBER() OVER (PARTITION BY blockface_id, reading_date
                                            ORDER BY hour_of_day) AS grp
    FROM analytics.v_hourly_revenue
    WHERE space_count >= 3
      AND n_full >= 0.5 * n_readings
),
runs AS (
    SELECT blockface_id, reading_date, grp,
           COUNT(*)         AS run_hours,
           MIN(hour_of_day) AS start_hour,
           MAX(hour_of_day) AS last_hour
    FROM full_hours
    GROUP BY blockface_id, reading_date, grp
)
SELECT d.paid_area,
       d.blockface_name,
       d.side_of_street,
       d.space_count AS spaces,
       r.reading_date,
       r.start_hour,
       r.last_hour + 1 AS ends_at_hour,
       r.run_hours
FROM runs r
JOIN clean.dim_blockface d USING (blockface_id)
WHERE r.run_hours >= 3
ORDER BY r.run_hours DESC, d.paid_area, d.blockface_name, r.reading_date
LIMIT 20;


-- =============================================================
-- Q8. Revenue concentration: what share of estimated revenue comes
-- from the top fifth of block faces? (NTILE + window over aggregate)
-- =============================================================
WITH per_block AS (
    SELECT blockface_id, SUM(est_revenue_capped) AS revenue
    FROM analytics.v_hourly_revenue
    GROUP BY blockface_id
),
ranked AS (
    SELECT blockface_id, revenue,
           NTILE(5) OVER (ORDER BY revenue DESC) AS quintile
    FROM per_block
)
SELECT quintile,
       COUNT(*)                                                    AS blockfaces,
       ROUND(SUM(revenue))                                         AS est_revenue_usd,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)  AS pct_of_total_revenue
FROM ranked
GROUP BY quintile
ORDER BY quintile;


-- =============================================================
-- Q9. Idle blocks: the 10 emptiest block faces (at least 24 hours of
-- data) and the value of their empty space at posted rates.
-- Very low values can also mean a closure or construction.
-- =============================================================
SELECT paid_area,
       paid_subarea,
       blockface_name,
       side_of_street,
       MAX(space_count)                                                  AS spaces,
       COUNT(*)                                                          AS block_hours,
       ROUND(100.0 * SUM(avg_occupied_capped) / SUM(space_count), 1)     AS occupancy_pct,
       ROUND(SUM(unused_capacity_value))                                 AS unused_capacity_ceiling_usd
FROM analytics.v_hourly_revenue
GROUP BY blockface_id, paid_area, paid_subarea, blockface_name, side_of_street
HAVING COUNT(*) >= 24
ORDER BY occupancy_pct ASC, unused_capacity_ceiling_usd DESC
LIMIT 10;


-- =============================================================
-- Q10. Uptown 20:00-21:59 by day (the hours excluded from analysis).
-- Near zero every day supports the exclusion; a spike on one day
-- would suggest an event.
-- =============================================================
SELECT f.reading_date,
       f.day_name,
       f.hour_of_day,
       COUNT(DISTINCT f.blockface_id)                                  AS blockfaces,
       ROUND(100.0 * SUM(f.avg_occupied_capped) / SUM(f.space_count), 1) AS occupancy_pct
FROM clean.fact_blockface_hour f
JOIN clean.dim_blockface d USING (blockface_id)
WHERE d.paid_area = 'Uptown'
  AND NOT d.is_restricted
  AND f.hour_of_day >= 20
GROUP BY f.reading_date, f.day_name, f.hour_of_day
ORDER BY f.reading_date, f.hour_of_day;
