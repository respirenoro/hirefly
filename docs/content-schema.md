# HireFly content schema

Bundled content lives in `assets/content/` as JSON. The app reads it at start; the learner's
progress lives in the database, never in these files. Every file must be strict JSON (UTF-8, no
comments, no trailing commas). Ids are lowercase kebab-case and unique across the whole app.

## Who the content is for

One learner, an entry-level candidate. Write to them as "you". Never put a name or contact
details in content. Their real record is in `Documents\HireFly\career\facts.md`; read it before
writing, and never coach them to claim more than it supports. Where a lesson teaches beyond
their level, say so in `interviewAngle` and give honest wording such as "I have been building
this skill on my own".

The bundled modules use one running example: scheduling and dispatch software that assigns
contracted pharmacists to pharmacies with staffing shortages, with a practice dataset to match.
New modules may use it or the learner's own domain.

## Skill modules: `assets/content/skills/<module-id>/`

`module.json`:

```json
{
  "id": "sql",
  "title": "SQL",
  "tagline": "One line on what this module gets you to.",
  "claim": "What the resume says about this skill, and what you must be able to do to back it.",
  "units": ["unit-1.json", "unit-2.json"],
  "interviewQuestions": [
    {"id": "sql-iq-1", "prompt": "A question an interviewer asks about this skill.",
     "strongAnswer": "A model spoken answer, 60-120 words, first person, built on the real work above."}
  ]
}
```

Each `unit-N.json`:

```json
{
  "id": "sql-u1",
  "title": "Unit title",
  "summary": "One or two sentences.",
  "lessons": [
    {
      "id": "sql-u1-l1",
      "title": "Lesson title",
      "minutes": 8,
      "body": "Markdown. 250-500 words. Teach by worked example. Fenced code blocks with a language tag. Tables allowed. No images, no HTML.",
      "keyPoints": ["3 to 5 short takeaways"],
      "interviewAngle": "Markdown, 40-100 words: how this comes up in an interview and how to talk about it honestly from the real work.",
      "exercises": [
        {"id": "sql-u1-l1-e1", "type": "mcq", "placement": true, "prompt": "Markdown.",
         "choices": ["A", "B", "C", "D"], "answer": 2, "explanation": "Why, in one to three sentences."},
        {"id": "sql-u1-l1-e2", "type": "short", "prompt": "A question with a one-word or one-line answer.",
         "accept": ["count(*)", "count(1)"], "answer": "COUNT(*)", "explanation": "..."},
        {"id": "sql-u1-l1-e3", "type": "open", "prompt": "Write a query / explain / draft a ticket ...",
         "answer": "A full model answer (markdown, code fenced).",
         "rubric": ["3 to 5 things a correct answer must contain"]}
      ]
    }
  ]
}
```

Rules:

- `mcq.answer` is the zero-based index of the correct choice. Vary its position. 3 or 4 choices,
  with wrong choices that are common real mistakes.
- `short.accept` is a list of accepted answers. The app compares after lowercasing and collapsing
  whitespace, so list realistic variants. Use `short` only when the answer is short and unambiguous.
- `open` is graded by a rubric (by the AI coach, or self-graded against the model answer).
- Each lesson has 3 to 5 exercises: at least one `mcq`, at least one `open`. Exactly one exercise per
  lesson has `"placement": true` (an `mcq` or `short`) and it must test the lesson's core idea,
  because a learner who gets a unit's placement questions right skips that unit.
- Order units from fundamentals to job-realistic work. 4 to 6 units per module, 2 to 4 lessons each.
  The last unit is always "In the interview": talking about the skill, common questions, and what
  a practical test or take-home looks like for these roles.
- Use the scheduling domain for examples where natural: tables like `shifts(id, pharmacy_id,
  pharmacist_id, requested_at, filled_at, starts_at, status, cancel_reason)`, `pharmacies`,
  `pharmacists`, `assignments`; tickets about dispatch, notifications, schedules.
- Be accurate. If unsure a feature or menu name is current, describe what it does rather than
  where it is. Plain direct prose; no filler, no hype.
