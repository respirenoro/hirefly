# Audit: Azure DevOps Test Plans module

## Benchmarks
- [What is Azure Test Plans?](https://learn.microsoft.com/en-us/azure/devops/test/overview?view=azure-devops): hubs, suites, runner, reports, access table.
- [Permissions, licensing, and access](https://learn.microsoft.com/en-us/azure/devops/test/manual-test-permissions?view=azure-devops) and [Try Azure Test Plans for free](https://learn.microsoft.com/azure/devops/organizations/billing/try-additional-features-vs).
- [Create test plans](https://learn.microsoft.com/en-us/azure/devops/test/create-a-test-plan?view=azure-devops), [test cases](https://learn.microsoft.com/en-us/azure/devops/test/create-test-cases?view=azure-devops), [shared steps](https://learn.microsoft.com/en-us/azure/devops/test/share-steps-between-test-cases?view=azure-devops), [parameters](https://learn.microsoft.com/en-us/azure/devops/test/repeat-test-with-different-data?view=azure-devops), [run manual tests](https://learn.microsoft.com/en-us/azure/devops/test/run-manual-tests?view=azure-devops).
- [Test & Feedback](https://learn.microsoft.com/en-us/azure/devops/test/provide-stakeholder-feedback?view=azure-devops) and [exploratory insights](https://learn.microsoft.com/en-us/azure/devops/test/insights-exploratory-testing?view=azure-devops).
- [ISTQB CTFL v4.0](https://istqb.org/certifications/certified-tester-foundation-level-ctfl-v4-0/): techniques, test management, vocabulary.

## Gaps found
No access-level content at all, no strategy versus plan, only equivalence partitioning among techniques, no decision table, state transition, scenario or exploratory charter material, no graded case-writing practice, thin suite choice and configuration depth, no Test & Feedback, no risk-based regression, UAT access and sign-off, linking automated tests, metrics, or defect life cycle.

## Errors corrected
- Test Runner was described as browser or "desktop client"; now: browser Test Runner for web apps, a desktop-application option, and Run with options.
- Access: running tests needs Basic; creating plans, suites, configurations, parameters and preparing UAT needs Basic + Test Plans; Stakeholders only use the extension. Added in units 7, 11 and 12.
- Severity values verified (1 - Critical to 4 - Low).
- Test case states Design, Ready, Closed were correct.

## Changes
Added units 7 to 12 (22 lessons): strategy, plan and ISTQB vocabulary; six technique lessons with drills; 16 graded case-writing exercises on the scheduling product; suite choice, configurations and parameters, runner, Test & Feedback; risk and UAT; traceability, automated linking, metrics, defect life cycle, access. Lessons 12 to 34. Interview questions 7 to 20. 12 resources, 7 labs, with the Test Plans trial stated.

## Could not verify
- Exact tab names inside a plan (Define, Execute, chart view): described by function.
- Associating Playwright tests with test cases and the Azure Test Plan task: concepts only; the task page was not opened.
- Clone options for plans and suites, and Test & Feedback browser list (Firefox appears in one source only).
- The ISTQB syllabus PDF was not opened; terms come from search summaries.
- Trial price: not stated.
