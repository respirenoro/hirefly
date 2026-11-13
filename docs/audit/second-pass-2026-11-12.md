# Second audit pass, 2026-11-12

The first audit compared each module with public resources from search-result snippets. This
pass opened and read the pages: vendor documentation, exam outlines (MO-200 and MO-210, PL-300,
ISTQB CTFL v4.0.1, ACP-620, the Scrum Guide), about 50 interview-question pages for the bank
and 3 to 6 per skill. Pages that would not open are named below.

## Corrected

- SQL: one Microsoft Learn path renamed; a module's length (141 minutes, not 60); Mode links
  now on thoughtspot.com; the freeCodeCamp course uses MySQL.
- Excel: DATEDIF is documented and Microsoft warns against it for days; the exam resource
  pointed at the Office 2019 exam (now MO-210); two Power Query resources had the wrong title;
  one "core" resource was a landing page.
- Power BI: licensing wording (free users can view content in an F64 or larger capacity); the
  Service calls the RLS check "Test as role"; roles are additive; the practice assessment moved.
- Jira: Atlassian's rename of issue to work item and project to space; `linkedIssues()` is now
  documented as `linkedWorkItems()`; quoted relative dates; `startOfWeek()` starts on Sunday;
  boards have a built-in standup.
- Azure DevOps: the free Microsoft-hosted pipeline grant now needs the organization linked to
  an Azure subscription (lab 6 said no payment details would be asked); Analytics views cover
  work items only.
- Test Plans: the Firefox Test & Feedback extension retires on 2026-11-30; automated tests can
  be associated from the web portal for all listed frameworks; progress report caveats.
- Playwright: a 1.65 change that breaks page objects with locators in field initializers.
- Tickets and documentation: incident role names attributed to Atlassian were not Atlassian's;
  a 15-minute notice target presented as a source's rule; a wrong claim about the order of
  Google's Technical Writing One; plainlanguage.gov now redirects.

## Added

- 20 lessons in 8 new units: SQL database concepts (keys, EXISTS, views, indexes, normal
  forms); Excel everyday workbook skills and version boundaries; Power BI row context,
  iterators, the DAX functions lists ask about, storage modes and Fabric; Azure DevOps pipeline
  vocabulary; ISTQB vocabulary, the pyramid and estimation; Playwright tags and awkward pages;
  Scrum by the Guide, prioritisation (MoSCoW, RICE), RAID, RACI and status reports; business
  analysis basics (elicitation, requirement kinds, process maps).
- 80 module interview questions with model answers, for questions that recur in public lists
  and had no equivalent.
- 52 bank questions (546 to 598): healthcare front desk and payer work, support fundamentals
  (DNS, DHCP, VPN, identity checks), QA terminology, AI judgement, basic statistics, and more
  difficulty-3 questions. Seven frequency ratings corrected.

## Still open

- Nothing was run in SQL Server, Excel, Power BI Desktop, a live Jira site or Azure DevOps.
  Figures were computed from the practice data in SQLite and Python.
- Not opened: LeetCode (403), Khan Academy's course page, Exponent (now aced.io), The Muse,
  Glassdoor, Teal, Harvard and Google re:Work pages, the AXELOS and ISO 29119-3 texts, and the
  YouTube channel pages (only the page frame loaded).
- Unconfirmed on a live site: whether unquoted Jira relative dates are accepted; associating a
  Playwright result with a test case.
- The bank's older entries still have many two-or-three-word pitfalls and follow-ups, and 40%
  of entries are rated "asked in most interviews". Near-duplicate clusters (weakness, critical
  bug before release) were not merged.
- The research recommended three whole modules (business analysis, agile product ownership,
  project delivery). This pass added their core as two units in the ticket-process module.
- The in-app New skill builder has been tested against a stand-in for the assistant, not a
  real API call.
