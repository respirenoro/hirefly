# Audit: Jira module

## Benchmarks (searched 2026-11-11)

- Atlassian University free Jira Fundamentals path and badge: https://www.atlassian.com/university (about 90 minutes, final assessment; path name has changed over time)
- Learn scrum with Jira: https://www.atlassian.com/agile/tutorials/how-to-do-scrum-with-jira
- Backlog refinement: https://www.atlassian.com/agile/scrum/backlog-refinement
- JQL functions and fields: https://support.atlassian.com/jira-software-cloud/docs/advanced-search-reference-jql-functions/ and .../advanced-search-reference-jql-fields/
- Velocity, cumulative flow, automation, JSM and Confluence docs (linked in module.json)
- ACP-620 exam topics PDF (April 2021 version): https://www.atlassian.com/dam/jcr:90960354-c158-4a0e-b31a-71f53b207669/ACP-620%20Managing%20Jira%20Projects%20for%20Cloud%20Exam%20Topics%20V2.pdf
- Most-watched free tutorials: Simon Sez IT beginner series and Intellipaat full course (titles only, not watched).

They cover the issue model, boards, backlog and sprints, JQL, reports, automation, project configuration, and JSM.

## Gaps found

Board configuration, refinement and ceremonies in the tool, velocity and capacity, epics and timeline, reports beyond burndown, automation, permissions and schemes, Confluence linkage, a JQL drill, and JSM queues, SLAs and knowledge base. Interview questions: 6, needed 15.

## Changes

- Fixed: the `issueFunction` JQL example (marketplace app) replaced with core `linkedIssues()`; the app note kept as a warning. Azure DevOps component mapping now says area paths are a hierarchy and a loose match; the interview answer was updated to match.
- Added 14 lessons in units 7, 8, 9 (20 graded JQL queries), 10 and 11. Lessons went from 14 to 28.
- Added 12 resources, 6 labs (Scrum project, run a sprint, triage board, five filters, dashboard, automation and reports) and 10 interview questions (16 total).
- "In the interview" is still last. The module now has 11 units, above the schema's 4 to 6.

## Could not verify

- Atlassian pages were seen only as search summaries, not opened. JQL syntax (`linkedIssues()`, `unreleasedVersions()`, `CHANGED ... AFTER`, escaped phrase search, `parent =`) is from search results and memory; none was run on a live Jira site.
- The field name "Story point estimate" and menu names vary by site and plan; timeline availability depends on plan.
- ACP-620 question counts and prices conflict across sources, so none are stated.
- Videos were not watched.
- Lab check figures come from the lab text, not a run.
