# Setting up HireFly (instructions for Claude)

Follow these steps in order when a user asks you to install or set up HireFly. Ask each
question with your question tool, one step at a time. Keep your own messages short.

HireFly reads the user's data from `Documents\HireFly`. Nothing personal goes in this repo.

## 0. Install

Download `HireFly-windows.zip` from this repo's latest release
(`gh release download --repo <this repo> --pattern "HireFly-windows.zip"`), unzip it where the
user chooses, and tell them to run `project_hirefly.exe`. Windows only.

## 1. Their resumes

Ask: **"Which folder holds your target-state resumes?"** (the versions showing the skills you
want to have by your start date). Also ask for their current resume if it is elsewhere.

Read every resume there, then write to `Documents\HireFly\career\`:

- `facts.md`: work history, education, a table of each skill with their honest level and what
  they must never claim, and how they talk. Facts only; ask instead of guessing.
- `dossier.md`: what their last role was, why it mattered to the business, what made them hard
  to replace, and how to present it for each kind of role they want.
- `stories.json`: one STAR story per responsibility, in the shape of
  `integration_test/fixture.dart`. Put what you do not know in each story's `open` list as
  questions. Never invent a detail.
- `skills.json`: `{"modules": [...]}` listing the bundled modules that match skills on those
  resumes, most important first. Bundled ids: `sql`, `excel`, `power-bi`, `jira`,
  `azure-devops`, `ado-test-plans`, `playwright`, `ticket-process`, `documentation`.

Tell them which resume skills have no module yet.

## 2. Research (an Opus session, medium effort)

Ask: **"Shall I start a research session to build lessons for the missing skills and questions
for your target roles?"** If yes, start a subagent or session on Opus at medium effort with:

- the skills without a module, and the target roles from the resumes;
- `assets/content/authoring.md` as the standard to follow and `docs/content-schema.md` as the
  format. The steps are in `integrations/claude-skill/hirefly-module/SKILL.md`;
- output to `Documents\HireFly\content\skills\<id>\` (a `module.json` and unit files, with
  `resources`, `labs`, `pathway` and an `unverified` list) and
  `Documents\HireFly\content\questions\<name>.json`;
- the rules that pages are opened and read, never taken from search snippets, that every
  resource link is one it opened in this session, and that it runs
  `python tool/check_module.py <module folder> --links` on each module before finishing.

Add each new module id to `skills.json`. HireFly reads these folders when it starts.

## 3. Sending jobs through Claude (no API key needed)

Copy `integrations/claude-skill/hirefly-role` and `integrations/claude-skill/hirefly-module` into
the `.claude/skills/` folder of the project where the user runs their job search. Ask which project. Then tell them:

> With HireFly open, say "send the <company> <role> job to HireFly" in that project. Claude
> writes the role brief and tailored questions and HireFly builds the plan. Later, say "coach
> my HireFly answers". For a skill the app does not teach yet, say "build a HireFly module
> for <skill>". Formats are in `docs/inbox.md`.

## 4. Optional

Ask which of these they want, and do only those:

- **Claude API key** (Settings): turns on the in-app coach, live mock interviewer, lesson
  tutor and New skill, which writes a module inside the app (without web research). Without it, coaching comes through step 3 and mocks run in a Claude conversation.
- **Speaking answers** (Settings, Voice): a one-time 661 MB speech model download. Runs on
  their PC; no audio is kept.
- **An interview date**: set it on the role; Today then paces the work.

Finish by telling them to restart HireFly, open "Your stories", and answer the open questions.
