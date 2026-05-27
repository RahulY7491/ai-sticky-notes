# Play Store setup (one-time)

This is the one-time configuration you do **before** your first
production release. After this is done, [RELEASING.md](RELEASING.md)
is the only doc you need for each subsequent release.

Estimated time: 60–90 minutes the first time, including waiting for
the Google review of your developer account.

---

## Phase 1 — Google Play developer account

1. Go to https://play.google.com/console.
2. Sign up. **One-time fee of US $25.**
3. Choose **Personal** or **Organization**. Personal is fine for a
   solo project; switching later requires re-verification.
4. Complete the identity verification — they will ask for a govt-ID
   scan and may take 1–3 business days to approve. Production releases
   are blocked until verified.

---

## Phase 2 — Create the app

In Play Console → **Create app**:

| Field                    | Value                                                          |
|--------------------------|----------------------------------------------------------------|
| App name                 | AI Sticky Notes                                                |
| Default language         | English (United States)                                        |
| App or game              | App                                                            |
| Free or paid             | Free                                                           |
| Declarations             | Tick both (Play policies + US export laws)                     |

After creation, your **package name** is locked: `com.aistickynotes.app`.
This matches `applicationId` in `app/android/app/build.gradle.kts` — do
not change one without the other.

---

## Phase 3 — Enroll in Play App Signing (mandatory)

Google now manages the signing key for every new app. Your local
keystore (`ai_sticky_notes_keystore.jks`) becomes the **upload key** —
Google re-signs your AAB with the real signing key on their side.

This is good news: losing the upload key is recoverable (Google can
issue you a new one); losing the actual signing key would be fatal.

You don't have to do anything special — the first AAB you upload
triggers the enrollment dialog. Pick **"Let Google generate and
manage the app signing key"**.

---

## Phase 4 — First release: do it manually

For the very first upload Google needs the AAB through the UI, not
the API. After that, the workflow can do it automatically.

1. Run the workflow manually: **Actions → android-release → Run
   workflow → track: skip** (just builds the artifacts).
2. Download `ai-sticky-notes-release-aab` from the run.
3. Play Console → **Production → Create new release**:
   - Upload the AAB.
   - Release name: `1.0.5 (7)`.
   - Release notes: paste from the GitHub Release page.
4. Save → Review → Roll out (start at 5% if you're cautious, 100% for
   a tiny audience).

---

## Phase 5 — Required store-listing assets

Play won't let the production release roll out until these are filled
in. All of them live under **Grow → Store presence → Main store
listing**.

| Asset                  | Spec                                                   | Notes                                 |
|------------------------|--------------------------------------------------------|---------------------------------------|
| App icon               | 512×512 PNG, ≤ 1 MB                                    | Already generated via `flutter_launcher_icons`; export from `assets/images/app_icon.png`. |
| Feature graphic        | 1024×500 PNG / JPG, no alpha                           | Required. The big banner on your listing. |
| Phone screenshots      | 2–8 images, 16:9 or 9:16, min side 320, max side 3840 | Use the Flutter Inspector + a Pixel 7 emulator. |
| 7-inch tablet shots    | Recommended if you support tablets                     | Same constraints, different aspect.   |
| Short description      | ≤ 80 chars                                             | One-liner. "AI sticky notes that summarise, capture by voice, and remind you." |
| Full description       | ≤ 4000 chars                                           | First 2 lines show by default — front-load value. |
| Category               | **Productivity**                                       |                                       |
| Tags (≤ 5)             | `productivity`, `notes`, `ai`, `voice`, `reminders`   |                                       |
| Contact email          | Required                                               | Use a real address; users mail you here for support. |
| Privacy policy URL     | Required                                               | Must be HTTPS, must match what the app actually does. |

A minimal acceptable privacy policy template lives in
`docs/PRIVACY_POLICY_TEMPLATE.md` (TODO — open an issue if you'd like
me to add one).

---

## Phase 6 — Required compliance forms

These are linked from **Policy → App content**. The release stays
blocked until each one shows a green checkmark.

| Form                          | Your answer (probably)                                 |
|-------------------------------|--------------------------------------------------------|
| Privacy policy URL            | Same URL as the store listing.                         |
| App access                    | All functionality available without restrictions.      |
| Ads                           | "No, my app does not contain ads."                     |
| Content rating questionnaire  | Productivity, no violence / drugs / gambling.          |
| Target audience               | 18+ (AI features make 13+ trickier — pick 18+ to avoid the Designed-for-Families program). |
| News app                      | No.                                                    |
| Covid-19 contact tracing      | No.                                                    |
| Data safety                   | See below — this one is non-trivial.                   |
| Government app                | No.                                                    |
| Financial features            | No.                                                    |
| Health                        | No.                                                    |

