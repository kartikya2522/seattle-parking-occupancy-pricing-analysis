-- =============================================================
-- 08_pricing_scenario.sql
-- What if rates changed? A scenario model, NOT a forecast.
--
-- Needs 03 and 05 to have been run.
-- Run each query on its own in pgAdmin.
--
-- MODEL (every assumption belongs in the README)
--   * Changed rate -> changed occupancy with constant elasticity:
--         new_occupancy = old_occupancy x (new_rate / old_rate) ^ elasticity
--     capped at the block's capacity. Revenue = occupancy x rate.
--   * Elasticity is ASSUMED, not estimated from this data (the 11 AM rate
--     step could not identify it, see P2). Published values: SFpark average
--     about -0.4 (wide spread by block), Dublin on-street about -0.29,
--     literature reviews -0.1 to -0.3. Grid used: -0.1, -0.3, -0.5, and a
--     -1.0 stress case (the break-even where a price cut stops losing money).
--   * Rule (adapted from SDOT's 70-85% occupancy goal): move a rate by
--     $0.50 DOWN when occupancy is below 70%, UP when above 85%, hold in
--     between. Rates never fall below the floor of $0.50 (an assumption).
--   * Occupancy is the dataset's PAID occupancy; it may understate real
--     occupancy, which would make "below 70%" look more common than it is.
--   * Revenue ignores event pricing, holidays and any change in the number
--     of cars that never pay.
--
-- SCENARIOS
--   S0  Baseline: posted rates.
--   S1  SDOT-style rule applied per sub-area and band (how SDOT sets rates).
--   S2  The same rule applied per block face and band (finer targeting).
--   S3  Targeted increases only: +$0.50 on block-face/band cells already at
--       70% occupancy or more; no rate cuts anywhere.
-- =============================================================


-- =============================================================
-- S-A. Scenario grid: revenue, occupancy and how many hours change price
-- =============================================================
WITH cfg AS (
    SELECT 0.50::NUMERIC AS step_usd,
           0.50::NUMERIC AS floor_usd,
           0.70::NUMERIC AS low_occ,
           0.85::NUMERIC AS high_occ
),
elast AS (
    SELECT * FROM (VALUES (-0.1), (-0.3), (-0.5), (-1.0)) AS e (elasticity)
),
base AS (
    SELECT blockface_id, paid_area, paid_subarea, band, space_count,
           avg_occupied_capped AS occ,
           rate_per_hour       AS rate
    FROM analytics.v_hourly_revenue
),
unit_a AS (
    SELECT paid_area, paid_subarea, band, SUM(occ) / SUM(space_count) AS unit_occ
    FROM base
    GROUP BY paid_area, paid_subarea, band
),
unit_b AS (
    SELECT blockface_id, band, SUM(occ) / SUM(space_count) AS unit_occ
    FROM base
    GROUP BY blockface_id, band
),
steps AS (
    SELECT b.*,
           CASE WHEN ua.unit_occ < c.low_occ  THEN -c.step_usd
                WHEN ua.unit_occ > c.high_occ THEN  c.step_usd ELSE 0 END AS step_s1,
           CASE WHEN ub.unit_occ < c.low_occ  THEN -c.step_usd
                WHEN ub.unit_occ > c.high_occ THEN  c.step_usd ELSE 0 END AS step_s2,
           CASE WHEN ub.unit_occ >= c.low_occ THEN  c.step_usd ELSE 0 END AS step_s3
    FROM base b
    JOIN unit_a ua USING (paid_area, paid_subarea, band)
    JOIN unit_b ub USING (blockface_id, band)
    CROSS JOIN cfg c
),
scen AS (
    SELECT s.blockface_id, s.space_count, s.occ, s.rate, x.scenario, x.ord, x.step
    FROM steps s
    CROSS JOIN LATERAL (VALUES
        ('S0 Baseline (posted rates)',                0, 0::NUMERIC),
        ('S1 SDOT rule, sub-area level',              1, s.step_s1),
        ('S2 SDOT rule, block-face level',            2, s.step_s2),
        ('S3 Targeted increases only (occupancy>=70%)', 3, s.step_s3)
    ) AS x (scenario, ord, step)
),
calc AS (
    SELECT sc.scenario, sc.ord, e.elasticity, sc.occ, sc.rate, sc.space_count,
           CASE WHEN sc.rate = 0 THEN 0
                ELSE GREATEST(c.floor_usd, sc.rate + sc.step) END AS new_rate
    FROM scen sc
    CROSS JOIN elast e
    CROSS JOIN cfg c
),
calc2 AS (
    SELECT *,
           CASE WHEN rate = 0 THEN occ
                ELSE LEAST(space_count, occ * POWER(new_rate / rate, elasticity)) END AS new_occ
    FROM calc
)
SELECT scenario,
       elasticity,
       ROUND(SUM(new_occ * new_rate))                                         AS est_revenue_usd,
       ROUND(SUM(new_occ * new_rate) - SUM(occ * rate))                       AS change_usd,
       ROUND(100.0 * (SUM(new_occ * new_rate) - SUM(occ * rate))
             / SUM(occ * rate), 1)                                            AS change_pct,
       ROUND(100.0 * SUM(new_occ) / SUM(space_count), 1)                      AS occupancy_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE new_rate > rate) / COUNT(*), 1)   AS pct_hours_price_up,
       ROUND(100.0 * COUNT(*) FILTER (WHERE new_rate < rate) / COUNT(*), 1)   AS pct_hours_price_down
FROM calc2
GROUP BY scenario, ord, elasticity
ORDER BY ord, elasticity DESC;


-- =============================================================
-- S-B. Where would S3 (targeted increases) earn its money?
-- Block-face/band cells with occupancy >= 70%, ranked by estimated gain
-- of a +$0.50 increase at elasticity -0.3 (the middle of the range).
-- =============================================================
WITH bb AS (
    SELECT blockface_id, paid_area, paid_subarea, blockface_name, side_of_street, band,
           MAX(space_count)           AS spaces,
           MAX(rate_per_hour)         AS rate,
           COUNT(*)                   AS block_hours,
           SUM(avg_occupied_capped)   AS occ_sum,
           SUM(space_count)           AS cap_sum
    FROM analytics.v_hourly_revenue
    GROUP BY blockface_id, paid_area, paid_subarea, blockface_name, side_of_street, band
)
SELECT paid_area,
       paid_subarea,
       blockface_name,
       side_of_street,
       band,
       spaces,
       block_hours,
       rate                                                     AS current_rate,
       rate + 0.50                                              AS new_rate,
       ROUND(100.0 * occ_sum / cap_sum, 1)                      AS occupancy_pct,
       ROUND(occ_sum * rate)                                    AS baseline_revenue_usd,
       ROUND(occ_sum * POWER((rate + 0.50) / rate, -0.3) * (rate + 0.50)
             - occ_sum * rate)                                  AS est_gain_usd
FROM bb
WHERE occ_sum / cap_sum >= 0.70
  AND rate > 0
ORDER BY est_gain_usd DESC
LIMIT 15;
