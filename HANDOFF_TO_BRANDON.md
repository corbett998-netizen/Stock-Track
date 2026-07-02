# Stock-Track — Handoff to Brandon

Welcome, Brandon. This is the **Stock-Track app + the owner/operator harness** — the system that
lets you (a non-coder) develop and test your app from your phone with an AI orchestrator.

## Start here
Open **`docs/brandon_handoff/00_START_HERE.md`** and read it fully, then follow the numbered docs
in order. That folder is your complete onboarding pack:

| Doc | What it's for |
|-----|---------------|
| `docs/brandon_handoff/00_START_HERE.md` | What Stock-Track + the harness are, what you're getting, what to do first |
| `docs/brandon_handoff/01_ENVIRONMENT_CHECKLIST.md` | Your orchestrator verifies your machine (WSL2, Zellij, Claude Code, Git/GitHub, Flutter, Android, gcloud/ADC) — honest READY/NOT-READY gate |
| `docs/brandon_handoff/02_FIREBASE_SETUP.md` | Set up **your own** Firebase project step-by-step (the canonical Firebase doc) |
| `docs/brandon_handoff/03_ORCHESTRATOR_ZELLIJ_WORKFLOW.md` | How your orchestrator runs lanes/sub-agents without getting bogged down |
| `docs/brandon_handoff/04_HARNESS_SYSTEMS_CLASSIFICATION.md` | What each harness system is |
| `docs/brandon_handoff/05_DOGFOOD_FLOW.md` | Your first 17-step on-device dogfood checklist |
| `docs/brandon_handoff/06_KNOWN_LIMITATIONS.md` | Honest known limitations / pending confirmation |
| `docs/brandon_handoff/07_SECURITY_ANTILEAK_AUDIT.md` | The security / separation posture |

## Your first steps (high level)
1. Have your orchestrator run **`01_ENVIRONMENT_CHECKLIST.md`** — do not continue until it reads READY.
2. Set up **your own Firebase** with **`02_FIREBASE_SETUP.md`**. **You must use your own Firebase project — never anyone else's.**
3. Your orchestrator builds your **own** APK (it targets *your* Firebase by default) and gets it on your phone.
4. Run **`05_DOGFOOD_FLOW.md`** to prove the whole loop on your device.

## The APK
You build your **own** APK against your **own** Firebase (your orchestrator does this after step 2).
Do **not** install any build that was wired to a different project — those were internal test builds
only. The committed default already points at your project.

## Known technical debt / pending confirmation (honest)
- **Copy-message confirm** (bubble grays + "copied" badge) is in the latest build — confirm it on your device during dogfood.
- **Mic "mic vs Mike":** the app uses the phone's on-device recognizer (same engine as the reference app); "mic"/"Mike" are exact homophones the recognizer guesses between — this is inherent recognizer behavior, not a wiring bug. No per-word override exists.
- **Inventory data is still placeholder/mock** — real cloud persistence is a defined later slice.
- **Cloud Storage is off by default** — turn it on (see `02`/`06`) for screenshot capture.
- **Chat workflow-tagging + top-bar controls, and floating-cluster polish** are future harness cleanup (see `06`), not required for the core loop.
- **A full independent readiness audit** is planned; your first dogfood (`05`) is your own proof.

## What YOU do vs what your ORCHESTRATOR does
Every step in the docs is tagged — console/account actions (Firebase, GitHub, permissions, your
phone) are **yours**; building, deploying, reading logs, and validation are your **orchestrator's**.
Nothing asks you to share a secret key — access is by granted permission only (see `02`, `07`).

Questions during setup: your orchestrator should follow the "If this fails / Do not continue until"
notes in each doc and tell you plainly if something is missing.
