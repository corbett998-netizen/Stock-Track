# Stock-Track — HARNESS-PORT Implementation PLAN (prove the reusable owner/operator harness in a 2nd app)

> **Status: PLAN ONLY. Nothing built, no code, no Firebase change, no APK, no BP file touched.**
> This answers Pete's 7 questions and defines the smallest slice that proves the concept.
> Date: 2026-06-30/07-01. Author lane: Stock-Track harness-port planning (a7c2a6b2).
>
> **THE PIVOT (locked, Pete):** the goal is NO LONGER "a Stock-Track app that opens," and it is NOT
> App Distribution. The goal is to **prove the Blueprint-Fitness owner/operator HARNESS itself runs
> inside a second app (Stock-Track) and lets the owner work through it** — in-app orchestrator chat,
> bug/report flow, dogfood controls, owner report queue, dev-status surface, the chat action-buttons
> that make it a command center, plus the minimal backend so the orchestrator can actually
> READ/RESPOND through Stock-Track. Pinned to **Brandon's own Firebase `easy-stock-track`** (NOT
> Blueprint). **Mock inventory data is fine.** App Distribution de-prioritized — **direct APK is fine.**
>
> **Acceptance test:** "I open Stock-Track and can use the harness-style owner controls / chat /
> reporting / dogfood flow in that app, proving the reusable harness concept outside Blueprint Fitness."
>
> Builds ON (does not restart): `docs/working/JUN30_stocktrack_harness_plan.md` (the owner-comms plan),
> and BP's `docs/working/JUN30_harness_generalization_analysis.md` + `JUN30_harness_stageA_*` (which
> already made the in-app harness **config-driven** — the big enabler, see §0).

---

## ⛔ HARD GUARDRAILS (restated — load-bearing)

1. **Everything pins to `easy-stock-track`.** Never BP's Firebase project
   (`blueprintfitnesssubscriptions`), never BP's service-account, never BP's UID
   (`<owner-reference-app-test-uid-redacted>`), never BP's collections/bucket/App-Dist id.
2. **Permissions, never a shared key/token.** To let the orchestrator reach Brandon's project, Brandon
   grants an *identity* IAM access — he never emails/commits a service-account key or password (Pete's
   security rule; already the decided path in `FOR_BRANDON_enable_tester_pipeline.md`).
3. **Reuse the PATTERN, re-instantiate the INFRA.** Copy the harness *shape* (already config-driven);
   every project-specific value comes from a Stock-Track `project.config.json`, never a BP literal.
4. **The port must not drag BP into Stock-Track** — no BP identifiers, collections, creds, or
   BP-coupled Dart imports survive the copy (§Q7).

---

## 0. What changed since the last harness plan — and why the port is now EASY

Two facts reshape the earlier plan:

- **(fact) Brandon's Firebase already EXISTS and the app is already wired to it.** `easy-stock-track`
  is live: `android/app/google-services.json` is in the repo, `com.stocktrack.app`, bucket
  `easy-stock-track.firebasestorage.app`, and `main.dart` already calls `Firebase.initializeApp()`.
  The earlier plan treated "Brandon creates his Firebase project" as the big human gate — **that gate
  is already cleared.** What's still off: Firestore Database not enabled, Auth not enabled,
  `cloud_firestore`/`firebase_auth` not yet dependencies, no security rules, and (critically) **no
  admin access from this machine** (§Q3).
- **(fact) BP's in-app harness is ALREADY config-driven** (Stage-A, done against BP). The in-app chat
  (`lib/features/dev/chat/**`, 25 modules) and report queue (`lib/features/dev/report_queue/**`, 12
  modules) read a generated `lib/harness/harness_config.g.dart` (referenced 27×) for every
  collection/doc name, the owner-role, and the push presentation. The owner UID is **not** hardcoded —
  it's the runtime Firebase-Auth uid. **So retargeting the in-app surfaces to Stock-Track is mostly
  "regenerate the config from a Stock-Track `project.config.json`," not a rewrite.**

Net: the port is now **~80% clean copy + config, ~20% thin-seam edits** (strip 5-6 BP-coupled imports),
plus a small Stock-Track-pinned orchestrator script for the reply side.

---

## Q1. What parts of the BP harness can be safely reused NOW (config vs rewrite)

