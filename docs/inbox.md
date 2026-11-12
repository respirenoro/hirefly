# The inbox: driving HireFly from another tool

While HireFly is open it checks `Documents\HireFly\inbox` every few seconds. Each `.json` file is
handled and moved to `inbox\done`, or to `inbox\failed` with a `.error.txt` saying why. Write a
file as `name.json.tmp`, then rename it to `.json`.

A Claude session can do everything the in-app assistant does except the live mock interview and
the lesson tutor, so no API key is needed. It does this with two requests.

## 1. Create a role

Only `role` is required. Text can be given directly or as a path (`postingFile`, `resumeFile`,
`targetResumeFile`, `researchFile`; `.html` is read as its text).

```json
{
  "role": "QA Analyst", "company": "Acme Health",
  "posting": "full text", "url": "https://... (downloaded when posting is empty)",
  "resumeFile": "C:\\path\\resume.html", "targetResumeFile": "C:\\path\\target.html", "useTarget": false,
  "researchFile": "C:\\path\\research.md", "interviewer": "name, title, notes",
  "interviewDate": "2026-11-20", "intensity": 3,
  "brief": {
    "summary": "What the job is day to day, and the one-line case for the candidate.",
    "whatTheyWant": ["what the posting screens for, most important first"],
    "yourEdge": [{"point": "...", "evidence": "the exact fact from the candidate's record"}],
    "gaps": [{"gap": "...", "howToAnswer": "the honest answer"}],
    "whyThisCompany": "an honest first draft",
    "questionsToAsk": ["..."]
  },
  "tailored": [
    {"prompt": "A question specific to this posting or resume", "category": "role",
     "competency": "quality", "intent": "what the interviewer is checking",
     "guide": ["3 to 5 points of a strong answer"], "followUps": ["..."]}
  ]
}
```

`intensity` is 1 (about 10 questions) to 5 (about 46). `category` is one of background,
motivation, self, behavioral, situational, role, curveball, closing. Leave out `brief` and
`tailored` and HireFly writes them itself when it has an API key.

HireFly answers in `Documents\HireFly\outbox`:

- `<company>-<role>.md`: the plan, the skills the posting calls for, a study plan for the days left.
- `<company>-<role>.json`: every question with its `id`, `intent`, `guide` and the learner's
  current `answer`. Rewritten whenever an answer changes.

## 2. Coach the answers

Read the role's `.json`, judge each answer that has text, and send:

```json
{"type": "coach", "results": [
  {"id": "<item id>", "eval": {
    "score": 7.5, "verdict": "Two sentences: what an interviewer would think.",
    "strengths": ["..."], "fixes": ["most important first"],
    "missing": ["true details only the candidate can supply, as questions"],
    "overclaims": ["anything past the candidate's record, with the honest wording"],
    "improved": "The answer rewritten, in their voice, from their facts only.",
    "followUp": "The next question a sharp interviewer would ask."}}
]}
```

The result appears under that answer on the Prepare tab. Scores are 0 to 10: 5 is forgettable,
7 would pass, 8.5 is strong.

## Rules for whoever writes these

Use only facts from the candidate's own record. Never invent an employer, number or outcome;
where a detail is missing, ask for it in `missing`. Write `improved` the way the candidate speaks.
