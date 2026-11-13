# Checks one skill module folder against docs/content-schema.md and
# assets/content/authoring.md.
#
#   python tool/check_module.py <module folder> [--links] [--bundled]
#
# --links    also requests every resource link and reports the ones that fail.
# --bundled  apply the limits for a module shipped with the app (12 or more
#            lessons); without it a learner's own module needs 6.
# Exits 1 when anything is wrong.
import json
import pathlib
import re
import sys
import urllib.request

args = [a for a in sys.argv[1:] if not a.startswith('--')]
flags = {a for a in sys.argv[1:] if a.startswith('--')}
if len(args) != 1:
    sys.exit(__doc__ or 'usage: python tool/check_module.py <module folder> [--links] [--bundled]')
folder = pathlib.Path(args[0])
problems, notes = [], []


def load(path):
    try:
        return json.loads(path.read_text(encoding='utf-8'))
    except FileNotFoundError:
        problems.append(f'{path.name}: missing')
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        problems.append(f'{path.name}: not valid UTF-8 JSON ({e})')
    return None


module = load(folder / 'module.json')
if not isinstance(module, dict):
    print('\n'.join(problems))
    sys.exit(1)

mid = module.get('id', '')
if not re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*', str(mid)):
    problems.append(f'module id {mid!r} is not lowercase kebab-case')
for field in ('title', 'tagline', 'claim'):
    if not str(module.get(field, '')).strip():
        problems.append(f'module.json: no {field}')

ids, lessons = set(), []


def claim(i, where):
    if not i or i in ids:
        problems.append(f'{where}: id {i!r} is missing or used twice')
    ids.add(i)


units = module.get('units') or []
if not 3 <= len(units) <= 14:
    problems.append(f'{len(units)} units; expected 4 to 6 for a new module')
last_title = ''
for name in units:
    unit = load(folder / name)
    if not isinstance(unit, dict):
        continue
    claim(unit.get('id'), name)
    last_title = str(unit.get('title', ''))
    for lesson in unit.get('lessons') or []:
        lid = lesson.get('id')
        claim(lid, name)
        lessons.append(lesson)
        if len(str(lesson.get('body', ''))) <= 400:
            problems.append(f'{lid}: body is too short')
        if re.search(r'https?://', str(lesson.get('body', ''))) and '--bundled' not in flags and not module.get('resources'):
            notes.append(f'{lid}: the body contains a web link; confirm it was opened')
        if not 3 <= len(lesson.get('keyPoints') or []) <= 5:
            problems.append(f'{lid}: needs 3 to 5 keyPoints')
        if not str(lesson.get('interviewAngle', '')).strip():
            problems.append(f'{lid}: no interviewAngle')
        ex = lesson.get('exercises') or []
        if not 3 <= len(ex) <= 8:
            problems.append(f'{lid}: {len(ex)} exercises; expected 3 to 5')
        if not any(e.get('type') == 'mcq' for e in ex):
            problems.append(f'{lid}: no multiple-choice exercise')
        if not any(e.get('type') == 'open' for e in ex):
            problems.append(f'{lid}: no open exercise')
        if sum(1 for e in ex if e.get('placement') is True) != 1:
            problems.append(f'{lid}: needs exactly one placement exercise')
        for e in ex:
            eid, kind = e.get('id'), e.get('type')
            claim(eid, name)
            if not str(e.get('prompt', '')).strip():
                problems.append(f'{eid}: no prompt')
            if kind == 'mcq':
                choices, answer = e.get('choices') or [], e.get('answer')
                if len(choices) < 3 or not isinstance(answer, int) or not 0 <= answer < len(choices):
                    problems.append(f'{eid}: needs 3 or 4 choices and an answer index inside them')
                if not str(e.get('explanation', '')).strip():
                    problems.append(f'{eid}: no explanation')
            elif kind == 'short':
                accept = e.get('accept') or []
                if not accept or not e.get('answer'):
                    problems.append(f'{eid}: needs accept and answer')
            elif kind == 'open':
                if not e.get('answer') or not e.get('rubric'):
                    problems.append(f'{eid}: needs a model answer and a rubric')
                if e.get('placement'):
                    problems.append(f'{eid}: an open exercise cannot be the placement question')
            else:
                problems.append(f'{eid}: unknown type {kind!r}')

