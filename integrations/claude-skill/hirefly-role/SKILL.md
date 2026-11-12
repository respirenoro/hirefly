---
name: hirefly-role
description: "Drive HireFly, the interview-prep desktop app, from this session: create a prep role for a job (with a role brief and tailored questions you write), or coach the answers the user has written in it. Use when the user says 'send this role to HireFly', 'prep me for X in HireFly', 'I got an interview at X', 'coach my HireFly answers', or 'which skills does HireFly say to study'."
user-invocable: true
---

# HireFly from this session

HireFly watches `%USERPROFILE%\Documents\HireFly\inbox` and answers in `...\HireFly\outbox`.
It must be open. Full file formats: `docs/inbox.md` in the HireFly repo. Touch only those two
folders.

## Send a role

1. Gather what you already have: `role`, `company`, the posting (text, else `url`), the resume
   sent (`resumeFile`, absolute path), a target-state resume if one exists, company research,
   the interviewer, `interviewDate`. Ask only for what you cannot find.
2. Write the `brief` and 6 to 10 `tailored` questions yourself, from the posting and the
   candidate's record. This is what the app's own assistant would do with an API key.
3. Save as `inbox\<company>-<role>.json.tmp`, then rename to `.json`.
4. After about 10 seconds read `outbox\<company>-<role>.md` and tell the user the question
   count, the skills to study and the first step for each. If the file went to `inbox\failed`,
   read its `.error.txt`, fix and resend. If nothing happened, HireFly is not running.

## Coach the answers

1. Read `outbox\<company>-<role>.json`. For each item whose `answer` has text and `coached` is
   false, judge it against `intent` and `guide`.
2. Save `{"type": "coach", "results": [{"id": ..., "eval": {...}}]}` to the inbox the same way.
3. Tell the user which answers were coached and the lowest scores.

## Rules

Use only facts from the candidate's record in this project. Never invent an employer, number
or outcome; ask for missing details in `missing`. Flag any overclaim. Write `improved` in the
candidate's voice. For a live mock interview, run it in this conversation: the app's mock
needs an API key.
