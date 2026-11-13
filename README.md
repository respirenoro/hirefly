# HireFly

Interview preparation and skills training for one candidate. Windows desktop; your data stays
on your PC.

## Install

Ask Claude Code: **"Set up HireFly from this repo."** It follows `SETUP.md`: installs the app,
builds your profile from your resumes, researches lessons for your skills, and shows you how to
send jobs to the app.

Or by hand: download `HireFly-windows.zip` from Releases, unzip, run `project_hirefly.exe`.

## What it does

- **Roles.** Give it a posting and the resume you sent. It plans the questions, lists the skills
  the job calls for, and takes you through Prepare, Practice (typed or spoken, timed) and a
  mock interview.
- **Your stories.** Builds, checks and rehearses the stories your answers come from.
- **Skills.** Nine modules (SQL, Excel, Power BI, Jira, Azure DevOps, Test Plans, Playwright,
  the ticket process, documentation): 285 lessons, 58 labs in the real tools, a SQL sandbox,
  and advice on which outside courses to use and when.
- **New skills.** For a skill it does not cover, Claude Code researches and writes a module to
  one standard (`assets/content/authoring.md`), or the app writes one itself with an API key.
- **Works without an API key.** A Claude Code session can send jobs and coach answers through
  a folder the app watches (`docs/inbox.md`). A Claude API key adds in-app coaching.

## Where things are

| | |
|---|---|
| Question bank (598) | `assets/content/questions/` |
| Skill modules | `assets/content/skills/` |
| Every prompt the app sends | `lib/ai/prompts.dart`, listed in `docs/prompts.md` |
| Content format | `docs/content-schema.md` |
| What the content was checked against | `docs/audit/` |
| Your profile, stories, extra lessons | `Documents\HireFly\` (not in this repo) |

Lesson examples use a fictional pharmacy-staffing product and its practice dataset.

Interface kit, API client and speech engine adapted from Project Soloza. FSRS maths adapted
from py-fsrs (MIT). Fonts under the SIL Open Font License.
