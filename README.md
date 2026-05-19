# AI Sticky Notes

A productivity app for working professionals. AI-powered sticky notes with
voice capture, brain-dump, smart reminders, and a home-screen widget.

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
