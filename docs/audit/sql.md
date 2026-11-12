# SQL module audit

## Benchmarks (found by search this session)

- Microsoft Learn: [Get Started Querying with Transact-SQL](https://learn.microsoft.com/en-us/training/paths/get-started-querying-with-transact-sql), [Write advanced Transact-SQL queries](https://learn.microsoft.com/en-us/training/paths/write-advanced-transact-sql-queries), [Write advanced T-SQL code](https://learn.microsoft.com/en-us/training/modules/write-advanced-sql-code) (CTEs, window functions).
- [SQLBolt](https://sqlbolt.com/): SELECT, joins, aggregates, then INSERT/UPDATE/DELETE.
- [Mode SQL tutorial](https://mode.com/sql-tutorial/intro-to-intermediate-sql): CASE, DISTINCT, joins, unions, self joins; separate window-function lesson.
- [Khan Academy intro](https://blog.khanacademy.org/new-course-learn-sql-interactively-on-khan-academy/) and [freeCodeCamp](https://www.freecodecamp.org/news/learn-sql-full-course/): querying, aggregating, modifying data.
- [DataLemur patterns](https://datalemur.com/blog/sql-interview-patterns), [LeetCode SQL 50](https://leetcode.com/studyplan/top-sql-50/), [StrataScratch](https://stratascratch.com/): joins, ranking, top-N, running totals, LAG, duplicates.
- Analyst assessment guides: joins, aggregation, HAVING, CTEs, ranking, rolling metrics, date bucketing, NULLs, deduplication, join-explosion checks.

## Gaps found

UNION/INTERSECT/EXCEPT, self, cross and full joins, string functions, NULLIF, RANK/DENSE_RANK/NTILE, LAG/LEAD, moving averages, percent of total, date bucketing and zero-filled calendars, execution order, INSERT/UPDATE/DELETE and transactions, classic puzzles (second highest, duplicates, gaps, pivot), a graded problem set, and runnable checks.

## Changed

- Four new units (7 to 10, 14 lessons) placed before "In the interview", which stays last. The problem set has 16 graded problems.
- No factual errors found in the 17 existing lessons. Every stated sample result was reproduced in SQLite. Small additions: LIMIT/OFFSET FETCH, DATETRUNC, links to the new units, schema columns now match the practice data.
- 49 open exercises carry a verified `sqlite` field. Prompts that depended on the 8-row sample were rewritten (for example Austin became Atlanta, shift 108 became 1005, HAVING threshold 2 became 20). Two-query and spoken answers have none.
- `lesson_sample.sql` written. Interview questions raised from 7 to 17, 11 resources and 6 labs added.

Counts: lessons 17 to 31, exercises 68 to 139, open 17 to 54.

## Could not verify

- T-SQL answers (DATEDIFF, DATEFROMPARTS, TOP, MAXRECURSION, transactions) were not run; only their SQLite equivalents were.
- Resource `minutes` are estimates. Khan Academy and LeetCode course pages were seen in search text only; Khan is linked through its blog post.
- SQL Server Express and SSMS lab steps were not performed. `practice.sql` was run only in SQLite.
- Mode pages carry a ThoughtSpot banner, so they may move.
