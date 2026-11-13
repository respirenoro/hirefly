# Prompts and questions

Everything the app asks a model is in `lib/ai/prompts.dart`. Each prompt is sent after one
shared, cached block: the coach's rules, the candidate's facts, dossier and stories, and (for a
role) the posting, resume, research and interviewer notes.

| Prompt | Used for | Reply |
|---|---|---|
| `briefInstructions` | Role brief and tailored questions | `briefSchema` |
| `draftInstructions` | A first answer from the candidate's history | `draftSchema` |
| `coachInstructions` | Scoring and rewriting an answer | `coachSchema` |
| `interviewerInstructions` | One turn of the mock interviewer | `interviewerSchema` |
| `debriefInstructions` | The debrief after a mock | `debriefSchema` |
| `storyInterviewInstructions` | Interviewing the candidate to build a story | text |
| `storyWriteInstructions` | Writing the story up from their answers | `storyWriteSchema` |
| `storyCheckInstructions` | Judging a story | `storyCheckSchema` |
| `gradeInstructions` | Grading a lesson exercise | `gradeSchema` |
| `tutorContext`, `lessonForTutor` | The lesson tutor | text |
| `moduleOutlineInstructions` | New skill: the plan for a module | `moduleOutlineSchema` |
| `moduleUnitInstructions` | New skill: the lessons of one unit | `moduleUnitSchema` |
| `moduleAnswersInstructions` | New skill: model answers to the interview questions | `moduleAnswersSchema` |

The New skill prompts follow a different cached block, `moduleStable`: the authoring standard
(`assets/content/authoring.md`) and the candidate's facts. The app assigns every id, drops
unusable exercises, and saves nothing unless the module passes `moduleProblems`
(`lib/engine/skill_builder.dart`).

Questions: `assets/content/questions/<category>.json`, 598 in eight categories, each with what
the interviewer is checking, a guide to a strong answer, pitfalls and follow-ups. Each skill
module adds its own under `interviewQuestions` with model answers. Format:
`docs/content-schema.md`. A session outside the app can fill the same roles: `docs/inbox.md`.
