# Findings

Seattle paid on-street parking, two sample weeks (2025-06-02 to 06-07 and 2025-06-30 to 07-05, 11 days with data). Figures come from the SQL scripts in `sql/`. The hour-by-hour and day-by-day figures are read from the Excel dashboard pivots, which reproduce the SQL totals exactly (revenue, occupancy, block faces and every per-area result). Revenue is a **model**: average paid vehicles in the hour × SDOT posted hourly rate (effective 2025-03-10). It is not actual collections.

## Headline numbers

| Metric | Value |
|---|---|
| Block faces analysed | 455 (453 report in each week, 4 in only one) |
| Block-face-hours | 51,626 |
| Estimated revenue (11 days) | ~$311K (about $28K per day, $62 per block face per day) |
| Occupancy (capacity-weighted, capped at 100%) | 32.0% |
| Theoretical unused-capacity ceiling | ~$645K (every empty space sold at the posted rate, so not a realistic opportunity) |

## 1. Revenue is concentrated in two areas and the afternoon

| Area | Est. revenue | Share | Occupancy | Revenue per block face per day |
|---|---:|---:|---:|---:|
| Commercial Core | $115,481 | 37.1% | 42.4% | $83 |
| South Lake Union | $98,440 | 31.6% | 28.5% | $47 |
| Uptown | $66,963 | 21.5% | 28.6% | $52 |
| Fremont | $16,984 | 5.5% | 35.8% | $154 |
| Columbia City | $13,192 | 4.2% | 31.6% | $120 |

- By band: Afternoon 74.2%, Evening 16.4%, Morning 9.3% of revenue.
- The two largest areas earn 68.8% of revenue. Fremont and Columbia City earn the most per block face (only 10 block faces each) because their afternoon and evening rates are among the highest ($6.00 to $6.50) while occupancy is 32-36%.
- South Lake Union has no paid parking after 17:59 and a free evening rate, so it has no Evening revenue.
- Revenue is also concentrated by block face. The top fifth of block faces (91 of 455) earns 48.5% of estimated revenue ($151K), the top two fifths earn 71.2%, and the bottom fifth earns only 4.1% ($12.7K). Week 1 alone gave 47.9% for the top fifth, so the pattern is stable.

## 2. Demand peaks around midday and differs by area

- Pooled occupancy climbs from 19.2% at 08:00 to 38.3% at 12:00, dips to about 28% at 16:00-17:00, then reads about 40% at 18:00-19:00. The evening figures cover four areas only, because South Lake Union has no paid hours after 17:59, so the pooled curve is not like-for-like across the day.
- Commercial Core peaks at 50.4% at 12:00 and stays between 39% and 50% from 11:00 to 17:00.
- Fremont is evening-led: only 5.1% at 08:00 but 47.0% to 49.1% at 18:00-19:00. Uptown also rises in the evening, to 38.9% and 42.0% at 18:00 and 19:00, against a daytime maximum of 32.2% at 17:00.
- South Lake Union stays below 36% in every hour it operates.

## 3. Most blocks sit below SDOT's 70-85% occupancy target

SDOT's stated aim is roughly 1-2 open spaces per block, and its rate rule targets 70-85% occupancy for each time period in each area. Across the 1,172 block-face and band combinations:

- **95.6% are below 70% occupancy**, 3.7% are inside the 70-85% target band, and only 0.7% are above 85%.
- Every South Lake Union South afternoon block is below 70%, even though its posted afternoon rate is $4.50. This sub-area earns 24.2% of all estimated revenue, yet its afternoon occupancy is 21.0%, with 3+ spaces open in 83.0% of minutes.
- Block size matters. Blocks with 1-3 spaces are completely full in 20.2% of minutes, against 2.6% for blocks with 8+ spaces, because one car changes a small block's state.

## 4. A few blocks are persistently full; others are nearly empty

- Busiest block with 3+ spaces: Madison St between Post Ave and 1st Ave (Waterfront), 84.2% occupancy and full 68.4% of minutes. Others at 73-80% are mostly 1st Ave Retail blocks and South Lake Union North blocks (Valley St, 9th Ave N, Eastlake Ave E).
- **Sustained overcrowding replicates across weeks.** Madison St had a 12-hour run (08:00-20:00) of being full for at least half of the minutes on 2025-06-06, and further 10-11 hour runs in week 2 (06-30, 07-03, 07-05) and on 06-07. Runs of 8 to 9 hours also appear on several South Lake Union blocks (9th Ave N, Valley St, Eastlake Ave E, E Nelson Pl).
- The 10 emptiest blocks run from 2.2% to 6.2% occupancy: five in South Lake Union South, three in Uptown and two on the Waterfront. Very low values can also mean a closure or construction.

## 5. Week-over-week stability, and one pattern that did not repeat

- Area occupancy is stable between week 1 and the two weeks combined (for example Commercial Core 41.9% to 42.4%).
- Daily revenue is steady at roughly $25.6K to $29.9K, except Saturday 2025-06-07 at $34.2K. The other Saturday, 2025-07-05, was only $27.5K, so there is no consistent Saturday revenue peak.
- **Week 1's Saturday uplift in Uptown (+14.7 points over weekdays) did not repeat in week 2 (+0.9).** South Lake Union was lower on Saturday in both weeks (-6.1, then -10.3). Saturday effects should not be generalised from one week.
- **No data exists for Friday 2025-07-04** (zero rows in the extract), consistent with paid parking not operating on the holiday.