The harness inventory + how each ports. **Config-driven = regenerate a value; Thin-seam = swap one
injection point; Rewrite/strip = replace a BP dependency.**

| Harness surface | BP source (read-only) | Ports how | Verdict for slice 1 |
|---|---|---|---|
| **In-app orchestrator CHAT (text)** | `lib/features/dev/chat/**` (~4,900 lines, 25 modules) + `orchestrator_chat_screen.dart` | Clean-copy the modules; **regenerate `HarnessConfig`** from Stock-Track's `project.config.json` (collection/doc names, owner-role='brandon', push). Strip 5 BP imports (below). | ✅ **REUSE (core of the slice)** |
| **Chat Firestore seam** | `chat/services/chat_repository.dart` — `orchestratorChat/{uid}/messages`, poke bump | The one portability seam; keep as-is, retarget via config + a `ChatRepository` interface (Mock → Firebase, mirroring Stock-Track's existing repo seam). | ✅ REUSE |
| **Chat action-buttons** | `chat_header.dart` — 5 buttons: Stream Colours · Workflow Dashboard · Copy Full Context · Copy Recent · Copy Work-Area | Buttons are BP-multi-lane workflow tooling. Keep only a **minimal** header (send/attach/refresh) for slice 1; the 5 export/dashboard buttons are DEFER (§Q2). | ⚠️ REUSE the composer, DEFER the 5 buttons |
| **Report CAPTURE (file a bug)** | `lib/features/mobile_testing/**` (14 modules) — draggable FAB, `mobile_issue_report_screen`, `screenshot_upload_service`, `mobile_issue_reporter_service` | Port the FAB + report screen + screenshot upload; write to a Stock-Track reports collection. **Strip** `route_region_classifier` + `current_route_tracker` (BP-route-coupled) and the voice button. | ✅ REUSE (text + 1 screenshot) |
| **REPORT QUEUE (owner reads/triages own reports)** | `lib/features/dev/report_queue/**` (~2,025 lines, 12 modules) | Clean-copy; already `HarnessConfig.reportsCollection`-driven. Owner actions (comment / status / triage Execute-or-Discuss / flag / resolve / poke) all port. Strip `IntakeCardStyling` + `AuthService` seam. | ✅ REUSE |
| **Poke mechanism** | `system/orchestratorPoke` bumped on every owner write | Same doc in easy-stock-track; the message IS the wake. | ✅ REUSE |
| **Dev-gating + entry** | `!kReleaseMode` gate; entry via app drawer + FABs | Wire the same gate into Stock-Track's nav shell (`core/navigation`) + a dev drawer/FAB. | ✅ REUSE |
| **MIC / VOICE dictation** | `chat_voice_controller.dart` + `bug_report_voice_service` + `packages/bp_voice` (offline **sherpa-onnx**) | Heavy subsystem (a whole local package + shared draft singleton). The phone's OS keyboard already gives free dictation. | ⛔ **DEFER (§Q2)** |
| **Dev-status / DASHBOARD** | `workflow_context_service.dart` + `workflow_dashboard_sheet.dart` reads `system/workflowContext` | Nice status projection, but it's a multi-lane feature; a single-lane Stock-Track proof doesn't need it. Keep a tiny "agents engaged / last build" line at most. | ⚠️ DEFER most (§Q2) |
| **Vision / agent-status projections** | `system/vision`, `system/agentStatus` publishers | Not consumed by the core loop; overkill for the proof. | ⛔ DEFER |

**Config-vs-rewrite summary:**
- **Pure config (regenerate, ~0 code):** every collection/doc name, owner-role, push title/channel/route
  — all already flow from `project.config.json` → `harness_config.g.dart`.
- **Runtime, no change:** the owner UID (it's the signed-in Firebase-Auth uid; wire anonymous Auth).
- **Thin-seam edits (the only real work, 5-6 points):**
  1. `IntakeCardStyling.primaryOrange` (accent, ~8 files) → Stock-Track theme accent (one constant / `Theme.of`).
  2. `AuthService.currentUser?.uid` → Stock-Track's Firebase Auth (anonymous) uid.
  3. `RouteRegionClassifier` + `CurrentRouteTracker` (area-tagging by BP screen) → **drop for slice 1**
     (write `area:'general'`); add a tiny Stock-Track route map later if wanted.
  4. Voice controller + `bp_voice` → **omit** (text-only).
  5. Repository interface: introduce `ChatRepository` / `ReportRepository` (Mock + Firebase impls),
     mirroring Stock-Track's existing `InventoryRepository` seam, so slice 1 can even run mock-first.

---

## Q2. What should be DEFERRED (not worth the first slice)

- **Voice/mic dictation** — the `bp_voice` offline (sherpa-onnx) package + shared bug-report voice
  service is a big port; OS keyboard dictation covers it for free. Text-only first.
- **The 4 chat export/dashboard buttons** (Stream Colours, Workflow Dashboard, Copy Full/Recent
  Context, Copy Work-Area) — these are BP **multi-lane** workflow tooling. A single-lane Stock-Track
  proof doesn't need them.
- **Message tagging / workflow lanes / stream colours** — same reason (BP has many parallel lanes;
  Stock-Track has one).
- **`system/workflowContext` dashboard, `system/vision`, `system/agentStatus` projections + their
  publishers** — status surfaces for a busy fleet; not needed to prove the harness runs.
- **Push / FCM notifications** — additive; the in-app live stream is enough for the proof.
- **Multiple/rich attachments** — allow ONE screenshot on a report for slice 1; defer doc-send, media
  galleries, on-device URL-minting niceties.
- **App Distribution delivery + a release keystore + the tester group** — direct APK is fine (§Q4).
- **Route-region area tagging** — cosmetic categorization; drop for slice 1.

---

## Q3. Backend collections/config needed in Brandon's Firebase — AND the real dependency

### Q3a. Collections/config to provision in `easy-stock-track` (mirror BP, separate project)

```
orchestratorChat/<brandon-or-anon-uid>/messages/{auto} = {
  role: 'brandon' | 'orchestrator',
  text, createdAt: serverTimestamp(),
  via: 'text' | 'image',            // 'voice' deferred
  attachments?: [ { path, ... } ]   // one screenshot, later
}
system/orchestratorPoke = { pokedAt: serverTimestamp(), note, by: <uid> }
stockIssueReports/{auto} = {        // Stock-Track's OWN queue — NEVER BP's mobileIssueReports
  userId: <uid>, note, screenshots?: [storagePaths],
  status, triageDecision?, comments?[], createdAt, ...
}
// Storage (for the one screenshot):  stockIssueReports/<uid>/screenshots/**   (owner-read rule)
// Security rules: scope every read/write to request.auth.uid == <owner-uid>, in easy-stock-track's firestore.rules + storage.rules
```
All in **easy-stock-track**, keyed by **Stock-Track's** anon-Auth UID, never BP's. Collection names can
even stay identical to BP's (`orchestratorChat`, `system/orchestratorPoke`) — they can never collide
because it's a **different Firebase project**. The reports collection is renamed to `stockIssueReports`
purely to keep BP's tooling from ever pointing at it by accident.

To make the app CLIENT write these, three one-time Brandon-side enables (project already exists):
1. **Enable Firestore Database** (console → Firestore → Create, test/locked mode + region).
2. **Enable Anonymous Auth** (console → Authentication → Sign-in method → Anonymous) — gives the app a
   UID to key the thread + scope rules, with no login UX.
3. **Deploy the harness security rules** (the `firestore.rules` + `storage.rules` above).

Steps 1-2 are console-only (~5 min). Step 3 can be CLI once an identity has access.

### Q3b. ⚠️ THE REAL DEPENDENCY — the ORCHESTRATOR cannot reach easy-stock-track (and why)

**(fact)** The app **client** already reaches easy-stock-track (google-services.json + client SDK,
subject to rules) — so the *app* can read/write the harness collections with only the three enables
above. **But the ORCHESTRATOR is a different animal:** it uses the Firebase **Admin SDK**, which needs
project credentials. On this machine the *only* Firebase auth is Pete's Google account, and (verified,
per `STOCKTRACK_SHIP_RUNBOOK.md` + `DECISIONS.md`) **it can see ONLY `blueprintfitnesssubscriptions` —
it has NO access to `easy-stock-track`.** There is **no admin service-account for easy-stock-track
anywhere on disk** (only BP's). So the orchestrator literally cannot READ Brandon's chat thread or
RESPOND into it until Brandon grants access.

**The concrete mechanism (permissions-only, no shared key — Pete's rule):**
- **Brandon grants an *identity* IAM access on `easy-stock-track`** — recommend a dedicated ops Google
  account (or Pete's) added as an IAM member with `roles/datastore.user` (Firestore read/write) +
  a Storage object role (for report screenshots). **No key file leaves Brandon's project.** This is
  exactly the decided path in `FOR_BRANDON_enable_tester_pipeline.md` ("grant Pete via IAM").
- **The orchestrator authenticates via Application Default Credentials (ADC), not a downloaded SA
  key:** run `gcloud auth application-default login` as that granted identity, then the Stock-Track
  orchestrator script inits the Admin SDK with `admin.credential.applicationDefault()` **and an
  explicit `projectId: 'easy-stock-track'` pin** (from Stock-Track's `project.config.json`).
  - This is the one **deviation from BP's pattern** worth calling out: BP's `chat.js` loads a
    `service-account.json` **key file** and derives the project from `sa.project_id`. For Stock-Track,
    prefer **ADC + IAM grant** so nothing secret is ever shared — a strictly cleaner mechanism that
    honors "permissions, never a shared key."
- **What Brandon must do (one short task, project already exists):** enable Firestore + Anonymous Auth,
  deploy the two rules files, and add the ops identity as an IAM member with the two roles. That's it —
  no keys, no passwords, no tokens shared.

**Bottom line for Q3:** the app side needs a ~5-10 min Brandon console task (Firestore + Anonymous Auth
+ rules). The orchestrator-reply side additionally needs Brandon's **IAM grant to an ops identity**
(permissions-only). Both are small, and neither shares a secret.

---

## Q4. Is App Distribution REQUIRED for this harness dogfood? — NO. Direct APK is enough.

**Clear answer: App Distribution is NOT required. A direct APK fully satisfies the harness dogfood.**
Separate the two things people conflate:

- **Build DELIVERY** (how the APK reaches the phone): App Distribution vs direct APK/sideload. For a
  proof that *you and the orchestrator* drive, **direct APK is fine** — it's Pete's stated preference,
  and it needs nothing from Brandon (App Distribution's tester-group + uploader-access is the current
  blocker in `STOCKTRACK_SHIP_RUNBOOK.md`, and it's **irrelevant to whether the harness works**).
- **Harness BACKEND** (what makes the harness actually function): the **Firestore backend in
  easy-stock-track** (chat/report persistence) and, for two-way, the orchestrator's IAM access. **This**
  is the real dependency — not delivery.

So: **do NOT gate the harness dogfood on App Distribution or Brandon's tester setup.** Build a direct
APK (`flutter build apk`, debug-signed) and sideload it to a test phone. App Distribution stays deferred
until Brandon wants a real external-tester pipeline — a separate, later track.

---

## Q5. What the FIRST testable Stock-Track harness APK includes (smallest slice that passes acceptance)

A dev-gated (`!kReleaseMode`) harness reachable from the Stock-Track drawer, pinned 100% to
easy-stock-track, delivered as a **direct APK**. Contents:

1. **In-app owner↔orchestrator CHAT (text-only)** — live Firestore stream of
   `orchestratorChat/<uid>/messages` in easy-stock-track; a minimal composer (type + send); bumps
   `system/orchestratorPoke` on send. Owner-role = `'brandon'` (Pete dogfoods as the stand-in owner).
2. **Report FLOW** — a "file a report" FAB/button → note (+ optional ONE screenshot to Storage) →
   writes `stockIssueReports`; **plus the REPORT QUEUE** screen where the owner reads/triages own
   reports (comment / status / Execute-or-Discuss / flag / resolve / poke). This half is a **complete
   owner loop client-side** — it works even before the orchestrator can reply.
3. **Anonymous Firebase Auth** — signs the app in so the UID keys the thread + scopes the rules.
4. **The orchestrator reply side** — a Stock-Track-pinned `stocktrack_chat.js` (`--read`/`--send`,
   ADC-based, `projectId: 'easy-stock-track'` pinned, BP-abort guard) so the orchestrator READS the
   owner's messages and REPLIES in-app, and `--build` drops a dogfood check-item. *(Requires the Q3b
   IAM grant — see the smallest-dependency ladder below for how slice 1 can land without waiting on it.)*
5. **Zero BP:** anti-leak scan green over Stock-Track's tree; the ops script aborts on any
   `blueprint`/`677287134512`/`io.bcd` token (the ship-script guard pattern, already proven).

**Smallest-dependency ladder (Pete's "less/no Brandon dependency for the very first slice" question):**

| Rung | What it proves | Brandon dependency | Orchestrator access? |
|---|---|---|---|
| **0 — mock-backed** | The harness **code ports** into Stock-Track, wires into its nav/theme, dev-gates, and the owner can **use** chat + report + queue against seeded in-memory data (via a `MockChatRepository`, mirroring `MockInventoryRepository`). | **NONE** | No |
| **1 — client-persisted** *(recommended first APK)* | Real persistence: owner's messages + reports **save to easy-stock-track**, survive restart, scoped to the anon UID; the **report round-trip is fully live** (file → Firestore → read/triage in queue). | Enable Firestore + Anonymous Auth + deploy rules (~5-10 min) | No (client writes directly) |
| **2 — full two-way** | The orchestrator **reads and replies** in-app; `--build` check-items appear. Completes Pete's stated goal. | + IAM grant to an ops identity (Q3b) | Yes (ADC + pin) |

**Recommendation:** target **Rung 1 as the first testable APK** (meaningful proof — real backend, real
report loop, owner controls usable — with only a tiny Brandon task and NO shared secret), and land
**Rung 2 immediately after** the IAM grant to make the chat two-way. Rung 0 is available as a
zero-dependency demo if we want to show the ported surfaces before Brandon touches anything.

---

## Q6. Proof brought back before calling it done (evidence-first, tied to the acceptance test)

Doctrine: a product-facing thing is proven by **running the real flow on-device**, never by a unit test.

1. **On-device run of the real flow (the acceptance test itself):** a screen recording / screenshots of
   opening the Stock-Track **direct APK** → dev drawer → **chat**: type + send a message, it appears →
   **report**: file one with a screenshot → it lands in the **report queue** → triage it (Execute /
   status / comment). This literally demonstrates "I open Stock-Track and can use the harness controls."
2. **Real-backend evidence:** the message + report docs present in **easy-stock-track** Firestore
   (read back by the orchestrator once IAM-granted, or shown via console) — proving persistence is in
   **Brandon's** project, not BP, and survives a restart.
3. **Two-way evidence (Rung 2):** the orchestrator posts a reply via `stocktrack_chat.js` and it renders
   in-app; a `--build` announcement creates a dogfood check-item the owner sees.
4. **Separation proof (see Q7):** the Stock-Track anti-leak scan = **0 hits**; a grep proving no
   `blueprintfitnesssubscriptions` / BP UID / BP service-account is reachable from Stock-Track config or
   scripts; the ops script's BP-abort guard demonstrated.
5. **Not-done-until:** any failure of 1-4 = not done. No "should work," no green-unit-test claim.

---

## Q7. Privacy/separation risks BP↔Stock-Track — and how each is BLOCKED

The overriding risk: porting the harness must NOT drag BP identifiers/collections/creds into Stock-Track,
and the two must never cross-write. Enumerated:

| # | Risk | Concrete BLOCK |
|---|---|---|
| R1 | **Ambient-credential footgun** — this machine's default Google auth resolves to BP; a Stock-Track script that forgets to pin could touch BP. | Every Stock-Track orchestrator script **pins `projectId: 'easy-stock-track'` explicitly** from Stock-Track's `project.config.json` + a **BP-abort guard** (abort on `blueprint` / `677287134512` / `io.bcd` / BP UID) — the exact guard already in `stocktrack_ship.sh`. Structurally incapable of reaching BP. |
| R2 | **Copying BP's `service-account.json`** into Stock-Track. | FORBIDDEN. Stock-Track uses **ADC + Brandon's IAM grant** (no key), or its own project's SA if ever minted — **never** BP's. `.gitignore` must exclude `service-account.json` / `.env` / `key.properties` (currently NOT listed in Stock-Track's `.gitignore` — **action item**). |
| R3 | **BP-coupled Dart imports riding along** in the ported surfaces (`IntakeCardStyling`, `RouteRegionClassifier`, `CurrentRouteTracker`, `AuthService`, `BugReportVoiceService`). These carry BP coupling (not secrets, but wrong-app). | Strip/replace all 5 on port (Q1 thin-seams). Then run a **Stock-Track-adapted `harness_antileak_scan.sh`** over Stock-Track's `lib/` — 0 hits gate. |
| R4 | **BP UID or collection literals** leaking into Stock-Track. | The in-app surfaces key by the **runtime anon UID** (no hardcoded UID) and read collection names from a **regenerated `harness_config.g.dart`** (from Stock-Track's config). No BP UID or literal is ever written. |
| R5 | **Writing Stock-Track data into BP (or vice-versa)** while one orchestrator drives both lanes. | Separate `project.config.json` per side, separate creds, explicit projectId pins, and the R1 guard. Reports go to `stockIssueReports` (distinct name) so BP's `mobileIssueReports` tooling can never point at it. |
| R6 | **Cross-repo secret/doc leak** — Stock-Track is a separate git repo (`github.com/corbett998-netizen/Stock-Track`). | Keep it separate; never commit any easy-stock-track SA/key/ADC. Add the R2 `.gitignore` lines before any backend wiring. |
| R7 | **BP push/FCM presentation** (channel `orchestrator_chat_channel`, title "Orchestrator") bleeding in. | Push is DEFERRED (Q2); if added later, its values come from Stock-Track's config, and are Stock-Track-branded. |

**The mechanical guarantee:** the same anti-leak discipline BP uses on itself — a
`harness_antileak_scan.sh` (Stock-Track pattern set) + the ship-script BP-abort guard + explicit
projectId pinning — is applied to Stock-Track's tree. Separation is *checked by a tool*, not asserted.

---

## Recommended lane/agent structure for the eventual BUILD (once Pete approves)

Keep it lean — this is **one bounded app port**, not a fleet. Recommend a small, sequenced structure:

- **1 × Stock-Track Harness BUILD lead** (owns the port end-to-end): scaffold `lib/features/dev/` in
  Stock-Track; introduce `ChatRepository` / `ReportRepository` seams (Mock + Firebase impls, mirroring
  the existing `InventoryRepository` seam); clean-copy chat + report_queue + report-capture; regenerate
  `harness_config.g.dart` from a Stock-Track `project.config.json`; strip the 5 BP couplings; wire
  anonymous Auth + the drawer/FAB dev-gate. Ships Rung 0 → Rung 1.
- **1 × Backend/config task** (same lead or a helper): author Stock-Track's `project.config.json`;
  write `stocktrack_chat.js` (ADC-based, projectId-pinned, BP-abort guard); author the `firestore.rules`
  + `storage.rules`; write the short "enable Firestore + Anonymous Auth + IAM grant" delta for Brandon
  (extends the existing `FOR_BRANDON_enable_tester_pipeline.md`). Enables Rung 2.
- **1 × Validator** (independent, per the internal-validation-gate SOP): runs the Q6 acceptance
  checklist on the built **direct APK** (opens Stock-Track, exercises each control on-device), runs the
  Q7 anti-leak scan + separation grep, and only then calls it proven. Independence is mechanical.
- **Main orchestrator** coordinates + surfaces the two owner-decisions (below); it does not execute the
  port itself.

**Sequence:** Rung 0 (mock, zero dependency — proves the port compiles + renders + is usable) → Brandon's
~10-min enable → Rung 1 (client-persisted, real proof) → Brandon's IAM grant → Rung 2 (two-way) →
Validator gate → Pete dogfoods the direct APK.

---

## Facts / Recommendations / Risks

**Facts (verified this session, read-only):**
- easy-stock-track is live + the Stock-Track client is wired to it (`google-services.json`,
  `com.stocktrack.app`, bucket `easy-stock-track.firebasestorage.app`, `Firebase.initializeApp()` in
  `main.dart`). Data is still all mock; no `cloud_firestore`/`firebase_auth` deps yet; no
  `lib/features/dev/`.
- BP's in-app harness is already config-driven: `lib/harness/harness_config.g.dart` (generated from
  `harness/project.config.json`) supplies collection/doc names, owner-role, push presentation; the
  in-app chat (25 modules) + report_queue (12 modules) reference it 27×. Owner UID is the runtime
  Firebase-Auth uid, not a literal.
- BP orchestrator comms (`chat.js`, `chat_send_doc.js`, `chat_send_image.js`) load `harness_config.js`
  for UID/collections but load `service-account.json` from a hardcoded path and derive the project from
  `sa.project_id`. Retargeting = a Stock-Track config + Stock-Track creds (ADC recommended).
- This machine's only Firebase auth (Pete's Google account) can see ONLY BP; it has **no access to
  easy-stock-track**, and no easy-stock-track service-account exists on disk (confirmed in
  `STOCKTRACK_SHIP_RUNBOOK.md` + `DECISIONS.md`).
- A Stock-Track direct-APK ship path already exists (`scripts/stocktrack_ship.sh`,
  `STOCKTRACK_SHIP_RUNBOOK.md`) — App-Distribution-oriented, currently BLOCKED-on-Brandon, and NOT
  needed for the harness to function (plain `flutter build apk` + sideload works).
- BP's voice is a local `packages/bp_voice` (offline sherpa-onnx) module + a shared bug-report voice
  service — a heavy subsystem.

**Recommendations:**
- **First testable APK = Rung 1** (client-persisted harness on easy-stock-track, mock inventory,
  direct APK). Land **Rung 2** (orchestrator two-way via ADC + IAM grant) right after. Rung 0 available
  as a zero-dependency demo.
- **Q4: direct APK — do not gate on App Distribution / Brandon's tester setup.**
- **Q3b: ADC + Brandon IAM grant** to an ops identity — permissions-only, no shared key (deviates from
  BP's SA-key pattern on purpose, strictly cleaner).
- **Defer** voice, the 4 export/dashboard chat buttons, tagging/lanes, dashboard/vision/agent-status
  projections, push, rich attachments, App Distribution.
- Fix Stock-Track `.gitignore` (add `service-account.json` / `.env` / `key.properties`) **before** any
  backend wiring.

**Risks:**
- **Ambient-credential footgun (R1)** — the single biggest separation risk; blocked by explicit
  projectId pinning + the BP-abort guard.
- **A mock chat is not a working channel** — Rung 0 proves the *port*, not the *channel*; don't mistake
  "the chat renders against fake messages" for "the harness works." Rung 1 is the honest first proof.
- **The orchestrator-reply loop truly depends on Brandon's IAM grant** — Rung 1 is designed so slice 1
  isn't blocked on it, but Pete's full stated goal (orchestrator READs/RESPONDs through Stock-Track)
  needs the grant.

**Owner-decisions needed (main orchestrator to surface):**
1. **Approve the Rung-1-first path** (client-persisted direct APK, then Rung 2 two-way)? Recommend YES.
2. **Name the ops identity** Brandon should IAM-grant on easy-stock-track (a dedicated ops Google
   account vs Pete's account), and confirm **ADC-not-a-key** as the orchestrator auth mechanism.
   Recommend a dedicated ops account + ADC.

---

### Appendix — sources read (read-only; no BP file modified)
BP harness: `lib/features/dev/chat/**` (25 modules) · `lib/features/dev/report_queue/**` (12) ·
`lib/features/mobile_testing/**` (14) · `packages/bp_voice/**` · `lib/harness/harness_config.g.dart` ·
`harness/{project.config.json,harness_config.js,harness_antileak_scan.sh}` ·
`docs/workflows_established/Agent_Coordination/{chat.js,chat_send_doc.js,chat_send_image.js}` ·
`.githooks/pre-commit`. BP plans: `JUN30_harness_generalization_analysis.md`,
`JUN30_harness_stageA_implementation_plan.md`, `JUN30_harness_stageA_EVIDENCE.md`. Stock-Track:
`lib/**`, `android/app/google-services.json`, `pubspec.yaml`, `main.dart`, and `docs/**`
(`DECISIONS.md`, `MOCKED_VS_REAL.md`, `JUN30_stocktrack_harness_plan.md`,
`JUN30_stocktrack_distribution_plan.md`, `JUN30_stocktrack_MVP_architecture_SPEC.md`,
`BRANDON_FIREBASE_SETUP.md`, `FOR_BRANDON_enable_tester_pipeline.md`, `STOCKTRACK_SHIP_RUNBOOK.md`,
`ORCHESTRATION_NOTES.md`).
