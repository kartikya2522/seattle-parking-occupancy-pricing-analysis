-- =============================================================
-- 04_coverage_check.sql
-- Why are there fewer block-face-hours than expected?
-- Run each query on its own in pgAdmin.
-- =============================================================


-- CHECK C1: Coverage by area and hour of day
-- coverage_pct = block-hours present / (block faces in area x 6 days)
SELECT d.paid_area,
       f.hour_of_day,
       COUNT(*)                                          AS block_hours_present,
       t.n_blockfaces * 6                                AS block_hours_if_all_report,
       ROUND(100.0 * COUNT(*) / (t.n_blockfaces * 6), 1) AS coverage_pct
FROM clean.fact_blockface_hour f
JOIN clean.dim_blockface d USING (blockface_id)
JOIN (
    SELECT paid_area, COUNT(*) AS n_blockfaces
    FROM clean.dim_blockface
    WHERE NOT is_restricted
    GROUP BY paid_area
) t USING (paid_area)
WHERE NOT d.is_restricted
GROUP BY d.paid_area, f.hour_of_day, t.n_blockfaces
ORDER BY d.paid_area, f.hour_of_day;


-- CHECK C2: Coverage by area and day
SELECT d.paid_area,
       f.reading_date,
       f.day_name,
       COUNT(*)                        AS block_hours_present,
       COUNT(DISTINCT f.blockface_id)  AS blockfaces_reporting
FROM clean.fact_blockface_hour f
JOIN clean.dim_blockface d USING (blockface_id)
WHERE NOT d.is_restricted
GROUP BY d.paid_area, f.reading_date, f.day_name
ORDER BY d.paid_area, f.reading_date;


-- CHECK C3: Are the missing hours concentrated in a few block faces?
WITH b AS (
    SELECT d.paid_area, f.blockface_id, COUNT(*) AS hrs
    FROM clean.fact_blockface_hour f
    JOIN clean.dim_blockface d USING (blockface_id)
    WHERE NOT d.is_restricted
    GROUP BY d.paid_area, f.blockface_id
),
m AS (
    SELECT paid_area, MAX(hrs) AS max_hrs
    FROM b
    GROUP BY paid_area
)
SELECT b.paid_area,
       m.max_hrs                                         AS most_hours_any_blockface,
       COUNT(*)                                          AS blockfaces,
       COUNT(*) FILTER (WHERE b.hrs = m.max_hrs)         AS blockfaces_with_full_hours,
       MIN(b.hrs)                                        AS fewest_hours,
       ROUND(AVG(b.hrs), 1)                              AS avg_hours
FROM b
JOIN m USING (paid_area)
GROUP BY b.paid_area, m.max_hrs
ORDER BY b.paid_area;