## 6. Pricing scenarios

The model changes a rate by $0.50 (down below 70% occupancy, up above 85%, hold in between, floor $0.50) and moves occupancy with a constant elasticity, capped at capacity. Elasticity is **assumed**, not estimated from this data. The three main values (-0.1, -0.3, -0.5) bracket published averages of about -0.4 (SFpark, first year) and about -0.3 (a California Air Resources Board literature review), and -1.0 is a stress case with no source behind it.

| Scenario | -0.1 | -0.3 | -0.5 | -1.0 |
|---|---:|---:|---:|---:|
| S1 SDOT rule per sub-area and band | -16.9% | -14.0% | -11.1% | -3.7% |
| S2 SDOT rule per block face and band | -15.3% | -12.6% | -9.8% | -2.9% |
| S3 targeted increases only (cells at 70%+ occupancy) | +1.4% | +1.0% | +0.7% | 0.0% |

(Changes are in estimated revenue versus the posted-rate baseline.)

- Because 95.6% of cells sit below 70%, SDOT's availability rule lowers rates almost everywhere. That trades revenue for occupancy (32.0% rises to 33.2%-43.9% in S1). Even at unit elasticity it still loses revenue.
- A targeted increase on already-busy blocks (S3) never cuts a rate and adds roughly 0.7% to 1.4% (about $2K to $4K) over the 11 days of data at elasticities of -0.5 to -0.1. It is small and has no downside in the model.
- Top S3 candidates are blocks at 70-92% occupancy, such as Uptown 2nd Ave N (Denny Way to John St), several 1st Ave Retail blocks, Eastlake Ave E and Alaskan Way.
- **The 11:00 rate step could not identify elasticity.** In sub-areas where the rate jumped at 11:00, occupancy rose rather than fell (implied values between -0.09 and +0.46), because time-of-day demand growth dominates. That is why elasticity is assumed. South Lake Union South was the only one that stayed flat despite a $1.00 to $4.50 jump.

## 7. Recommendations

These follow from the findings above and carry their caveats: two sample weeks and assumed elasticities.

1. **Raise rates only where blocks are already busy.** A $0.50 increase on block-face and time-band combinations at 70%+ occupancy adds about 0.7% to 1.4% in the model and never cuts a rate (S3). The gain is small, so treat it as a low-risk first step.
2. **Do not apply the occupancy rule across the board if revenue is the goal.** The rule is built to free up spaces, not to raise revenue. Because 95.6% of cells are below 70%, it lowers rates almost everywhere and costs 3.7% to 16.9% of modelled revenue (S1 and S2). Whether that trade is worthwhile depends on how much the city values open spaces.
3. **Set rates per block face where one sub-area rate hides both full and empty blocks.** Block-face rules (S2) lose less revenue than sub-area rules (S1) at every elasticity tested.
4. **Review the persistently full and persistently empty blocks.** Madison St between Post Ave and 1st Ave is full in 68.4% of minutes and has repeated 10-12 hour overcrowding runs. South Lake Union South has a $4.50 afternoon rate with 21.0% occupancy and 3+ spaces open in 83.0% of minutes. Both are candidates for a rate or time-limit review.
5. **Pilot before rolling out.** The data could not identify elasticity (section 6), so any price change should start as a controlled pilot with a before-and-after comparison.

## Limitations

- Two sample weeks (11 days), Monday to Saturday, no Sundays, one season.
- Revenue is modelled from posted rates, ignoring event pricing, holidays, permits and non-payers. Revenue per block face per day divides by the 11 days with data.
- Paid occupancy may understate real occupancy, so "below 70%" may be overstated.
- The scenario model works with unrounded revenue (baseline $311,045.68), while the dashboard sums row values rounded to cents ($311,061.34). The $15.66 (0.005%) difference is rounding, confirmed by recomputing the unrounded sum, so headline figures are quoted as about $311K.
- Four of the 455 block faces report in only one of the two weeks (136 analysis hours, 0.26%), with no reason given in the source. See `data_quality_report.md`.
- Pricing results depend on assumed elasticities and a fixed $0.50 step. SDOT's larger $1.00 step above 100% occupancy is not modelled.
- Rates are SDOT's schedule effective 2025-03-10, applied to every day. Both sample weeks fall inside that schedule.

## Sources

- Seattle Open Data, [2025 Paid Parking Occupancy](https://catalog.data.gov/dataset/2025-paid-parking-occupancy).
- SDOT, [Street parking rate update, March 10, 2025](https://sdotblog.seattle.gov/2025/03/07/street-parking-rate-update-march-10-2025/): hourly rates and the 1-2 open spaces aim.
- SDOT, [2022 Paid Parking Annual Report](https://www.seattle.gov/documents/Departments/SDOT/ParkingProgram/PaidParking/2022_PaidParking_Annual_Report.pdf): 70-85% target occupancy and $0.50 rate steps.
- Pierce and Shoup, SFpark first-year price elasticity of about -0.4, summarised in [Access Magazine](https://www.accessmagazine.org/fall-2013/sfpark-pricing-parking-demand/).
- California Air Resources Board, [Impacts of Parking Pricing](https://ww2.arb.ca.gov/sites/default/files/2020-06/Impacts_of_Parking_Pricing_Based_on_a_Review_of_the_Empirical_Literature_Technical_Background_Document_0.pdf): average elasticity of about -0.3.
