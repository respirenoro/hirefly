# Audit: Power BI module

## Benchmarks
- [PL-300 study guide](https://learn.microsoft.com/en-us/certifications/resources/study-guides/PL-300) (skills as of 20 April 2026): prepare the data 25-30%, model 25-30%, visualize and analyze 25-30%, manage and secure 15-20%.
- Microsoft Learn paths: [Get started with Power BI](https://learn.microsoft.com/en-us/training/paths/get-started-power-bi/), [Prepare data](https://learn.microsoft.com/en-us/training/paths/prepare-data-power-bi), [Model data](https://learn.microsoft.com/training/paths/model-power-bi), [Dashboard in a Day](https://learn.microsoft.com/training/paths/dashboard-in-a-day/).
- Free: [SQLBI Introducing DAX](https://www.sqlbi.com/articles/start-learning-dax-for-free/) and [data modelling](https://www.sqlbi.com/articles/start-learning-data-modeling-for-free/), [Guy in a Cube](https://www.youtube.com/@GuyInACube).
- Guidance: [star schema](https://learn.microsoft.com/power-bi/guidance/star-schema), [row-level security](https://learn.microsoft.com/power-bi/create-reports/desktop-rls).

## Gaps found
Concepts were covered, but nothing used the practice CSVs, so no lesson gave numbers to check. Missing: role-playing dates, profiling pitfalls, worked CALCULATE and month-over-month figures, bookmarks and tooltips, performance, sharing options and a PL-300-style drill.

## Changes
- Fixes: the shift dashboard lesson described columns and statuses that do not exist in the practice data (region, "Filled"); rewritten to the real files. Corrected the Contributor role description, an unsupported claim that a free personal account can publish, and a date-table sample with a skipped date.
- Added 12 lessons in units 7 to 11 (18 to 30); "In the interview" stays last.
- 12 resources, 7 labs ending in the full dashboard, with Python-computed figures (906 of 1019 shifts filled, 88.9%; 828 completed, 81.3%; average 9.52 hours; emergency 1.26 hours; FL 537 shifts).
- Interview questions raised from 7 to 16, all stating Power BI is new.

## Could not verify
- Nothing was built in Power BI Desktop. DAX, menu names and expected values were checked by Python and reasoning only.
- Guy in a Cube was confirmed only as a channel page; playlist contents were not seen.
- The Learn path pages were seen in search results only, not opened, so module lists are unconfirmed.
- Licensing and publishing rules change; the sharing lessons are conceptual.
- Dashboard in a Day is tied to a workshop; its current format was not checked.
