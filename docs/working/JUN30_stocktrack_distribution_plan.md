# Stock-Track — Build / Test / Distribution Pipeline PLAN

> **Status: PLAN ONLY — no setup, no build, no deploy, nothing modified.** This document designs
> Stock-Track's OWN clean build → distribution → tester → dogfood pipeline so it graduates from the
> temporary chat-file-download to a proper app-tester flow. It **reuses the Blueprint Fitness (BP)
> distribution PATTERN** (read-only reference) but copies **none** of BP's Firebase project, App
> Distribution config, secrets, signing keys, tester records, or dogfood data store.
>
> Date: 2026-06-30. Author lane: Stock-Track (Brandon's App) distribution sub-orchestrator.
> Companion docs: `docs/working/JUN30_stocktrack_MVP_architecture_SPEC.md` (the product),
> `docs/MOCKED_VS_REAL.md` (slice-1 mock-vs-real), `docs/DECISIONS.md` (owner ledger).

---

## ⛔ HARD BOUNDARIES (restated — load-bearing)

These are non-negotiable and repeated at the top so they can never be lost:

1. **Never use Blueprint Fitness's Firebase project, App Distribution app, secrets, `FIREBASE_TOKEN`,
   service accounts, or signing keystore for Stock-Track.** BP's app id `1:677287134512:android:…`
   and its tester group `self` are BP's — Stock-Track gets its **own** everything.
2. **Never mix build artifacts** (APKs, AABs, build logs) between the two apps. Stock-Track artifacts
   live under the Stock-Track repo / its own clean-room, never under `C:\dev\bpcut` or the BP repo.
3. **Never mix tester records or dogfood state.** Stock-Track testers live in *Brandon's* Firebase
   App Distribution; Stock-Track dogfood checklist items live in *Brandon's* data store — **never**
   BP's `mobileIssueReports` collection.
4. **Stock-Track has its own clean identity** (package id, name, icon, keystore, version counter,
   Firebase project, tester group) **and eventually its own build/distribution lane** that points
   only at Brandon's project (`firebase … --project <brandon-project>`, never BP's).

---

## 0. How to read this doc (point-form, for fast owner sign-off)

- **§1** — Pete's question 1: *Should Stock-Track get its own pipeline?* (Yes — designed below.)
- **§2** — Pete's question 2: map each BP pattern piece → Stock-Track's SEPARATE equivalent.
- **§3** — Pete's question 3: the **separate-identity checklist** (what's already set ✓ vs what to create).
- **§4** — Pete's question 4: is chat-file-download OK as the temporary transport? (Yes, temporary — with a stated expiry.)
- **§5** — Pete's question 5: what's REQUIRED to graduate — the ordered prerequisites.
- **§6** — Pete's question 6: the staged plan (Stage 0–3) with each stage's gate + owner action.
- **§7** — risks / things to watch.

> If you read one thing: **Stage 0 (file-download) is the stopgap we are on NOW. To graduate we need,
> in order: Brandon's own Firebase project → register the Android app (`com.stocktrack.app`) in it
> (this is what unlocks App Distribution) → a Stock-Track signing keystore → a small
> `stocktrack_ship` script that mirrors BP's clean-room cut but points only at Brandon's project.**
> None of it touches Blueprint Fitness.

---

## 1. Should Stock-Track get its own pipeline? — YES

**Recommendation: YES, design and build Stock-Track its own clean build/test/distribution pipeline.**

Rationale:
- **It's a separate product with a separate audience.** Stock-Track's testers (Pete, Brandon, later
  Brandon's installers) are not BP's tester group. They must not see BP builds and BP's tester (Pete's
  dogfood phone) must not be spammed with Stock-Track builds. A shared pipeline would cross-contaminate
  tester lists, release notes, and version counters.
- **Separation is already a hard project invariant** (`README.md`, `HANDOVER_NEXT_AI.md`): separate
  repo, separate source-of-truth, separate Firebase. A shared distribution pipeline would silently
  violate that invariant at the one place it matters most — the thing that puts code on a real device.