- 8 or more `interviewQuestions` per module: one for every question that recurs in public
  interview lists for the skill, including the definition and comparison questions.
- `unverified` (optional, in `module.json`): a list of what the author could not confirm, such
  as syntax not run on the real product or a price. The app shows it on the module page under
  "Check before you rely on it".

What a module must cover, and how each part is verified, is in `assets/content/authoring.md`.
That file is the standard for every author: a Claude Code session (the `hirefly-module` skill
in `integrations/claude-skill/`) and the assistant inside the app (New skill) are both given
it. Check a module folder with `python tool/check_module.py <folder> [--links] [--bundled]`.

## Question bank: `assets/content/questions/<category>.json`

Each file is a JSON array of:

```json
{
  "id": "beh-conflict-01",
  "category": "behavioral",
  "competency": "conflict",
  "prompt": "Tell me about a time you disagreed with a teammate.",
  "variants": ["Describe a conflict at work and how you handled it."],
  "intent": "What the interviewer is checking, in one or two sentences.",
  "framework": "STAR",
  "answerGuide": ["3 to 5 bullets on what a strong answer contains"],
  "pitfalls": ["1 to 3 common mistakes"],
  "followUps": ["2 to 4 follow-up questions an interviewer would ask next"],
  "roles": ["any"],
  "frequency": 3,
  "difficulty": 2
}
```

- `category` (also the file name): `behavioral`, `situational`, `motivation`, `self`, `background`,
  `role`, `curveball`, `closing`.
  - `behavioral`: "tell me about a time..."; `situational`: "what would you do if / when you
    encounter..."; `motivation`: why this role, why this company, why leaving, goals; `self`:
    strengths, weaknesses, work style, feedback; `background`: walk me through your resume, gaps,
    degree mismatch, short tenure, salary, remote readiness; `role`: role-specific knowledge and
    process questions; `curveball`: odd, off-topic or pressure questions; `closing`: questions to
    ask them, anything else, final pitch.
- `competency`, one of: `conflict`, `prioritization`, `failure`, `initiative`, `ownership`,
  `communication`, `stakeholders`, `customer-focus`, `problem-solving`, `attention-to-detail`,
  `learning`, `adaptability`, `teamwork`, `leadership`, `pressure`, `ambiguity`, `process-improvement`,
  `quality`, `data`, `ethics`, `feedback`, `time-management`, `remote-work`, `motivation`,
  `self-awareness`, `career-story`, `company-fit`, `compensation`, `technical-knowledge`, `closing`.
- `framework`: `STAR`, `PAR`, `Present-Past-Future`, `Claim-Evidence-Tie`, `Weakness-Action-Progress`,
  `Structure-Then-Answer`, or `Direct`.
- `roles`: `any`, or any of `qa`, `ba`, `po`, `pm`, `support`, `implementation`, `ops`, `data`,
  `cs`, `healthcare`.
- `frequency` 1-3 (3 = asked in most interviews). `difficulty` 1-3.

## Additions (audit round, 2026-11-11)

### Practice data: `assets/content/datasets/`

Fictional data the learner can open in the real tools. `practice.sql` creates and fills every
table and runs unchanged in SQLite and SQL Server. The same tables are there as CSV files.
In the app the learner exports this folder with one click, and the SQL sandbox runs against it.

```text
pharmacies(id, name, city, state)                                   40 rows
pharmacists(id, name, license_state, active)                        60 rows
shifts(id, pharmacy_id, pharmacist_id, requested_at, filled_at, starts_at,
       status, cancel_reason, is_emergency)                       1019 rows
assignments(id, shift_id, pharmacist_id, status, completed_at)     906 rows
tickets(id, opened_at, closed_at, pharmacy_id, category, severity, status, title)  734 rows
```

`shifts.status` is `completed`, `cancelled` or `open`. `cancel_reason` is `no coverage`,
`pharmacy cancelled` or `pharmacist cancelled`. Datetimes are text `YYYY-MM-DD HH:MM:SS`,
January to early October 2026. `tickets.category` is `How do I`, `Bug`, `Access`,
`Feature request` or `Data fix`; severity is `low`, `medium`, `high` or `critical`.
Built-in trends worth finding: "How do I" tickets fall sharply from May (a documentation
rewrite); emergency shifts (`is_emergency = 1`) fill much faster from June (an alert feature).

