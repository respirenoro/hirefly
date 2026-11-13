---
name: hirefly-module
description: "Build or extend a skill module for HireFly, the interview-prep desktop app: lessons, exercises, labs, rated outside courses and interview answers, researched against current documentation and written for this candidate's honest level. Use when the user says 'build a HireFly module for X', 'add X to HireFly', 'teach me X in HireFly', 'HireFly has no lessons on X', or 'audit the HireFly X module'."
user-invocable: true
---

# Build a HireFly skill module

Read two files in the HireFly repo before writing anything, and follow both:

- `assets/content/authoring.md`: the standard. What a module must cover and how to verify it.
- `docs/content-schema.md`: the file format.

Write to `%USERPROFILE%\Documents\HireFly\content\skills\<id>\` (a `module.json` and
`unit-N.json` files). HireFly reads that folder when it starts. Touch nothing else there
except `career\skills.json`.

## Steps

1. **The learner.** Read `Documents\HireFly\career\facts.md` for the skill's real level and
   what must never be claimed. If the skill is not in it, ask the user two questions: what
   their resume says about it, and what they have actually done with it.
2. **Research, with pages opened.** For the skill, open and read: the vendor's documentation
   for each feature you will teach; a current exam or certification outline; at least three
   public interview-question lists for the user's target roles; and candidates for outside
   courses and a free hands-on environment. Keep a table as you go: topic, where it is asked
   or tested, the page you read. A search snippet does not count as reading a page.
3. **Plan.** List the topics from step 2 and mark each as a lesson, an interview question, or
   both. Include the definitions interviewers ask by name, the comparison questions, and the
   small routine tasks practical tests use. Show the user the unit list and get a yes before
   writing.
4. **Write** units, lessons, exercises, labs, `resources` (each with `priority`, `useWhen`
   and `versus`), `pathway`, and `interviewQuestions` with model answers. Compute every
   number and run every query or formula you state.
5. **Record what you could not confirm** in the module's `unverified` list. HireFly shows it
   to the learner on the module page.
6. **Check.** Run `python tool/check_module.py "<module folder>" --links` from the HireFly
   repo and fix everything it reports.
7. **Register.** If `career\skills.json` exists, add the module id to its `modules` list.
8. **Report** to the user: units and lesson count, the sources you opened, the `unverified`
   list, and that HireFly must be restarted to show the module.

## Extending or auditing an existing module

Same steps, but start by reading the module's files and listing, for each public topic and
interview question, the lesson or question that covers it, or MISSING. Open every existing
`resources` link and correct titles, descriptions and ratings that have drifted. Add new
lessons as a new unit file listed before the final "In the interview" unit; never renumber or
reuse existing ids, because the learner's progress is stored against them.

## Rules that are easy to break

- Never write a web address from memory. A link you did not open this session is left out.
- Every model answer stays inside the learner's real level and uses only facts from their
  record.
- Do not mark a resource `core` unless you read it and the learner should not skip it.
- If a lab needs an account, a trial or payment details, say so in its setup and give the
  free route.
