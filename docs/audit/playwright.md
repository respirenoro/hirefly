# Audit: Playwright module

## Benchmarks
- Playwright docs: [Installation](https://playwright.dev/docs/intro), [Best Practices](https://playwright.dev/docs/best-practices), [Locators](https://playwright.dev/docs/locators), [Assertions](https://playwright.dev/docs/test-assertions), [Trace viewer](https://playwright.dev/docs/trace-viewer), [CI](https://playwright.dev/docs/ci), [Mock APIs](https://playwright.dev/docs/mock), [API testing](https://playwright.dev/docs/api-testing), [Fixtures](https://playwright.dev/docs/test-fixtures), [Authentication](https://playwright.dev/docs/auth)
- [Microsoft Learn module](https://learn.microsoft.com/en-us/training/modules/build-with-playwright) and [video series](https://learn.microsoft.com/shows/getting-started-with-end-to-end-testing-with-playwright/introduction-to-playwright-for-end-to-end-testing)
- [Interview list](https://testdino.com/blog/playwright-interview-questions-answers-2026)

## Gaps (12 lessons before)
No contexts, drills, page objects, test data, parallelism and reporters, mocking, API checks, accessibility or visual mention, fix-the-tests practice, manual-versus-automate lesson, labs or resources.

## Factual fixes
- Installer folder: `tests/example.spec.ts`, not `tests-examples/`.
- Azure YAML now follows the official sample; retried passes leave runs green.
- HTML reporter `open: 'never'`.
- New traps found by running: `goto('/')` drops a path in `baseURL`; `waitForResponse` hangs on in-browser navigation; an unawaited assertion failed with "Test ended" in 1.65.

## Changed
Now 28 lessons in 8 units (above the schema's 4 to 6): four locator drills (16 graded), assertions drill, contexts, fixtures and page objects, test data, parallelism and reporters, debugging workflow, mocking, API check, accessibility and visual (marked "learned in practice"), manual versus automate, five failing tests. 12 resources, 7 labs, 16 interview questions.

## What I ran
Playwright 1.65, Node 24, Chromium, on playwright.dev, the TodoMVC demo and jsonplaceholder. All lesson specs passed; each intended failure failed as quoted. Also retries and the flaky label, trace on retry, CI-style JUnit and HTML output, axe, ARIA and screenshot checks, and a YAML parse.

## Could not verify
- Azure Pipelines itself: only parsed, and its commands run locally.
- Codegen recording, trace viewer, UI mode and `--debug` windows were not driven.
- Firefox and WebKit were not installed.
- No Playwright YouTube link was found, so none is listed.
