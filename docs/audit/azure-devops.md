# Audit: Azure DevOps module

## Benchmarks
- [What is Azure DevOps? (Learn module)](https://learn.microsoft.com/en-us/training/modules/get-started-with-devops/): services, organization, project.
- [Choose an Agile approach (Learn module)](https://learn.microsoft.com/en-us/training/modules/choose-an-agile-approach/): Boards, work items, Basic process.
- [Default processes and process templates](https://learn.microsoft.com/en-us/azure/devops/boards/work-items/guidance/choose-process?view=azure-devops): types and states for Basic, Agile, Scrum, CMMI.
- [WIQL syntax](https://learn.microsoft.com/en-us/azure/devops/boards/queries/wiql-syntax?view=azure-devops), [dashboards](https://learn.microsoft.com/en-us/azure/devops/report/dashboards/add-widget-to-dashboard?view=azure-devops), [access levels](https://learn.microsoft.com/en-us/azure/devops/organizations/security/access-levels?view=azure-devops).
- [Key Pipelines concepts](https://learn.microsoft.com/en-us/azure/devops/pipelines/get-started/key-pipelines-concepts?view=azure-devops) and [PublishTestResults@2](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/publish-test-results-v2?view=azure-pipelines).
- [AZ-400 path](https://learn.microsoft.com/en-us/training/paths/az-400-get-started-devops-transformation-journey/): advanced; vocabulary only.

## Gaps found
No side-by-side process states, no field and link-type reference, no delivery plans, queries without a drill or direct-links queries, no Analytics views, notifications or wiki, no pull-request review lesson, YAML without variables, conditions or environments, nothing on publishing test results or artifacts, and nothing on access levels.

## Errors corrected
- Agile and Scrum state lists omitted Removed, and CMMI and Basic states were not given. Fixed in unit 1 and tabulated in unit 7.
- Severity values verified against the field reference: 1 - Critical, 2 - High, 3 - Medium, 4 - Low. The existing WIQL was already correct.
- Access levels were absent. Added unit 10: Stakeholder, Basic, Basic + Test Plans and the trial.

## Changes
Added units 7 to 10 (10 lessons): process comparison, fields and links, delivery plans, query types with a five-item drill, dashboards and Analytics views, notifications and wiki, pull-request review, YAML variables and environments, publishing results and artifacts, access. Lessons 13 to 23. Interview questions 7 to 15. 12 resources, 6 labs (free organization, Agile project, backlog with SOS, sprint, queries and dashboard, pull request, YAML pipeline that publishes results). "In the interview" remains last.

## Could not verify
- Wiki details, Analytics views availability, notification subscription permissions and delivery plan drag behavior: written from general knowledge, not a page opened this session.
- Pull request vote names and thread statuses: not opened.
- Free hosted pipeline parallelism for new organizations: lab 6 hedges; check at sign-up.
- Exact portal menu labels move; lessons describe functions.
- The Learn module "Get started with Azure DevOps" path name was not found; the closest module is cited.
