# Contributing to AI Sticky Notes

First off — thank you for considering contributing! AI Sticky Notes is a
small but growing open-source project, and contributions of any size are
welcome: bug fixes, new features, documentation polish, test coverage,
translations, design feedback, even just thoughtful issue reports.

This document tells you everything you need to get from "I cloned the
repo" to "my PR got merged."

---

## TL;DR

```bash
# 1. Fork the repo on GitHub, then clone your fork
git clone https://github.com/<your-username>/ai-sticky-notes.git
cd ai-sticky-notes

# 2. Run the existing tests to make sure your environment works
cd app && flutter pub get && flutter test && cd ..
cd backend/AIStickyNotes.API && dotnet restore && dotnet build && cd ../..

# 3. Create a branch, code, commit, push
git checkout -b feat/short-feature-name
# ...edit files...
git commit -m "feat: human-readable description"
git push origin feat/short-feature-name

# 4. Open a Pull Request on GitHub against `main`
```

---

## Ways to contribute

1. **Pick a `good first issue`.** Anything labelled
   [`good first issue`](https://github.com/RahulY7491/ai-sticky-notes/labels/good%20first%20issue)
   on the issue tracker is scoped specifically for newcomers — small,
   self-contained, and explained step by step.
2. **Pick a `help wanted` issue.** These are bigger or more open-ended
   tasks the maintainers haven't gotten to.
3. **File a bug.** Open an issue using the **Bug report** template if
   something doesn't work the way the docs say it should.
4. **Propose a feature.** Open an issue using the **Feature request**
   template *before* writing code, so we can agree on the shape of the
   change.
5. **Improve docs.** README, CONTRIBUTING, code comments — all fair game.
   Doc-only PRs do not need an issue first.

---

## Local development setup

### Prerequisites

| Tool      | Version           | Notes                                                |
|-----------|-------------------|------------------------------------------------------|
| Flutter   | 3.41.4 (stable)   | `flutter --version` should match                     |
| Dart      | 3.11.1            | Bundled with Flutter                                 |
| .NET SDK  | 8.0.x             | https://dotnet.microsoft.com/download/dotnet/8.0     |
| Android Studio or VS Code | latest | For the Flutter app                              |
| A Gemini API key | —          | https://aistudio.google.com/apikey (free tier works) |

### Flutter app (`app/`)

```bash
cd app
flutter pub get
flutter test                   # runs all unit + widget tests
flutter analyze                # static analysis
flutter run --dart-define=GEMINI_API_KEY=your_key
```

Common dev tasks:

- **Run a single test file:** `flutter test test/voice_note_sheet_test.dart`
- **Generate launcher icons:** `flutter pub run flutter_launcher_icons`
- **Build a release APK locally:** `flutter build apk --release --dart-define=GEMINI_API_KEY=your_key`

### Backend (`backend/AIStickyNotes.API/`)

```bash
cd backend/AIStickyNotes.API
dotnet user-secrets init                                # one-time
dotnet user-secrets set "Gemini:ApiKey" "your_key"      # one-time
dotnet run
```

The API listens on https://localhost:7xxx — the exact port is printed at
startup. Use `Properties/launchSettings.json` to change it.

**Never** put real keys into `appsettings.json` or
`appsettings.Development.json` if those files will be committed. Use
`dotnet user-secrets` instead; it stores secrets outside the repo.

---

## Coding style

### Dart / Flutter

- Run `flutter analyze` before committing — CI will fail otherwise.
- Prefer `const` constructors wherever possible.
- Widget files live under `lib/widgets/`, screen files under
  `lib/screens/`, services under `lib/services/`. Try to match the
  existing pattern rather than introducing new top-level folders.
- Wrap text shown to users in `Text(...)` — no string concatenation in
  `build()`. Once we add i18n, the wrapping moves to `S.of(context).foo`.

### C# / .NET

- Match the existing nullable-reference and implicit-usings style — both
  are enabled in the `.csproj`.
- One controller per domain concept; thin controllers, fat services.

### Tests

- Every new widget / service should ship with a test where reasonable.
  See `app/test/voice_note_sheet_test.dart` for an example of how to
  test widgets that depend on platform plugins (we mock the speech
  channel).
- Flutter widget tests must not rely on real network, audio, or storage —
  inject test doubles or mock platform channels.

---

## Commit message format

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
type(optional scope): short description in lowercase, no period

(optional blank line)
(optional longer body, wrapped at 72 chars)
```

Common types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`,
`ci`, `perf`.

**Good examples:**
- `feat(voice): add live waveform visualisation while recording`
- `fix(android): correct alarm-clock channel ID on Android 14`
- `docs: clarify Gemini key placement in CONTRIBUTING`
- `test(brain-dump): cover empty-input path of the use case`

**Avoid:** `Update files`, `fix bug`, `wip`, `asdf`.

---

## Pull request process

1. **One PR = one logical change.** A bug fix and a refactor go in
   separate PRs. Reviewers can merge small focused PRs in minutes;
   500-line grab-bags can sit for weeks.
2. **Reference the issue.** Put `Closes #123` in the PR description if
   your PR fixes an issue.
3. **CI must be green.** The PR will be blocked from merge until
   `flutter-ci` and (if you touched `backend/`) `backend-ci` pass.
4. **Fill out the PR template.** It's short and exists to save back-and-forth.
5. **Be patient and friendly.** Maintainers are volunteers. We'll get to
   your PR — usually within a few days.
6. **Expect review comments.** They're not personal; they're how code
   gets better. Push fixes to the same branch and reply once you've
   addressed each comment.

---

## What gets a PR rejected

Almost nothing gets *rejected* outright — most things just need iteration.
But these slow things down a lot:

- Committing secrets or credentials. (CI does a string scan; even if it
  passes, reviewers will catch this. Rotate the key, force-push the
  cleaned branch, and we move on.)
- Breaking tests without explanation.
- Drive-by formatting changes mixed into a feature PR. (`style:` PRs are
  welcome — just keep them separate.)
- New dependencies without justification. Each `pubspec.yaml` or
  `.csproj` entry is something we have to keep updated forever.

---

## Stuck?

Open a draft PR early or comment on the relevant issue. It's much easier
to course-correct after 20 lines than after 2,000.

Thanks again for being here. 🧠📓
