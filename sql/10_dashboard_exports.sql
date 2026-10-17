-- =============================================================
-- 10_dashboard_exports.sql
-- Exports three CSVs for the Excel dashboard. Run each \copy line
-- in psql (not pgAdmin) — one at a time, after 03/05 have both
-- been run on the full two-week data.
--
-- File 1: fact_blockface_hour.csv  (~52K rows) — the main table.
--         Build PivotTables + slicers on this directly. This is
--         ACTUAL data at block-face/hour grain, not pre-aggregated,
--         so every pivot and slicer in Excel is doing real work.
-- File 2: dim_blockface.csv        (~460 rows)  — lookup table for
--         an honest XLOOKUP example (block name -> lat/long/spaces).
-- File 3: dim_rate.csv             (~24 rows)   — lookup table for
--         XLOOKUP on posted rate by area/subarea/band.
--
-- Edit the output paths before running (use forward slashes).
-- =============================================================

\copy (SELECT source_file, blockface_id, blockface_name, side_of_street, paid_area, paid_subarea, band, reading_date, day_name, hour_of_day, space_count, ROUND(avg_occupied_capped,2) AS avg_occupied, ROUND(occupancy_rate*100,1) AS occupancy_pct, rate_per_hour, est_revenue_capped, n_readings FROM analytics.v_hourly_revenue ORDER BY reading_date, hour_of_day, paid_area, blockface_id) TO 'C:/Users/karti/Downloads/fact_blockface_hour.csv' WITH (FORMAT csv, HEADER true)

\copy (SELECT blockface_id, blockface_name, side_of_street, paid_area, paid_subarea, space_count, time_limit_category, latitude, longitude FROM clean.dim_blockface WHERE NOT is_restricted ORDER BY paid_area, blockface_name) TO 'C:/Users/karti/Downloads/dim_blockface.csv' WITH (FORMAT csv, HEADER true)

\copy (SELECT paid_area, paid_subarea, band, rate_per_hour FROM analytics.dim_rate WHERE effective_from = DATE '2025-03-10' ORDER BY paid_area, paid_subarea, band) TO 'C:/Users/karti/Downloads/dim_rate.csv' WITH (FORMAT csv, HEADER true)