need = 12 if '--bundled' in flags else 6
if len(lessons) < need:
    problems.append(f'{len(lessons)} lessons; needs at least {need}')
if units and 'interview' not in last_title.lower():
    problems.append(f'the last unit is "{last_title}"; it should be "In the interview"')

answers = [0, 0, 0, 0]
for lesson in lessons:
    for e in lesson.get('exercises') or []:
        if e.get('type') == 'mcq' and isinstance(e.get('answer'), int) and e['answer'] < 4:
            answers[e['answer']] += 1
if sum(answers) >= 12 and max(answers) > 0.6 * sum(answers):
    notes.append(f'correct choices sit at positions {answers}; vary them')

iq = module.get('interviewQuestions') or []
if len(iq) < 6:
    problems.append(f'{len(iq)} interviewQuestions; needs at least 6 (8 or more for a new module)')
for q in iq:
    claim(q.get('id'), 'interviewQuestions')
    words = len(str(q.get('strongAnswer', '')).split())
    if not str(q.get('prompt', '')).strip() or words < 40:
        problems.append(f"{q.get('id')}: needs a prompt and a model answer of 60 to 120 words (has {words})")
    elif words > 150:
        notes.append(f"{q.get('id')}: model answer is {words} words; it is meant to be spoken")

for lab in module.get('labs') or []:
    claim(lab.get('id'), 'labs')
    if len(lab.get('steps') or []) < 3 or not lab.get('check'):
        problems.append(f"{lab.get('id')}: a lab needs 3 or more steps and a check")
    if not lab.get('talkTrack'):
        notes.append(f"{lab.get('id')}: no talkTrack")

resources = module.get('resources') or []
for r in resources:
    url = str(r.get('url', ''))
    if not url.startswith('https://'):
        problems.append(f"resource {r.get('title')!r}: the link must start with https://")
    for field in ('title', 'why'):
        if not str(r.get(field, '')).strip():
            problems.append(f'resource {url}: no {field}')
    for field in ('priority', 'useWhen', 'versus'):
        if not str(r.get(field, '')).strip():
            notes.append(f"resource {r.get('title')!r}: no {field}")
    if r.get('priority') not in (None, 'core', 'worthwhile', 'optional'):
        problems.append(f"resource {r.get('title')!r}: priority must be core, worthwhile or optional")
if 'unverified' not in module:
    notes.append('module.json has no "unverified" list; add one, empty only if everything was confirmed')
if not resources:
    notes.append('no outside resources; fine for a module written without web access')

if '--links' in flags:
    for r in resources:
        url = str(r.get('url', ''))
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (link check)'})
            with urllib.request.urlopen(req, timeout=20) as resp:
                if resp.status >= 400:
                    problems.append(f'link answers {resp.status}: {url}')
                elif resp.geturl().rstrip('/') != url.rstrip('/'):
                    notes.append(f'link redirects: {url} -> {resp.geturl()}')
        except Exception as e:  # a refused or blocked request still needs a person to look
            notes.append(f'link could not be checked ({type(e).__name__}: {e}): {url}')

print(f'{mid}: {len(units)} units, {len(lessons)} lessons, {sum(len(l.get("exercises") or []) for l in lessons)} exercises, '
      f'{len(iq)} interview questions, {len(module.get("labs") or [])} labs, {len(resources)} resources')
for n in notes:
    print('note:', n)
for p in problems:
    print('PROBLEM:', p)
sys.exit(1 if problems else 0)
