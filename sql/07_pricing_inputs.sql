-- =============================================================
-- 07_pricing_inputs.sql
-- Inputs for the dynamic-pricing scenario. SDOT sets rates per
-- sub-area and time band, so that is the unit used here.
--
-- Needs 03 and 05 to have been run (no need to re-run them).
-- Run each query on its own in pgAdmin.
-- Occupancy is capped at 100% and weighted by capacity.
-- =============================================================


-- =============================================================
-- P1. The pricing unit: sub-area x band, with the current rate,
-- occupancy, minute-level states and estimated revenue.
-- =============================================================
SELECT paid_area,
       paid_subarea,
       band,
       MAX(rate_per_hour)                                             AS rate_usd,
       COUNT(DISTINCT blockface_id)                                   AS blockfaces,
       COUNT(*)                                                       AS block_hours,
       ROUND(100.0 * SUM(avg_occupied_capped) / SUM(space_count), 1)  AS occupancy_pct,
       ROUND(100.0 * SUM(n_full)       / SUM(n_readings), 1)          AS pct_min_full,
       ROUND(100.0 * SUM(n_open_1_2)   / SUM(n_readings), 1)          AS pct_min_1_to_2_open,
       ROUND(100.0 * SUM(n_open_3plus) / SUM(n_readings), 1)          AS pct_min_3plus_open,
       ROUND(SUM(est_revenue_capped))                                 AS est_revenue_usd
FROM analytics.v_hourly_revenue
GROUP BY paid_area, paid_subarea, band
ORDER BY paid_area, paid_subarea,
         CASE band WHEN 'Morning' THEN 1 WHEN 'Afternoon' THEN 2 ELSE 3 END;


-- =============================================================
-- P2. The 11 AM rate step as a rough natural experiment.
-- Many sub-areas jump from the morning to the afternoon rate at 11:00;
-- two (Commercial Core Financial, South Lake Union North) do not.
--   pre  = hours 9-10  (before the step)
--   post = hours 12-13 (after the step; cars parked earlier have left)
-- The unchanged sub-areas show how occupancy moves between those hours
-- anyway. implied_elasticity = LN(change relative to the unchanged
-- sub-areas) / LN(rate ratio). Treat it as a rough range, not a fact:
-- time-of-day demand differs by area and the groups are not identical.
-- =============================================================
WITH step AS (
    SELECT paid_area, paid_subarea,
           MAX(rate_per_hour) FILTER (WHERE band = 'Morning')   AS morning_rate,
           MAX(rate_per_hour) FILTER (WHERE band = 'Afternoon') AS afternoon_rate
    FROM analytics.dim_rate
    WHERE effective_from = DATE '2025-03-10'
    GROUP BY paid_area, paid_subarea
),
occ AS (
    SELECT paid_area, paid_subarea,
           SUM(avg_occupied_capped) FILTER (WHERE hour_of_day IN (9, 10))  AS pre_occ,
           SUM(space_count)         FILTER (WHERE hour_of_day IN (9, 10))  AS pre_cap,
           SUM(avg_occupied_capped) FILTER (WHERE hour_of_day IN (12, 13)) AS post_occ,
           SUM(space_count)         FILTER (WHERE hour_of_day IN (12, 13)) AS post_cap
    FROM analytics.v_hourly_revenue
    GROUP BY paid_area, paid_subarea
),
joined AS (
    SELECT s.paid_area, s.paid_subarea, s.morning_rate, s.afternoon_rate,
           o.pre_occ, o.pre_cap, o.post_occ, o.post_cap,
           (s.afternoon_rate = s.morning_rate) AS is_control
    FROM step s
    JOIN occ o USING (paid_area, paid_subarea)
),
control AS (
    SELECT (SUM(post_occ) / SUM(post_cap)) / (SUM(pre_occ) / SUM(pre_cap)) AS control_ratio
    FROM joined
    WHERE is_control
)
SELECT j.paid_area,
       j.paid_subarea,
       j.morning_rate,
       j.afternoon_rate,
       CASE WHEN j.is_control THEN 'unchanged (control)' ELSE 'rate rises at 11:00' END AS group_type,
       ROUND(100.0 * j.pre_occ  / j.pre_cap,  1)                  AS pre_occupancy_pct,
       ROUND(100.0 * j.post_occ / j.post_cap, 1)                  AS post_occupancy_pct,
       ROUND((j.post_occ / j.post_cap) / (j.pre_occ / j.pre_cap), 2) AS post_vs_pre_ratio,
       ROUND(c.control_ratio, 2)                                  AS control_ratio,
       ROUND(LN(((j.post_occ / j.post_cap) / (j.pre_occ / j.pre_cap)) / c.control_ratio)
             / NULLIF(LN(j.afternoon_rate / NULLIF(j.morning_rate, 0)), 0), 2)
            AS implied_elasticity
FROM joined j
CROSS JOIN control c
ORDER BY j.is_control DESC, j.paid_area, j.paid_subarea;


-- =============================================================
-- P3. Block-level view of SDOT's 70-85% occupancy band.
-- For every block face and band: below 70%, inside 70-85%, above 85%.
-- Shows how much a single sub-area rate hides: hot and idle blocks
-- often share the same posted rate.
-- =============================================================
WITH bb AS (
    SELECT paid_area, paid_subarea, band, blockface_id,
           SUM(avg_occupied_capped) / NULLIF(SUM(space_count), 0) AS occ
    FROM analytics.v_hourly_revenue
    GROUP BY paid_area, paid_subarea, band, blockface_id
)
SELECT paid_area,
       paid_subarea,
       band,
       COUNT(*)                                                         AS blockfaces,
       COUNT(*) FILTER (WHERE occ <  0.70)                              AS below_70,
       COUNT(*) FILTER (WHERE occ >= 0.70 AND occ <= 0.85)              AS in_70_to_85,
       COUNT(*) FILTER (WHERE occ >  0.85)                              AS above_85,
       ROUND(100.0 * COUNT(*) FILTER (WHERE occ <  0.70) / COUNT(*), 1) AS pct_below_70,
       ROUND(100.0 * COUNT(*) FILTER (WHERE occ >= 0.70 AND occ <= 0.85) / COUNT(*), 1) AS pct_in_band,
       ROUND(100.0 * COUNT(*) FILTER (WHERE occ >  0.85) / COUNT(*), 1) AS pct_above_85
FROM bb
GROUP BY paid_area, paid_subarea, band
ORDER BY paid_area, paid_subarea,
         CASE band WHEN 'Morning' THEN 1 WHEN 'Afternoon' THEN 2 ELSE 3 END;