### Data safety — what to declare

Be honest. False answers here are the #1 reason apps get suspended.

| Data type           | Collected? | Shared with 3rd parties? | Why?                              |
|---------------------|------------|--------------------------|-----------------------------------|
| Voice / audio       | No, voice is transcribed on-device by `speech_to_text`; only the resulting text leaves the device. | n/a | Voice capture |
| Text (note bodies)  | Yes, only when the user invokes an AI action | Yes, **Google Gemini** | Summaries, action extraction, voice-note structuring |
| App activity        | No (no analytics in the app)             | No                       | —                                 |
| Crash data          | Recommended to add — see "Optional: crash reporting" below | No | Debugging |

You'll also need to declare encryption-in-transit (yes — HTTPS to Gemini)
and whether users can request deletion (yes — local notes are deleted
on uninstall; nothing is server-stored).

---

## Phase 7 — Set up the GitHub Action secrets

These are the secrets the `android-release` workflow expects. Go to
**Settings → Secrets and variables → Actions → New repository secret**:

### Signing-related secrets

```bash
# Run these on the dev machine that holds the keystore.

# 1. Base64-encode the keystore for transport through GitHub Secrets.
#    -w0 disables line-wrapping so the secret value is a single line.
base64 -w0 app/android/ai_sticky_notes_keystore.jks > /tmp/keystore.b64
#    Copy the contents of /tmp/keystore.b64 into the secret value box.
```

| Secret name                  | Value                                                                 |
|------------------------------|-----------------------------------------------------------------------|
| `ANDROID_KEYSTORE_BASE64`    | Output of `base64 -w0 app/android/ai_sticky_notes_keystore.jks`.      |
| `ANDROID_KEYSTORE_PASSWORD`  | `storePassword` from `app/android/key.properties`.                    |
| `ANDROID_KEY_PASSWORD`       | `keyPassword` from `app/android/key.properties`.                      |
| `ANDROID_KEY_ALIAS`          | `keyAlias` from `app/android/key.properties`.                         |
| `GEMINI_API_KEY`             | Your Google AI Studio API key.                                        |

On Windows PowerShell the equivalent of `base64 -w0` is:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("app\android\ai_sticky_notes_keystore.jks")) `
  | Out-File -NoNewline -Encoding ascii $env:TEMP\keystore.b64
notepad $env:TEMP\keystore.b64   # then copy the contents into the GitHub secret
```

### Play Store API secret (only if you want automated uploads)

This is the most involved part — skip it for now if you just want to
ship the first release manually.

1. Go to https://console.cloud.google.com/iam-admin/serviceaccounts.
2. Create a new project (or reuse one).
3. Create a **service account** named `play-store-release-bot`.
4. **Keys** tab → Add key → JSON → download the JSON file. Treat this
   like a password — it lets the bearer publish releases.
5. Go to https://play.google.com/console → **Users and permissions →
   Invite new users**:
   - Email: the service account address from the JSON
     (`...@<project>.iam.gserviceaccount.com`).
   - App permissions: select AI Sticky Notes.
   - Account permissions: tick **Release manager**.
   - Send invite.
6. Back in GitHub → add a secret:
   - Name: `PLAY_STORE_SERVICE_ACCOUNT_JSON`
   - Value: paste the **entire contents** of the JSON file.

The first time you run the workflow with this secret, the upload will
fail with "the application needs the API enabled". Go to
https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com
and click **Enable** on the same project. Re-run the workflow.

---

## Optional: crash reporting

The app currently ships without Firebase Crashlytics or Sentry. The
Play Console's built-in vitals dashboard gives you crash and ANR rates
out of the box, but it's not as detailed as a dedicated SDK.

If you want richer crash diagnostics:

- **Firebase Crashlytics** — free, tightly integrated with Play.
- **Sentry** — open-source-friendly, generous free tier.

Either way, the workflow already uploads `--obfuscate` mapping +
debug-symbols artifacts, so Play Console can de-obfuscate stack
traces without any extra setup.

---

## Once everything's green

You can finally hit **Create new release** on the Production track. The
button will be enabled and the page will say "Ready to publish."

From that moment on, your loop is:

```
edit code → commit → bump pubspec → tag → push → Play picks it up
```

…which is exactly the loop [RELEASING.md](RELEASING.md) documents.
