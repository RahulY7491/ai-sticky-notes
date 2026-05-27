# Security policy

## Supported versions

Until the project reaches a stable 1.0, only the latest release on
`main` receives security fixes. Older versions are not patched.

| Version          | Supported          |
|------------------|--------------------|
| `main` / latest  | yes                |
| anything older   | no                 |

## Reporting a vulnerability

**Please do not open a public GitHub issue for security problems.**
Public issues notify everyone — including potential attackers — before
a fix is available.

Instead, use one of these channels:

1. **Preferred — GitHub private vulnerability reporting:**
   <https://github.com/RahulY7491/ai-sticky-notes/security/advisories/new>

2. **Email:** r.yadav7491@gmail.com with the subject line
   `[security] ai-sticky-notes: <short summary>`

Please include:

- A description of the vulnerability and its impact.
- Reproduction steps (proof-of-concept code, screenshots, logs).
- The affected component (Flutter app, backend, CI workflows).
- Any suggested mitigation.

## What to expect

| Step                             | SLA (best effort)        |
|----------------------------------|--------------------------|
| Acknowledgement of your report   | within 48 hours          |
| Initial assessment and severity  | within 5 business days   |
| Fix released (for critical bugs) | within 30 days           |
| Public disclosure / CVE          | after a fix ships        |

If we agree the report is valid, you'll be credited in the release
notes (unless you'd rather stay anonymous).

## What is **not** in scope

- Vulnerabilities in third-party packages we depend on — report those
  upstream (e.g. to `flutter`, `dotnet`, or the package author). Open
  a regular issue here only if we need to bump the version.
- Social-engineering attacks against maintainers.
- DoS via excessive Gemini API usage from a stolen key — rotate the
  key in Google AI Studio and update your GitHub secret.

## Handling leaked secrets

If you accidentally committed a real Gemini API key (or any other
credential) to a public fork or PR:

1. **Rotate the key immediately** in Google AI Studio — assume it's
   compromised.
2. Force-push a cleaned branch (or use `git filter-repo` for fully
   removing it from history).
3. Update the `GEMINI_API_KEY` GitHub Action secret with the new key.

We will never ask you to share a real API key in an issue, PR, or
email.
