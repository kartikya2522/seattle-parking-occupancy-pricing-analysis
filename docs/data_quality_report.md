# Data quality report

How the raw Seattle paid-parking occupancy readings were checked, cleaned and reduced to the analysis grain. The check table comes from the cleaning log built by `sql/03_clean_layer.sql`, run on both weeks combined. The block-face, rate and rounding results come from `sql/11_final_checks.sql`.

## Source

- Seattle Open Data paid parking occupancy (view `7c2e-uany`), downloaded through the SODA API as two one-week extracts.
- Week 1: 2025-06-02 to 2025-06-07, 1,921,428 rows. Week 2: 2025-06-30 to 2025-07-05, 1,571,355 rows. Total: **3,492,783 raw rows**.
- The raw layer is loaded as-is and never modified. Cleaning happens in the `clean` and `analytics` schemas.

## Check results (both weeks)

| # | Check | Rows affected | Share | Treatment |
|---|---|---:|---:|---|
| 1 | Raw rows loaded | 3,492,783 | 100% | Reference count |
| 2 | Non-numeric occupancy, capacity or block-face key | 0 | 0% | Would stop the pipeline |
| 3 | Duplicate readings (same block face and timestamp) | 0 | 0% | One reading kept per block face and timestamp |
| 4 | Restricted Parking Zone readings | 250,208 | 7.16% | Flagged `is_restricted`, excluded (near-zero paid occupancy) |
| 5 | Paid occupancy above space count | 91,020 | 2.61% | Kept and flagged. Headline occupancy is capped at 100%, uncapped kept for sensitivity |
| 6 | Missing paid sub-area (area has no sub-areas) | 1,260,031 | 36.08% | Filled with `None`. Not an error |
| 7 | Hourly block-face rows built from raw readings | 58,399 | 100% | Reference count at hourly grain |
| 8 | Low-coverage hours (under 30 readings) | 187 | 0.32% | Flagged `is_low_coverage`, excluded |
| 9 | Uptown 20:00-21:59 | 2,416 | 4.14% | Excluded (near-zero occupancy outside Uptown's paid window) |
| 10 | **Hourly rows available for analysis** | **51,626** | **88.40%** | `analytics.v_hourly` |

Final analysis grain: **51,626 block-face-hours across 455 block faces** in 5 paid areas, with 0 rows missing a band or a rate.

Checks 1-6 count raw readings; checks 7-10 count block-face-hours. Restricted-zone hours are removed between checks 7 and 10 but are not reported as a separate row. Check 9 counts only unrestricted hours with enough readings, and the analysis view removes only these three groups, so the 4,170 hours that remain unexplained (58,399 - 187 - 2,416 - 51,626) are restricted-zone hours with enough readings. This figure is derived from the other counts, not queried directly.

Block-face count: 453 paid block faces report usable hours in week 1 and 453 in week 2 (the second figure is derived from the totals), and 455 appear across both weeks. Four block faces have usable hours in only one week, 136 of the 51,626 analysis hours (0.26%):

| Only in | Area / sub-area | Block face | Usable hours |
|---|---|---|---:|
| Week 1 | Commercial Core / Financial | 5th Ave between Marion St and Madison St | 18 (20 reported) |
| Week 1 | South Lake Union / North | Dexter Ave N between Prospect St and Highland Dr | 10 |
| Week 2 | Commercial Core / Retail | 9th Ave between the I-5 express ramp and Pine St | 60 |
| Week 2 | Commercial Core / Retail | University St between 5th Ave and 6th Ave | 48 |

The source gives no reason (closures, new spaces and data gaps are all possible), and the effect on any total is negligible.

## Rules and why they were chosen

- **Restricted zones excluded.** Their paid occupancy is near zero, so including them would drag every average down without describing paid parking.
- **Over-capacity readings capped, not dropped.** 2.61% of readings report more paid vehicles than spaces. Headline occupancy and revenue use the capped value. Uncapped is kept: overall occupancy is 32.0% capped and 32.7% uncapped, and estimated revenue is $311,061 capped versus $318,887 uncapped.
- **Uptown 20:00-21:59 excluded.** Occupancy in those hours is 0.2% to 0.5% at 20:00 and 0.0% at 21:00 on every one of the 11 days, with no event spikes, so the exclusion is systematic rather than a one-week observation.
- **Low-coverage hours excluded.** An hour with under 30 readings is too thin to average reliably.
- **Missing sub-area is not a defect.** Columbia City, Fremont and Uptown simply have no sub-areas.
- **One row per block face is safe.** 490 block faces appear in both weeks of the raw data, and none of them changes name, capacity, side of street, area or sub-area, time-limit category or parking category between the weeks.

## Known gaps and quirks in the source

- **No data for Friday 2025-07-04.** The extract has zero rows for that day, not low occupancy. The five week-2 days present (Mon-Thu and Sat) sum to exactly the 1,571,355 rows downloaded, so this is not a download or filtering artefact. It is consistent with paid parking not operating on the holiday, but the dataset does not state a reason.
- **Rates are not in the dataset.** The source rate column (`paidparkingrate`) is empty (NULL) on every row in both weeks (1,921,428 of 1,921,428 in week 1 and 1,571,355 of 1,571,355 in week 2), although the portal preview displays it as 0. Revenue is therefore modelled from SDOT's published rates (see assumptions in `sql/05_rates_and_revenue.sql`).
- **Sampled days.** The data covers two Mon-Sat sample weeks (11 days), not a continuous period.
- **Paid occupancy only.** It can understate real occupancy, because vehicles that do not pay are not counted.
- **Coverage by hour was checked on week 1 only.** `04_coverage_check.sql` assumes 6 days. Week 1 coverage was complete for Columbia City but lower in some Commercial Core hours (for example 78.9% at 08:00). No coverage percentage is quoted for the full two-week period.

## Dashboard consistency

The Excel dashboard reproduces the SQL totals exactly: revenue $311,061, occupancy 32.0%, 455 block faces, and all five area revenue and occupancy figures.

The pricing scenarios start from a baseline of $311,046, which is $15.66 (0.005%) below the dashboard's $311,061.34. This is rounding, not an error. The revenue column is rounded to cents row by row, and exact half-cent values round up. Summing the unrounded values gives $311,045.68, which is the scenario baseline. Headline figures are quoted as about $311K.
