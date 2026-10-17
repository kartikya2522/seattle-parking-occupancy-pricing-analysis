-- =============================================================
-- 05_rates_and_revenue.sql
-- Adds the SDOT rate table, the time-band mapping, and a view with
-- ESTIMATED posted-rate revenue per block face per hour.
--
-- Run in pgAdmin Query Tool (whole file). Safe to re-run.
--
-- ASSUMPTIONS (every one of these belongs in the README)
--   1. Rates are SDOT's published hourly rates that took effect on
--      2025-03-10 and stayed in force until the next change on 2025-08-04
--      (source: SDOT blog post of 2025-03-07). Both planned weeks
--      (2-7 June and 30 June-5 July 2025) fall inside this period.
--   2. Band hours: Morning 8-11, Afternoon 11-17, Evening 17-close.
--      South Lake Union is the exception: its readings stop at 17:59 and
--      its evening rate is Free, so its afternoon band is treated as
--      running to 18:00. EDIT dim_time_band BELOW to test other choices.
--   3. Estimated revenue = average paid vehicles in the hour x posted
--      hourly rate x 1 hour. It ignores event-day pricing, holidays,
--      permits and anyone who parks without paying, so it is a MODEL,
--      not actual collections.
--   4. unused_capacity_value is a theoretical CEILING (every empty space
--      sold at the posted rate), not a realistic revenue opportunity.
-- =============================================================


-- =============================================================
-- SECTION 1: Rate table (SDOT rates effective 2025-03-10)
-- 'Free' evening rates are stored as 0.00.
-- =============================================================

DROP TABLE IF EXISTS analytics.dim_rate CASCADE;
CREATE TABLE analytics.dim_rate (
    paid_area      TEXT,
    paid_subarea   TEXT,
    band           TEXT CHECK (band IN ('Morning', 'Afternoon', 'Evening')),
    rate_per_hour  NUMERIC(5,2),
    effective_from DATE,
    effective_to   DATE,
    source         TEXT,
    PRIMARY KEY (paid_area, paid_subarea, band, effective_from)
);

INSERT INTO analytics.dim_rate
    (paid_area, paid_subarea, band, rate_per_hour, effective_from, effective_to, source)
SELECT paid_area, paid_subarea, band, rate_per_hour,
       DATE '2025-03-10', DATE '2025-08-03',
       'SDOT blog 2025-03-07: new rates as of March 10, 2025'
FROM (VALUES
    ('Columbia City',    'None',      'Morning',   1.00),
    ('Columbia City',    'None',      'Afternoon', 6.00),
    ('Columbia City',    'None',      'Evening',   6.00),
    ('Commercial Core',  'Financial', 'Morning',   1.00),
    ('Commercial Core',  'Financial', 'Afternoon', 1.00),
    ('Commercial Core',  'Financial', 'Evening',   1.00),
    ('Commercial Core',  'Retail',    'Morning',   2.00),
    ('Commercial Core',  'Retail',    'Afternoon', 4.50),
    ('Commercial Core',  'Retail',    'Evening',   1.50),
    ('Commercial Core',  'Waterfront','Morning',   1.00),
    ('Commercial Core',  'Waterfront','Afternoon', 6.50),
    ('Commercial Core',  'Waterfront','Evening',   5.00),
    ('Fremont',          'None',      'Morning',   1.00),
    ('Fremont',          'None',      'Afternoon', 6.00),
    ('Fremont',          'None',      'Evening',   6.50),
    ('South Lake Union', 'North',     'Morning',   1.00),
    ('South Lake Union', 'North',     'Afternoon', 1.00),
    ('South Lake Union', 'North',     'Evening',   0.00),
    ('South Lake Union', 'South',     'Morning',   1.00),
    ('South Lake Union', 'South',     'Afternoon', 4.50),
    ('South Lake Union', 'South',     'Evening',   0.00),
    ('Uptown',           'None',      'Morning',   1.00),
    ('Uptown',           'None',      'Afternoon', 3.00),
    ('Uptown',           'None',      'Evening',   2.00)
) AS r (paid_area, paid_subarea, band, rate_per_hour);


