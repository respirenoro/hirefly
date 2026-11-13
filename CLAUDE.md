# HireFly

Interview preparation and skills training. Flutter, Windows desktop, local data.

**If the user asks to install or set up HireFly, follow `SETUP.md` step by step.**

- The user's data lives in `Documents\HireFly`, never in this repo.
- Content format: `docs/content-schema.md`. Driving the app from a session: `docs/inbox.md`.
- Writing or extending a skill module: follow `assets/content/authoring.md` (the steps are in
  `integrations/claude-skill/hirefly-module/SKILL.md`), then run
  `python tool/check_module.py <module folder> --links`.
- Checks: `flutter analyze`, `flutter test`, and
  `flutter test integration_test/app_test.dart -d windows`.
- After changing `lib/data/db.dart`: `dart run build_runner build`.
