# AI Sticky Notes

[![flutter-ci](https://github.com/RahulY7491/ai-sticky-notes/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/RahulY7491/ai-sticky-notes/actions/workflows/flutter-ci.yml)
[![backend-ci](https://github.com/RahulY7491/ai-sticky-notes/actions/workflows/backend-ci.yml/badge.svg)](https://github.com/RahulY7491/ai-sticky-notes/actions/workflows/backend-ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

> AI-powered sticky notes for working professionals. Capture by voice,
> brain-dump messy thoughts into structured notes, get smart reminders,
> and pin everything to a home-screen widget.

<!--
Add screenshots here once you have them. Three ~270px-wide PNGs side
by side works well. Example:

<p align="center">
  <img src="docs/screenshots/home.png" width="270" alt="Home screen" />
  <img src="docs/screenshots/voice.png" width="270" alt="Voice capture" />
  <img src="docs/screenshots/braindump.png" width="270" alt="Brain dump" />
</p>
-->

## Features

- **Voice notes** — 15-second voice capture that gets transcribed and
  reformatted into a clean title + body via Gemini.
- **Brain dump** — paste a wall of messy text and get structured notes,
  action items, or a summary.
- **Smart reminders** — natural-language times ("tomorrow at 8") get
  parsed and scheduled with Android's alarm clock.
- **Home-screen widget** — your most recent notes, one tap away.
- **Offline-first** — local Hive storage; AI calls only when you ask
  for them.
- **No telemetry** — your notes stay on your device.

## Project layout

```
ai-sticky-notes/
├── app/                          # Flutter mobile app (Android / iOS / web / desktop)
│   ├── lib/                      # Dart source
│   └── test/                     # Widget + unit tests
├── backend/AIStickyNotes.API/    # ASP.NET Core 8 backend (Gemini proxy)
└── .github/workflows/            # GitHub Actions CI/CD
```

## Local setup

### Flutter app

```bash
cd app
flutter pub get
flutter test
flutter run --dart-define=GEMINI_API_KEY=your_key_here
```

### .NET backend

The backend reads the Gemini key from configuration. **Do not** put real
keys in `appsettings.json` — it's checked in as a template only. Use one
of these mechanisms for local development:

1. **`appsettings.Development.json`** (gitignored — your file, your key):

   ```json
   {
     "Gemini": {
       "ApiKey": "AIza..."
     }
   }
   ```

2. **.NET User Secrets** (preferred — never on disk inside the repo):

   ```bash
   cd backend/AIStickyNotes.API
   dotnet user-secrets init
   dotnet user-secrets set "Gemini:ApiKey" "AIza..."
   ```

Then:

```bash
cd backend/AIStickyNotes.API
dotnet run
```

## CI/CD

GitHub Actions runs three workflows defined in `.github/workflows/`:

| Workflow | Triggers on | What it does |
|---|---|---|
| `flutter-ci.yml` | push / PR touching `app/**` | `flutter analyze` + `flutter test` |
| `backend-ci.yml` | push / PR touching `backend/**` | `dotnet build` (Release) |
| `android-build.yml` | tag push `v*`, or manual | Builds the release APK and uploads it as an artifact |

### Required GitHub secrets

Configure these under **Settings → Secrets and variables → Actions** in
the GitHub repo:

| Secret | Used by | Purpose |
|---|---|---|
| `GEMINI_API_KEY` | `android-build.yml` | Compiled into the APK via `--dart-define` so the Flutter `AiService` can reach the Gemini API. |

### Cutting a release

```bash
git tag v1.0.5
git push origin v1.0.5
```

The `android-build` workflow will pick the tag up, build the release APK,
and attach it as a downloadable artifact on the workflow run's summary.

## Contributing

We :heart: contributions of all sizes — bug fixes, features, tests,
docs, translations, design feedback. Start here:

- Read [**CONTRIBUTING.md**](CONTRIBUTING.md) for setup and the PR
  workflow.
- Look for issues labelled
  [`good first issue`](https://github.com/RahulY7491/ai-sticky-notes/labels/good%20first%20issue)
  or [`help wanted`](https://github.com/RahulY7491/ai-sticky-notes/labels/help%20wanted).
- Found a security issue? Please read [**SECURITY.md**](SECURITY.md) —
  don't open a public issue.
- All participants are expected to follow our
  [**Code of Conduct**](CODE_OF_CONDUCT.md).

## Roadmap

Rough order, not a promise:

- [ ] iOS build target in CI
- [ ] End-to-end encryption for synced notes
- [ ] Optional cloud sync (self-hostable via the .NET backend)
- [ ] Web build polish (PWA install prompts, share-target)
- [ ] Localisation (i18n) — English first, then community translations
- [ ] In-app theming (dark mode polish, accent colour picker)
- [ ] Note search with semantic recall (embeddings via Gemini)

Open an issue if you want to claim one of these or propose a new bullet.

## Tech stack

| Layer       | Choice                                       | Why                                            |
|-------------|----------------------------------------------|------------------------------------------------|
| App         | Flutter 3.41 (Dart 3)                        | One codebase for Android / iOS / Web / Desktop |
| State       | `provider`                                   | Simple, no codegen, great for small apps       |
| Storage     | `hive` + `hive_flutter`                      | Fast local KV store, works on web              |
| Notifications | `flutter_local_notifications`              | Android exact-alarm scheduling                 |
| Voice       | `speech_to_text`                             | On-device STT, no recordings leave the phone   |
| AI          | Google Gemini (`gemini-2.5-flash`)           | Cheap, fast, good enough for note structuring  |
| Backend     | ASP.NET Core 8                               | Optional proxy / sync target                   |
| CI          | GitHub Actions                               | Free for public repos, matrix-friendly         |

## License

[MIT](LICENSE) — do whatever you want, but no warranty. Attribution
appreciated.

## Acknowledgements

- The [Contributor Covenant](https://www.contributor-covenant.org/) for
  the Code of Conduct template.
- Everyone who has filed an issue, opened a PR, or starred the repo —
  you're the reason this exists.