### `module.json` gains `resources` and `labs`

```json
"resources": [
  {"title": "Exact title of the course, doc page or video", "url": "https://...",
   "source": "Microsoft Learn", "kind": "course", "minutes": 240, "free": true,
   "why": "One sentence: what it gives the learner that this module does not, or which unit it deepens.",
   "units": ["sql-u3"]}
],
"labs": [
  {"id": "sql-lab-1", "title": "Short imperative title", "minutes": 30,
   "goal": "What the learner will have built or proved by the end.",
   "setup": "Markdown: exactly what to install or sign up for (free tiers only) and how to load the practice data.",
   "steps": ["Markdown step, one action each, 5 to 12 steps"],
   "check": ["2 to 5 observable results that prove it worked, with the expected figure where there is one"],
   "talkTrack": "One or two sentences the learner can now say truthfully in an interview."}
]
```

- `kind`: `course`, `docs`, `video`, `practice`, `reference` or `certification`.
- Every `url` must be one you opened or found in search results this session, on the vendor's
  own site or another well-known source. Never write a URL from memory. Prefer stable
  landing pages (a Microsoft Learn path, the Playwright docs intro, an Atlassian University
  course page) over deep links that move.
- Labs are done in the real tool, on a free tier, with the practice data. They are what a
  video walkthrough gives that reading does not, so each must end in something visible.

### Exercises may carry a runnable check (SQL only)

An `open` exercise whose answer is a query can add `"sqlite": "SELECT ..."`: a correct solution
in SQLite syntax against the practice data above. The app runs the learner's query and this
one and compares the rows, so it must return exactly the columns the prompt asks for, in the
order asked. Add `"ordered": true` when row order is part of the question. Lessons may keep
teaching T-SQL; say in the prompt when the sandbox needs a different function (SQLite has
`julianday()` and `strftime()` instead of `DATEDIFF` and `DATEPART`, and `LIMIT` instead of `TOP`).

### Audit reports: `docs/audit/<name>.md`

Each audit writes a short report: what it compared against (with links), the gaps found,
what it changed, and what it could not verify.

### Course advice (2026-11-12)

Each entry in `resources` gains three fields, and `module.json` gains `pathway`. Together they
let the app say which outside course to use, when, and when HireFly's own lessons are the better
use of the time. The advice must be honest in both directions.

```json
{"title": "...", "url": "...",
 "priority": "core",
 "useWhen": "One sentence naming the moment to open it: after which unit or lab, or in which situation.",
 "versus": "One sentence: what this does better than HireFly's lessons, and what HireFly does better for an interview."}
```

- `priority`: `core` (do it; HireFly cannot replace it), `worthwhile` (do it if you have a week
  or more), `optional` (reference, or only for a certificate or a deep dive).

```json
"pathway": {
  "summary": "Two or three sentences: how far HireFly alone gets you in this skill, and what it cannot give you.",
  "hireflyBetter": ["3 to 5 concrete cases where HireFly is the better choice"],
  "externalBetter": ["3 to 5 concrete cases where an outside course or the real tool is the better choice"],
  "plans": [
    {"when": "Interview in three days or less", "hours": 4, "steps": ["Ordered steps. Name HireFly units, labs and outside resources by their exact titles."]},
    {"when": "About two weeks", "hours": 15, "steps": ["..."]},
    {"when": "A month or more, or you have the job", "hours": 40, "steps": ["..."]}
  ]
}
```

What HireFly is: text lessons with worked examples in the learner's own domain, graded
exercises, a test-out per unit, an AI tutor, interview talk tracks with honest wording,
hands-on labs on free tiers with a practice dataset, and (SQL only) a sandbox that runs and
checks queries. What it is not: video, a hosted copy of the tool, a certificate, a community,
or a course kept current by the vendor.
