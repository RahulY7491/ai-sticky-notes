# Releasing AI Sticky Notes

This is the runbook for cutting a new release. If you're setting up
the Play Store for the very first time, read
[PLAY_STORE_SETUP.md](PLAY_STORE_SETUP.md) first — that's the one-time
config.

---

## TL;DR — cutting a normal release

```bash
# 1. From an up-to-date main:
git checkout main && git pull

# 2. Bump version in app/pubspec.yaml
#    versionName goes up for users, versionCode +N must strictly increase.
#    e.g. 1.0.5+7  ->  1.0.6+8
$EDITOR app/pubspec.yaml

# 3. Commit and tag
git add app/pubspec.yaml
git commit -m "chore(release): v1.0.6"
git tag v1.0.6
git push origin main v1.0.6
```

That tag push triggers the `android-release` workflow, which:

1. Verifies the tag matches `pubspec.yaml`.
2. Runs `flutter analyze` + `flutter test`.
3. Builds an obfuscated, signed AAB + universal APK + debug symbols.
4. Creates a GitHub Release at
   `https://github.com/RahulY7491/ai-sticky-notes/releases/tag/v1.0.6`
   with auto-generated release notes and the AAB/APK attached.

It **does not** automatically push to the Play Store. See "Publishing
to the Play Store" below.

---

## The version-number rules

Flutter expresses both numbers as `versionName+versionCode`:

```yaml
version: 1.0.5+7
```

| Part      | Format         | Meaning                                                            |
|-----------|----------------|--------------------------------------------------------------------|
| `1.0.5`   | semver         | What users see in the Play listing and the app's About screen.     |
| `+7`      | integer ≥ 1    | Play's internal counter. Must strictly increase for every upload.  |

Rules of thumb:

- **Bug fix only:** bump the patch — `1.0.5+7` → `1.0.6+8`
- **New feature, no breaking change:** bump the minor — `1.0.5+7` → `1.1.0+8`
- **Breaking change (e.g. dropped Android version, data migration):** bump the major.
- **Bumped `pubspec.yaml` once and the upload was rejected (wrong signing key, etc.)?** You still have to bump `versionCode` for the next attempt — Play remembers rejected uploads too.

---

## Publishing to the Play Store

Two modes — pick whichever fits the change.

### Mode A: Manual via Play Console (safest, no service account needed)

1. Wait for the tag-push run to finish.
2. Download `ai-sticky-notes-release-aab` from the Actions run page.
3. In Play Console → **Production** → **Create new release**:
   - Upload the `.aab`.
   - Paste the release notes (copy from the GitHub Release).
   - Choose a rollout percentage (start with 5–20% for non-trivial releases).
4. Click **Save** → **Review release** → **Start rollout**.
5. Monitor crash rate and 1-star reviews for 24–48 hours before pushing
   the rollout to 100%.

### Mode B: Automated via the workflow (requires service account setup)

Once `PLAY_STORE_SERVICE_ACCOUNT_JSON` is configured (see
[PLAY_STORE_SETUP.md](PLAY_STORE_SETUP.md)):

1. Go to **Actions → android-release → Run workflow**.
2. Pick a `track`:
   - `internal` — instant, up to 100 testers, you can iterate.
   - `alpha` / `beta` — wider closed/open testing tracks.
   - `production` — the real thing.
3. If `production`, set `rollout` (e.g. `0.10` = 10%).
4. Run.

The workflow pushes the same AAB you'd upload manually, plus mapping
and symbol files so the Play Console can de-obfuscate crashes.

---

## The staged-rollout playbook

Don't ship to 100% on day one. The standard pattern:

| Day | Rollout | What you're watching for                       |
|-----|---------|------------------------------------------------|
| 0   | 5%      | Crash-free sessions ≥ 99.5%. ANR rate < 0.47%. |
| 1–2 | 20%     | Same metrics + 1-star review trend.            |
| 3–5 | 50%     | Confirm no regressions in core funnels.        |
| 7+  | 100%    | Full rollout.                                  |

To bump the rollout, re-run the workflow with the same `track` and a
higher `rollout` value, **or** do it manually in Play Console →
Production → the release → "Update rollout".

To halt: Play Console → the release → "Halt rollout". The current
rollout freezes; existing users keep their version. You then ship a
fix on a higher `versionCode` and start a new rollout.

---

## Pre-release checklist

Before you push the tag, make sure:

- [ ] `flutter analyze` is clean locally (`cd app && flutter analyze`)
- [ ] `flutter test` is green locally (`cd app && flutter test`)
- [ ] `pubspec.yaml` version is bumped
- [ ] CHANGELOG / release notes drafted (the workflow auto-generates
      from commit messages, so use [Conventional Commits](https://www.conventionalcommits.org/))
- [ ] No new permissions in `AndroidManifest.xml` you haven't declared
      in Play Console → Policy → Data safety
- [ ] If you bumped `minSdk` or `targetSdk`, verify in Play Console →
      Release dashboard that you haven't cut off existing users
- [ ] Privacy policy URL is still live and reachable

---

## When something goes wrong

### "Upload failed: versionCode 7 has already been used."

Bump `+N` in `pubspec.yaml`, re-tag (delete the old tag first:
`git tag -d v1.0.5 && git push --delete origin v1.0.5`), push.

### "Your release is using a different signing key."

Either you regenerated the keystore (don't — it's permanent for the
app) or the `ANDROID_KEYSTORE_BASE64` secret isn't the same keystore
you used for the previous release. If you've truly lost the keystore,
you have to enroll a new upload key via Play Console → Setup → App
integrity → "Use a different key" → upload the PEM Google emails you.

### "Your APK or Android App Bundle must target API level 36 or higher."

Update `targetSdk = 36` in `app/android/app/build.gradle.kts`. Every
August, Google bumps the minimum target SDK by one version.

### "We found violations in your app's data safety section."

Go to Play Console → Policy → App content → Data safety → re-answer
the questionnaire. The current answers must match what your app
actually does (Gemini sees voice transcripts and brain-dump text).

---

## Rolling back

You can't actually replace a released version on the Play Store. To
"roll back" you ship a new version that's effectively the old code:

```bash
git revert <bad-commit-sha>          # creates a new commit
$EDITOR app/pubspec.yaml             # bump versionCode + 1
git commit -am "chore(release): v1.0.7 (rollback)"
git tag v1.0.7
git push origin main v1.0.7
```

Or halt the current rollout (see above) so it doesn't reach more users
until a fix is ready.
