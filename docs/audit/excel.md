# Audit: Excel module

## Benchmarks
- [MO-200 Excel Associate](https://learn.microsoft.com/certifications/exams/mo-200): worksheets and workbooks (10-15%), cells and ranges (20-25%), tables (15-20%), formulas and functions (20-25%), charts (20-25%).
- Microsoft Support: [Power Query and Power Pivot overview](https://support.microsoft.com/office/learn-to-use-power-query-and-power-pivot-in-excel-42d895c2-d1d7-41d0-88da-d1ed7ecc102d), [new array functions](https://support.microsoft.com/en-US/Excel/new-array-functions).
- Free courses: [freeCodeCamp](https://www.freecodecamp.org/news/learn-microsoft-excel), [Leila Gharani](https://www.xelplus.com/free-excel-tutorials/), [Kevin Stratvert](https://kevinstratvert.com/2026/03/30/excel-tutorial-for-beginners-start-here/), [ExcelIsFun](https://m.youtube.com/user/ExcelIsFun).
- Timed assessments: [TestGorilla](https://testgorilla.com/test-library/software-skills-tests/microsoft-excel-skills-test) and [Exponent](https://www.tryexponent.com/courses/product-analytics/data-analytics-technical/how-excel-and-google-sheets-are-tested). Common content: formulas, lookups, pivots, charts, data cleaning.

## Gaps found
Existing lessons covered references, tables, cleaning, IF/COUNTIFS, lookups, pivots, conditional formatting, a Power Query intro and test advice. Missing: named ranges and structured references, error handling, date maths on real timestamps, dynamic arrays, chart choice, deeper pivot features, protection, printing and sharing, Power Query merge/append/unpivot, what-if, and a timed drill. The module had no labs, resources or practice data use.

## Changes
- Fact check: no factual errors found in the 18 existing lessons.
- Added 14 lessons in units 7 to 11 (18 to 32), ending with the 26-task timed drill. "In the interview" stays last.
- Dynamic arrays and Power Query are marked as newly learned.
- 12 resources, 7 labs with figures computed in Python from the CSVs (for example 828 of 1019 shifts completed, 81.3%; How do I tickets 37.75 a month before May and 10.8 after; emergency hours to fill 1.70 before June and 0.64 after).
- Interview questions raised from 6 to 16, worded as moderate Excel.

## Could not verify
- No Excel was run: formulas and expected values were checked by Python, not in the application, and menu paths may differ by version.
- The MO-200 skill bullets were not read; only the area weightings.
- Indeed and eSkill test content was not found; the assessment profile rests on TestGorilla, other vendor pages and Exponent.
- Leila Gharani, Kevin Stratvert and ExcelIsFun course contents were not opened; resource descriptions are general.
- The practice data is fictional, so the 71% fall in How do I tickets is not the learner's real 35% inflow result.
