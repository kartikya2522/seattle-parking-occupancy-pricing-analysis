-- =============================================================
-- 11_final_checks.sql
-- Four small checks that close the last open questions before the
-- README is written. Run each query on its own in pgAdmin.
-- Needs 03 and 05 to have been run on both weeks.
-- (source_file values are 'week1_2025-06-02' and 'week2_2025-06-30'.)
-- =============================================================


-- =============================================================
-- C1. Is the source rate column empty in BOTH weeks?
-- (Week 1 was 100% NULL. Week 2 was never checked.)
-- =============================================================
SELECT source_file,
       COUNT(*)                                                              AS raw_rows,
       COUNT(*) FILTER (WHERE paidparkingrate IS NULL)                       AS null_rate_rows,
       COUNT(*) FILTER (WHERE paidparkingrate = '0')                         AS zero_rate_rows,
       COUNT(*) FILTER (WHERE paidparkingrate IS NOT NULL
                          AND paidparkingrate <> '0')                        AS other_rate_rows
FROM raw.parking_occupancy
GROUP BY source_file
ORDER BY source_file;


-- =============================================================
-- C2. Do block-face attributes stay the same across the two weeks?
-- (Profiling R5 only covered week 1. The block-face table keeps the
-- latest week's attributes, so a change would be hidden.)
-- Expect every "changed" column to be 0.
-- =============================================================
SELECT COUNT(*)                                    AS blockfaces_total,
       COUNT(*) FILTER (WHERE n_weeks = 2)         AS in_both_weeks,
       COUNT(*) FILTER (WHERE n_weeks = 1)         AS in_one_week_only,
       COUNT(*) FILTER (WHERE n_names  > 1)        AS name_changed,
       COUNT(*) FILTER (WHERE n_spaces > 1)        AS capacity_changed,
       COUNT(*) FILTER (WHERE n_areas  > 1)        AS area_or_subarea_changed,
       COUNT(*) FILTER (WHERE n_limits > 1)        AS time_limit_changed,
       COUNT(*) FILTER (WHERE n_sides  > 1)        AS side_changed,
       COUNT(*) FILTER (WHERE n_cats   > 1)        AS category_changed
FROM (
    SELECT sourceelementkey,
           COUNT(DISTINCT source_file)                                        AS n_weeks,
           COUNT(DISTINCT blockfacename)                                      AS n_names,
           COUNT(DISTINCT parkingspacecount)                                  AS n_spaces,
           COUNT(DISTINCT paidparkingarea || '|' || COALESCE(paidparkingsubarea, '')) AS n_areas,
           COUNT(DISTINCT parkingtimelimitcategory)                           AS n_limits,
           COUNT(DISTINCT sideofstreet)                                       AS n_sides,
           COUNT(DISTINCT parkingcategory)                                    AS n_cats
    FROM raw.parking_occupancy
    GROUP BY sourceelementkey
) k;


-- =============================================================
-- C3. Why 453 block faces in week 1 but 455 across both weeks?
-- Lists paid block faces that have usable hours in only one week.
-- (usable = at least 30 readings in the hour, so it matches the analysis)
-- =============================================================
SELECT d.paid_area,
       d.paid_subarea,
       d.blockface_name,
       d.side_of_street,
       d.space_count,
       COUNT(*) FILTER (WHERE f.source_file LIKE 'week1%')                            AS hours_week1,
       COUNT(*) FILTER (WHERE f.source_file LIKE 'week1%' AND NOT f.is_low_coverage)  AS usable_hours_week1,
       COUNT(*) FILTER (WHERE f.source_file LIKE 'week2%')                            AS hours_week2,
       COUNT(*) FILTER (WHERE f.source_file LIKE 'week2%' AND NOT f.is_low_coverage)  AS usable_hours_week2
FROM clean.fact_blockface_hour f
JOIN clean.dim_blockface d USING (blockface_id)
WHERE NOT d.is_restricted
GROUP BY d.blockface_id, d.paid_area, d.paid_subarea, d.blockface_name, d.side_of_street, d.space_count
HAVING (COUNT(*) FILTER (WHERE f.source_file LIKE 'week1%' AND NOT f.is_low_coverage) = 0)
    <> (COUNT(*) FILTER (WHERE f.source_file LIKE 'week2%' AND NOT f.is_low_coverage) = 0)
ORDER BY d.paid_area, d.blockface_name;


-- =============================================================
-- C4. The $15 gap: why does the pricing baseline ($311,046) differ
-- from the revenue total ($311,061)?
-- Hypothesis: the revenue column is rounded to cents row by row, and
-- exact half-cent values always round up, which adds a small bias.
-- If "unrounded_total" comes out near 311,046, rounding explains it.
-- =============================================================
SELECT ROUND(SUM(est_revenue_capped), 2)                                   AS rounded_rows_total,
       ROUND(SUM(avg_occupied_capped * rate_per_hour), 2)                  AS unrounded_total,
       ROUND(SUM(est_revenue_capped) - SUM(avg_occupied_capped * rate_per_hour), 2) AS difference
FROM analytics.v_hourly_revenue;
