# Audit: Ticket process module

## Benchmarks (searched 2026-11-11)

- ITIL 4 practices (incident, problem, change enablement, service request): AXELOS reader's manual https://www.axelos.com/resource-hub/practice/readers-manual-itil-4-practice-guide and Atlassian's ITSM guide https://www.atlassian.com/collections/service/guides/it-service-management
- Atlassian Incident Management Handbook: https://www.atlassian.com/incident-management/handbook/incident-response, severity levels https://www.atlassian.com/incident-management/kpis/severity-levels, templates https://wac-cdn.atlassian.com/incident-management/incident-communication/templates
- 5 whys and blameless postmortems: https://www.atlassian.com/incident-management/postmortem/5-whys
- KCS v6: https://library.serviceinnovation.org/KCS/KCS_v6/KCS_v6_Practices_Guide
- ISTQB CTFL v4.0.1 syllabus: https://www.istqb.org/wp-content/uploads/2024/11/ISTQB_CTFL_Syllabus_v4.0.1.pdf
- Zendesk metrics: https://www.zendesk.com/resources/customer-service-reports/
- JSM SLAs: https://support.atlassian.com/jira-service-management-cloud/docs/what-are-slas-and-how-do-i-view-them-in-my-service-project/

HubSpot: only third-party summaries came up, no official page, so HubSpot is not cited.

## Gaps found

The existing 15 lessons covered the lifecycle, triage, bug reports, stories, SLAs and metrics. Missing: ITIL record types, the defect life cycle, major incident handling and communication, root cause analysis, KCS, escalation and handoffs, deeper metrics (reopen, backlog age, deflection, CSAT), customer message templates, and a graded practice bank. Interview questions: 6, needed 15.

## Changes

- No factual errors found in existing lessons. The severity scale (Critical/Major/Moderate/Minor) differs from the CSV's low/medium/high/critical, so the new triage lesson maps them.
- Added 15 lessons in units 7 to 12: record types, defect life cycle, major incidents, communication templates, 5 whys, KCS, escalation, metrics, five message situations, 12 rewrite exercises, 6 triage sets of five tickets (30 tickets).
- Added 12 resources, 5 labs and 10 interview questions (16 total). Metrics in lessons and labs were computed from tickets.csv (734 rows; top title 50 times; How do I 151 for Jan to Apr versus 54 for May to Sep; mean hours to close by severity 2.4, 7.5, 20.6, 37.9).
- The module now has 12 units, above the schema's 4 to 6, as requested.

## Could not verify

- Pages were seen as search summaries, not opened. Wording of Atlassian severity and ITIL definitions is paraphrased from summaries.
- ISTQB defect report fields were not read from the syllabus; the summary points to ISO/IEC/IEEE 29119-3, which was not opened.
- Zendesk and KCS details come from search summaries. The sample status names and SLA numbers are teaching examples, not vendor defaults.
- Model answers in the rewrite and triage banks are judgement calls, not an official key.