- **The BP pattern is proven and worth reusing** — the clean-room cut, the monotonic version counter,
  the asset guard, the one PASS/FAIL line, the auto-created dogfood checklist item. We reuse the
  **shape** of that pipeline; we instantiate it against Brandon's own infrastructure.
- **It's low-cost to stand up.** Firebase App Distribution is free; a debug/release keystore is a
  one-time `keytool` command; the ship script is ~100 lines mirroring `deploy_remote.ps1` minus BP's
  asset/version complexity (Stock-Track has far simpler assets than BP's Today's-Groove webp saga).

The chat-file-download we used for the first mock APK was the right call to get look-and-feel onto a
phone fast (frontend-first, no Firebase gate). It is a **stopgap, not the pipeline** — see §4.

---

## 2. Reuse the BP PATTERN without sharing secrets/config — piece-by-piece map

The BP distribution pattern (read-only sources:
`/mnt/c/dev/blueprint-fitness-app/.claude/skills/ship-apk/SKILL.md`,
`docs/workflows_established/Build_Deploy_APK/cut_bpcut.ps1`,
`…/deploy_remote.ps1`,
`docs/workflows_established/Agent_Coordination/chat.js --build`) decomposes into these reusable
**pattern pieces**. Each maps to a Stock-Track-OWN equivalent — same shape, different (Brandon's)
identity:

| # | BP pattern piece | What it does in BP | Stock-Track's SEPARATE equivalent | Copy config/secrets? |
|---|---|---|---|---|
| P1 | **Clean-room cut** (`cut_bpcut.ps1` → `C:\dev\bpcut` linked worktree, reset to local HEAD) | Builds from a disposable clean copy so the dirty dev tree never ships; deploy-only, no push | **Optional, later.** Stock-Track can build directly from the repo for now (the dev tree IS clean — single lane). Adopt a clean-room only if multiple lanes start sharing the tree. | **No.** Pattern (build-from-clean) only. |
| P2 | **Monotonic version counter** (live build +1; MAX of counter / deploy logs / build commits; the "1.0(184) downgrade" guard) | Guarantees every shipped build's versionCode > the last one on the tester's phone | **Stock-Track's own counter**, seeded at its own `versionCode` (currently `1`, from `version: 1.0.0+1`). Independent integer line, never shares BP's 4xx series. | **No.** Pattern only. |
| P3 | **Build step** (`flutter build apk`) | Produces the binary | Same command, `flutter build apk` in the Stock-Track repo. (Debug-signed now; release-signed once the keystore exists — §3.) | **No.** |
| P4 | **Asset-drift guard** (`cut_asset_guard.ps1` — pubspec asset-sync + post-build APK assert) | Stops BP's gitignored `today_groove` webps shipping absent (the 3-day blank-image bug) | **Skip initially.** Stock-Track's slice-1 assets are simple/tracked (no gitignored media batches). Add an equivalent guard only if/when Stock-Track introduces gitignored bundled media. | **No.** Pattern, only if needed. |
| P5 | **App Distribution upload** (`firebase appdistribution:distribute <apk> --app <BP-app-id> --groups self`) | Uploads + distributes to the tester group | `firebase appdistribution:distribute <apk> --app <BRANDON-app-id> --groups <stocktrack-group> --project <brandon-project>` | **NO — this is the critical one.** Brandon's app id + project + group, never BP's `1:677287134512:…` / `self`. |
| P6 | **Tester group** (BP's `self` group = Pete's phone) | The distribution audience | **Stock-Track's own group** (e.g. `stocktrack-testers`) in Brandon's project: Pete + Brandon. | **No.** Brandon's project's own group. |
| P7 | **Auth** (`FIREBASE_TOKEN` env var or stored `firebase login`) | Lets the CLI upload non-interactively | Brandon's own Firebase auth — a CLI login on Brandon's project, or a CI token scoped to Brandon's project. **Never BP's `FIREBASE_TOKEN`.** | **NO.** |
| P8 | **One PASS/FAIL result line** (`CUT RESULT: PASS 1.0(N) … uploaded NEW`) | Agent-first output contract: one unambiguous line, no false-green | Mirror the contract: `STOCKTRACK SHIP RESULT: PASS 1.0(N) | <MB> | uploaded NEW` / `FAIL: <reason>`. Reuse the *contract*, not BP's parser internals. | **No.** Pattern only. |
| P9 | **Dogfood check-item** (`chat.js --build` → posts a chat msg AND auto-creates a `mobileIssueReports` doc = a verify-checklist item in Pete's in-app panel) | Every announced build becomes a "did you verify it?" item | **Stock-Track's own** lightweight checklist, in its OWN data store (Brandon's Firestore once it exists, or a local checklist file in Stage 2). **Never** BP's `mobileIssueReports`. | **NO — never BP's collection.** |
| P10 | **Release notes from last commit** (`[branch @ sha] subject`) | Auto-labels each build | Same pattern, generated from Stock-Track's repo git log. | **No.** |
| P11 | **Ship skill / runbook** (BP's `ship-apk` SKILL.md = one command, read one line, notify) | Encodes the procedure so it's one command, not a fiddly hand-cut | A short Stock-Track ship runbook (a few lines in this repo) once the script exists. | **No.** Pattern only. |

**Net:** we copy the **shape** (P1–P4, P8, P10–P11 = pure pattern), and we re-instantiate the
infrastructure-bound pieces (P5–P7, P9) entirely inside **Brandon's own** project. The one line that
must never be copied verbatim is BP's `--app 1:677287134512:android:…` / `--groups self` /
`FIREBASE_TOKEN` — those are replaced by Brandon's app id, group, project, and auth.

---

## 3. What must be SEPARATE — the separate-identity checklist (set ✓ vs to-create)

| Identity piece | BP value (do NOT reuse) | Stock-Track status | Action to create |
|---|---|---|---|
| **Package / application ID** | `io.bcd.blueprint…` (BP) | ✅ **SET** — `applicationId = "com.stocktrack.app"` (`android/app/build.gradle.kts:24`); namespace `com.stocktrack.stock_track` | None — already clean + distinct. |
| **App name** | "Blueprint Fitness" | ✅ **SET** — Stock-Track / "stock_track" | None (cosmetic label polish optional). |
| **App icon** | BP icon | ❌ **TO CREATE** — currently the default Flutter launcher icon | Design a Stock-Track icon → wire via `flutter_launcher_icons` (a design task, not a pipeline task). Non-blocking for tester distribution; do before any external/public build. |
| **Firebase project** | BP's `blueprintfitnesssubscriptions` / app `1:677287134512:…` | ❌ **TO CREATE** — none yet (frontend-first, no Firebase) | **Brandon creates his OWN Firebase project** (his Google account + billing). This is the gate for both cloud data AND App Distribution. |
| **App Distribution app** | BP's App Distribution app + group `self` | ❌ **TO CREATE** — depends on the Firebase project above | Register the Android app `com.stocktrack.app` inside Brandon's Firebase project → that registration is what *enables* App Distribution for Stock-Track. (App Distribution is a Firebase feature → it lives in Brandon's project, same gate as the cloud build.) |
| **Signing keystore** | BP's release keystore (long-lead, permanent, BP-owned) | ⚠️ **DEBUG-SIGNED ONLY** — `release { signingConfig = signingConfigs.getByName("debug") }` (`build.gradle.kts:34-37`, with the TODO); no `key.properties`, no `.keystore` | **Debug-signed is FINE for now** (internal tester dogfood). For a real release build, create a **Stock-Track keystore** (Brandon's own) via `keytool -genkey -v -keystore stocktrack-release.keystore -alias stocktrack -keyalg RSA -keysize 2048 -validity 10000`, store the password in a gitignored `android/key.properties`, and wire `signingConfigs.release` to it. Keystore is **long-lead + permanent** — generate deliberately, back it up off-machine, **never commit it**. |
| **Versioning / build numbers** | BP's `1.0(4xx)` series (counter in `bpcut`) | ✅ **SEEDED** — `version: 1.0.0+1` (`pubspec.yaml:19`) → versionCode `1` | Stock-Track runs its **own** counter from `1`, incremented per ship. Fully independent of BP's 4xx line — they never share a counter. |
| **Tester group** | BP's `self` (Pete's phone) | ❌ **TO CREATE** — depends on Brandon's App Distribution | Create a Stock-Track group (e.g. `stocktrack-testers`) in Brandon's project; add Pete + Brandon. Distinct from BP's `self`. |
| **Dogfood checklist / reporting** | BP's `mobileIssueReports` Firestore collection (BP project) | ❌ **TO CREATE** — none yet | Stock-Track's **own** dogfood checklist in its **own** data store (Brandon's Firestore once live, or a local checklist in the interim). Reuse the BP check-item *pattern* (announce build → auto-create a verify item) but **never** write to BP's `mobileIssueReports`. |
| **CLI auth / token** | BP's `FIREBASE_TOKEN` / stored login | ❌ **TO CREATE** — n/a yet | Brandon's own `firebase login` / a token scoped to **Brandon's** project. Never BP's token. |

**Summary — already set ✓:** package/application ID (`com.stocktrack.app`), app name, version seed
(`1.0.0+1`). **To create ❌/⚠️:** app icon (design task), Brandon's Firebase project, the registered
App-Distribution app, a Stock-Track signing keystore (debug-signed is fine until release), the tester
group, the dogfood checklist data store, and Brandon's CLI auth.

---

## 4. Is chat-file-download acceptable as the temporary first-mock transport? — YES, temporary only

**Recommendation: YES — it is acceptable as the STOPGAP for the first mock build(s), and it is the
right call to get look-and-feel on a phone before any Firebase gate.** Slice 1 (86 MB debug APK) was
delivered this way and that was correct.

**When it STOPS being acceptable (the expiry conditions — any one of these ends the stopgap):**
- **As soon as there is more than one tester** (the moment Brandon — not just Pete — needs the build).
  A file link doesn't manage a tester list, install instructions, or update notifications.
- **As soon as builds become iterative** (more than the occasional one-off). Manually re-sending links
  doesn't scale, gives no install-history, and no "is this newer than what's on my phone?" guarantee
  (no monotonic version surface to the tester).
- **The moment Firebase lands** (Stage 1). Once Brandon's project + App-Distribution app exist, App
  Distribution is strictly better and free — there's no reason to keep file-download.
- **Never for a real/release-signed or external build.** File-download is internal-debug-APK only.

So: **acceptable for Stage 0 (now), retired at Stage 2 when the proper App-Distribution pipeline goes
live.** Treat every file-download build as "throwaway transport for a look-and-feel mock," not a
release channel.

---

## 5. What's REQUIRED to graduate — ordered prerequisites

To move from Stage 0 (file-download) to the proper tester pipeline, in **this order** (each gates the
next):

1. **Brandon's OWN Firebase project exists.** Brandon creates it under his Google account/billing
   (own project id, own console). *Owner/Brandon action.* — This is the root gate; both cloud data
   (the eventual `FirebaseInventoryRepository` swap) and App Distribution hang off it.
2. **Register the Android app in Brandon's project.** Add `com.stocktrack.app` as an Android app in
   the Firebase console → generates Brandon's `google-services.json` and, crucially, **gives an App
   Distribution app id** (`1:<brandon-sender>:android:<hash>`). *This registration is what unlocks
   App Distribution for Stock-Track.* (For App Distribution alone you do NOT need to wire
   `firebase_core` into the app — registering the app + the APK is enough. The `google-services.json`
   / `firebase_core` wiring is the separate "go-live with real cloud data" step from
   `MOCKED_VS_REAL.md §4`.)
3. **A Stock-Track signing keystore.** Debug-signed APKs distribute fine to internal testers, so this
   is **only required for a release-signed build** — but it's long-lead + permanent, so generate it
   deliberately and back it up. `keytool -genkey -v -keystore stocktrack-release.keystore -alias
   stocktrack -keyalg RSA -keysize 2048 -validity 10000`; reference it from a **gitignored**
   `android/key.properties`; wire `signingConfigs.release` in `build.gradle.kts` (replace the
   debug-signing TODO). **Never commit the keystore or `key.properties`.** *Owner/Brandon action +
   one code wire-up.*
4. **A Stock-Track ship script** — a small `stocktrack_ship.ps1` (or `.sh`) that mirrors the bpcut
   pattern but points **only at Brandon's project**:
   - build: `flutter build apk` (`--release` once the keystore is wired; `--debug` until then),
   - read the last commit for release notes (`[branch @ sha] subject`),
   - bump/set the Stock-Track versionCode (its own counter, live+1),
   - distribute: `firebase appdistribution:distribute <apk> --app <BRANDON-app-id> --groups
     <stocktrack-group> --project <brandon-project> --release-notes "<notes>"`,
   - emit ONE agent-first line: `STOCKTRACK SHIP RESULT: PASS 1.0(N) | <MB> | uploaded NEW` or
     `FAIL: <reason>`.
   - **The firebase CLI MUST target Brandon's project** — pass `--project <brandon-project>` (or run
     in a dir with Brandon's `.firebaserc`), never BP's. The `--app` id must be Brandon's. This is the
     single most important guardrail in the script.
5. **A Stock-Track tester group + testers.** Create `stocktrack-testers` in Brandon's App
   Distribution console; add Pete + Brandon. *Owner/Brandon action.*
6. **(Optional, with Firebase live) the dogfood checklist** — Stock-Track's own verify-checklist,
   written to **Brandon's** data store, mirroring the BP `--build` check-item pattern. Never BP's
   `mobileIssueReports`.

**Hard CLI guardrail (restate):** every `firebase` invocation in the Stock-Track lane carries
`--project <brandon-project>` and `--app <brandon-app-id>`. A Stock-Track ship must be structurally
incapable of uploading to BP's project — pin the project explicitly, never rely on an ambient default.

---

## 6. Staged plan — Stage 0 → 3 (each with its gate + owner action)

> Mirrors the team's "spec → confirm → build → prove on-device" discipline. Each stage gates the next.

### Stage 0 — Mock APK via file-download (NOW — done, stopgap)
- **What:** `flutter build apk --debug` in the Stock-Track repo → 86 MB debug APK → delivered to
  Pete's phone via a chat file-download link (done for slice 1, commit `e741ed2`). Mock/local data,
  no Firebase, debug-signed.
- **Gate:** none beyond "it builds + installs + opens." Look-and-feel only.
- **Owner action:** Pete dogfoods the mock on-device (in progress).
- **Status:** ✅ DONE. Stopgap transport — see §4 for when it expires.

### Stage 1 — Brandon's Firebase + app registered + keystore
- **What:** Brandon creates his own Firebase project; register `com.stocktrack.app` in it (→ App
  Distribution app id + `google-services.json`); generate the Stock-Track signing keystore (or
  consciously defer to debug-signing for now). **No new app behavior** — this is infrastructure.
- **Gate:** Brandon's project exists; the Android app is registered; an App Distribution app id is in
  hand; keystore generated + backed up off-machine (or "debug-sign for now" explicitly chosen).
- **Owner action:** **Brandon** (his Google account/billing) creates the project + registers the app
  + (optionally) generates the keystore. This is the human-owned gate — an agent cannot create
  Brandon's Google project.
- **Status:** ❌ NOT STARTED (frontend-first; no Firebase yet by design).

### Stage 2 — The Stock-Track ship script + first App-Distribution build
- **What:** Author `stocktrack_ship.ps1` (§5.4) pointed at Brandon's project; run it to produce the
  first App-Distribution build to the `stocktrack-testers` group. Create the tester group + add Pete +
  Brandon. **Retire the file-download transport** (§4).
- **Gate:** one `STOCKTRACK SHIP RESULT: PASS …` line; the build appears in Brandon's App Distribution
  console; Pete + Brandon receive it via the App-Distribution tester invite and install it on-device.
- **Owner action:** Brandon accepts the tester invite (one-time); Pete + Brandon dogfood from the
  proper channel.
- **Status:** ❌ NOT STARTED (gated on Stage 1).

### Stage 3 — Stock-Track's own dogfood / reporting
- **What:** Stand up Stock-Track's own dogfood checklist + reporting, mirroring BP's `--build`
  check-item pattern, written to **Brandon's** data store (Brandon's Firestore once the cloud swap
  lands, or a local checklist in the interim). Optionally a small "announce build → auto-create verify
  item" wrapper for the Stock-Track lane.
- **Gate:** announcing a Stock-Track build auto-creates a verify item in Stock-Track's own store; a
  tester can mark it verified. **Zero reads/writes to BP's `mobileIssueReports`.**
- **Owner action:** Pete/Brandon use the Stock-Track checklist to track on-device verification.
- **Status:** ❌ NOT STARTED (gated on Stage 1, naturally follows the Firebase swap).

**Stage dependency line:** Stage 0 (done) → Stage 1 (Brandon's Firebase + app + keystore, owner-gated)
→ Stage 2 (ship script + first App-Dist build, retires file-download) → Stage 3 (own dogfood store).
Stage 1 is the single human-owned bottleneck; Stages 2–3 are agent-executable once Stage 1 lands.

---

## 7. Risks / things to watch (facts vs to-confirm)

- **(guardrail, load-bearing)** The ship script must pin `--project <brandon-project>` + `--app
  <brandon-app-id>` on every firebase call. A missing/ambient default could, in theory, target BP's
  project — structurally prevent it by always passing Brandon's project explicitly. (This is the one
  failure that would violate the separation invariant.)
- **(fact)** App Distribution does NOT require wiring `firebase_core` into the app — registering the
  app + uploading the APK is enough. The full `google-services.json` / `firebase_core` wiring is the
  separate "real cloud data" step (`MOCKED_VS_REAL.md §4`), which can land independently of the tester
  pipeline. So Stage 2 (tester pipeline) does NOT block on the cloud-data swap.
- **(fact)** Debug-signed APKs distribute fine to internal testers via App Distribution — the keystore
  is only strictly required for a release-signed/external build. Don't let "we need a keystore" block
  Stage 2 internal dogfooding.
- **(to-confirm, owner)** Whether Brandon wants a release-signed build now (needs the keystore +
  off-machine backup) or is fine with debug-signed internal dogfood until closer to a real release.
- **(to-confirm, owner)** The Stock-Track tester group name + initial tester list (proposed:
  `stocktrack-testers` = Pete + Brandon).
- **(permanence)** The keystore is long-lead + permanent (lose it and you can't update the same app
  listing later). Generate deliberately, back up off-machine, never commit. Same discipline BP applies
  to its keystore — but a SEPARATE keystore.
- **(fact)** This plan writes NO code, creates NO Firebase project, generates NO keystore, ships
  NOTHING. It is the design only. Stages 1–3 are gated owner/agent actions to be executed later on
  explicit go.

---

## Appendix A — BP pattern sources read (read-only, for the PATTERN only)
| BP source (read-only) | Pattern extracted |
|---|---|
| `.claude/skills/ship-apk/SKILL.md` | One-command ship, read-one-line, notify-on-PASS; clean-room/no-push discipline |
| `docs/workflows_established/Build_Deploy_APK/cut_bpcut.ps1` | Clean-room cut, monotonic version counter (+1, MAX-of-signals downgrade guard), asset guard, one PASS/FAIL line |
| `docs/workflows_established/Build_Deploy_APK/deploy_remote.ps1` | Dirty-tree guard → release notes from commit → `flutter build apk` → `firebase appdistribution:distribute --app … --groups self` → config restore |
| `docs/workflows_established/Agent_Coordination/chat.js` (`--build`) | Announce build → auto-create a dogfood check-item (`mobileIssueReports`) = a verify-checklist entry |

**Copied from BP: pattern/shape only. Copied from BP: ZERO config, secrets, project ids, app ids,
tokens, keystores, tester records, or dogfood data.**
