# Writing a HireFly skill module: the standard

This is the one set of rules for creating or extending a skill module, whoever writes it: a
Claude Code session with web access, or the assistant inside the app. The file format is in
`docs/content-schema.md`. These rules say what makes a module worth the learner's time. They
come from auditing HireFly's own modules against public courses, exam outlines and interview
question lists, and each rule exists because the audit found the opposite somewhere.

## 1. Start from evidence, not from memory

- Build the topic list from three kinds of source, and open each one: the vendor's own
  documentation, a current exam or certification outline for the skill, and at least three
  public lists of interview questions for the learner's target roles.
- A search-result snippet is not a source. If you did not open the page and read it, you may
  not cite it, and you may not rely on it.
- Product names, menu labels, licences, limits and syntax change. Confirm each against the
  vendor's page in this session. Where you cannot, describe what the feature does instead of
  where it is, and add the point to the module's list of things to check.
- If you have no web access, say so in the module, write no web links at all, and keep to
  stable concepts. List what a reader should check against current documentation.

## 2. Cover what interviews actually ask

- Interviews open with vocabulary and definitions before they test doing. Every module needs
  the terms a screen asks by name (for SQL: primary key, index, view, normalization) even when
  the learner's work never required the words.
- For each recurring public interview question, the module must have either an
  `interviewQuestions` entry or an exercise that answers it. A lesson that teaches a topic does
  not count on its own: people cannot produce a spoken answer they have never rehearsed.
- Include the comparison questions (this tool against its main alternatives, old feature
  against new) and the judgement questions (when would you choose which).
- Cover the small routine tasks that practical tests are built from, not only the impressive
  features.
- Add scenario questions set in the learner's own domain, and at least a few hard ones.

## 3. Teach so that it sticks

- Teach by one worked example per idea, in the learner's own domain, using the names in
  their record.
- Show the trap. Each lesson should contain at least one case where the obvious approach
  gives a wrong answer, with the reason (a NULL in a list, a tie in a top five, an average of
  averages).
- State the rule for choosing: when to use this and when to use the alternative.
- Every number, query result and formula result in a lesson or answer must be one you
  computed or ran. Never estimate a result. If the practice data cannot be run, use a small
  example whose answer can be checked by hand, and check it.
- Placement questions test the core idea of the lesson, because a correct answer lets the
  learner skip it.
- Wrong choices in a multiple-choice question are mistakes people really make, not filler.
- Give version boundaries where a feature is not universal ("Excel 2021 and later").

## 4. Keep the learner honest

- Read the learner's record first. It lists each skill, the real level, and what must never
  be claimed.
- Lessons may teach beyond the real level. Every `interviewAngle` and every `strongAnswer`
  must stay inside it, and should model the honest sentence: what I did, what I have studied,
  what I have not done.
- Never write an answer that invents an employer, a number, a title, a certification or an
  outcome. Use only facts from the record.
- Model answers are written to be spoken: first person, plain words, 60 to 120 words.

## 5. Outside resources

- Open every link in this session. Record what the page is called now, not what it used to
  be called, and what it really contains.
- State how long it takes only if the page says so.
- Rate each one honestly against the module: `core` only if the learner should not skip it.
  A landing page, a channel home page or a sales page is never `core`.
- Say when to use it and how it compares with the module's own lessons.
- Prefer the vendor's free training, a free hands-on sandbox, and one source of unseen
  practice problems.
- A link you could not open is left out. Never write a web address from memory.

## 6. Labs

- A lab is done in the real tool, has numbered steps, and ends with a result the learner can
  see and check against stated values.
- State any cost, sign-up or payment detail the lab will ask for, and give the free route
  where one exists. Vendors change free tiers; check on the day.
- End with a `talkTrack`: the honest sentence the learner can say about having done it.

## 7. Before you hand it over

- Every file parses as strict JSON. Ids are unique across the whole app.
- Each lesson has 3 to 5 exercises, at least one multiple-choice and one open, and exactly one
  placement question that is multiple-choice or short-answer.
- 4 to 6 units of 2 to 4 lessons; the last unit is "In the interview".
- 8 or more `interviewQuestions`, each with a model answer.
- Run `python tool/check_module.py <module folder>`; it checks the points above. Add
  `--links` to test that every resource link answers.
- Write down, in the module's `unverified` list, everything you could not confirm: syntax
  not run on the real product, menu names, prices, anything from memory. An honest list is
  part of the deliverable. An empty one must be true.
- Re-audit a module when the vendor renames or re-licenses the product, and at least once a
  year. Links and names drift even when the ideas do not.