-- =============================================================
-- SECTION 2: Time-band mapping (hour of day -> rate band)
-- first_hour / last_hour are inclusive hours of the day (0-23).
-- =============================================================

DROP TABLE IF EXISTS analytics.dim_time_band CASCADE;
CREATE TABLE analytics.dim_time_band (
    paid_area  TEXT,
    band       TEXT CHECK (band IN ('Morning', 'Afternoon', 'Evening')),
    first_hour INT,
    last_hour  INT,
    note       TEXT,
    PRIMARY KEY (paid_area, band)
);

INSERT INTO analytics.dim_time_band (paid_area, band, first_hour, last_hour, note)
SELECT a.paid_area, b.band, b.first_hour, b.last_hour,
       'Default bands 8-11 / 11-17 / 17-close (SDOT 2023 post, 2017 maps)'
FROM (VALUES ('Columbia City'), ('Commercial Core'), ('Fremont'), ('Uptown')) AS a (paid_area)
CROSS JOIN (VALUES ('Morning', 8, 10), ('Afternoon', 11, 16), ('Evening', 17, 21))
           AS b (band, first_hour, last_hour);

INSERT INTO analytics.dim_time_band (paid_area, band, first_hour, last_hour, note)
VALUES
    ('South Lake Union', 'Morning',    8, 10, 'Default morning band'),
    ('South Lake Union', 'Afternoon', 11, 17, 'ASSUMPTION: afternoon runs to 6 PM (data stops at 17:59, evening rate is Free)'),
    ('South Lake Union', 'Evening',   18, 21, 'Free evening; no readings in the data');


-- =============================================================
-- SECTION 3: Estimated revenue view
-- LEFT JOINs so that a missing band or rate shows up as NULL
-- (and is counted in V5) instead of silently dropping rows.
-- =============================================================

DROP VIEW IF EXISTS analytics.v_hourly_revenue;
CREATE VIEW analytics.v_hourly_revenue AS
SELECT v.*,
       tb.band,
       r.rate_per_hour,
       ROUND(v.avg_occupied_capped * r.rate_per_hour, 2)                        AS est_revenue_capped,
       ROUND(v.avg_occupied        * r.rate_per_hour, 2)                        AS est_revenue_uncapped,
       ROUND((v.space_count - v.avg_occupied_capped) * r.rate_per_hour, 2)      AS unused_capacity_value
FROM analytics.v_hourly v
LEFT JOIN analytics.dim_time_band tb
       ON tb.paid_area = v.paid_area
      AND v.hour_of_day BETWEEN tb.first_hour AND tb.last_hour
LEFT JOIN analytics.dim_rate r
       ON r.paid_area    = v.paid_area
      AND r.paid_subarea = v.paid_subarea
      AND r.band         = tb.band
      AND v.reading_date BETWEEN r.effective_from AND r.effective_to;


-- =============================================================
-- SECTION 4: Verification (run each query)
-- =============================================================

-- V5: every analysis row must have a band and a rate (week 1: 29,682 / 0 / 0)
SELECT COUNT(*)                                         AS rows_in_view,
       COUNT(*) FILTER (WHERE band IS NULL)             AS missing_band,
       COUNT(*) FILTER (WHERE rate_per_hour IS NULL)    AS missing_rate
FROM analytics.v_hourly_revenue;


-- V6: occupancy and estimated revenue by area and band
SELECT paid_area,
       band,
       COUNT(*)                                                       AS block_hours,
       ROUND(100.0 * SUM(avg_occupied_capped) / SUM(space_count), 1)  AS weighted_occupancy_pct,
       ROUND(SUM(est_revenue_capped))                                 AS est_revenue_usd
FROM analytics.v_hourly_revenue
GROUP BY paid_area, band
ORDER BY paid_area, MIN(hour_of_day);


-- V7: totals for the week (capped vs uncapped, and the theoretical ceiling)
SELECT ROUND(SUM(est_revenue_capped))    AS est_revenue_capped_usd,
       ROUND(SUM(est_revenue_uncapped))  AS est_revenue_uncapped_usd,
       ROUND(SUM(unused_capacity_value)) AS unused_capacity_ceiling_usd
FROM analytics.v_hourly_revenue;
