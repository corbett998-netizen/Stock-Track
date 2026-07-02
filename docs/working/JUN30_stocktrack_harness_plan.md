# Stock-Track — Owner-Comms / Dev-Harness PLAN

> **Status: PLAN ONLY — nothing built, no Firebase created, no collection written, no BP file touched.**
> This document designs **Stock-Track's OWN owner-comms + dev-harness path** so Brandon (a non-coder,
> like Pete) can operate his project the way Pete operates Blueprint Fitness: direct his orchestrator,
> get updates, attach files, approve decisions, and coordinate setup. It **reuses the Blueprint Fitness
> (BP) harness PATTERN** (read-only reference) and points it **only at Brandon's own infrastructure** —
> never BP's Firebase, secrets, storage, chat collections, report queue, dogfood store, or service
> accounts.
>
> Date: 2026-06-30. Author lane: Stock-Track owner-comms harness sub-orchestrator (a44fe78d).
> Companion docs: `docs/working/JUN30_stocktrack_distribution_plan.md` (the build/ship/dogfood
> PIPELINE — this doc is its comms-channel sibling, do not duplicate it), `JUN30_stocktrack_MVP_architecture_SPEC.md`
> (the product), `BRANDON_FIREBASE_SETUP.md` (the one unlock), `DECISIONS.md` (owner ledger),
> `MOCKED_VS_REAL.md` (slice-1 mock-vs-real).

---

## ⛔ HARD GUARDRAILS (restated up top — load-bearing, cannot be lost)

1. **Never use Blueprint Fitness's Firebase project, service accounts, secrets, `FIREBASE_TOKEN`,
   storage bucket, chat collections (`orchestratorChat/<pete-uid>`), report queue (`mobileIssueReports`),
   dogfood store, or signing keys for Stock-Track.** BP's project `blueprintfitnesssubscriptions`, BP's
   canonical UID `<owner-reference-app-test-uid-redacted>`, and BP's `service-account.json` are BP's. Stock-Track
   gets its **own** everything.
2. **Never mix Brandon's messages, dogfood reports, owner-decisions, or dev-state into BP** (and no BP
   data into Brandon's). Separate Firestore project, separate collections, separate registers, separate
   Node scripts, separate service account.
3. **Do not let the harness block the frontend shell.** The current frontend-first slice (mock data, no
   Firebase, file-download APK) ships and iterates **without** the harness. The harness is added on the
   Firebase track, never as a gate on look-and-feel work.
4. **A minimal doc/relay harness suffices for NOW — say so plainly.** Brandon is not self-driving the
   workflow yet (he is dogfooding look-and-feel; Pete relays his words). The full in-app chat is the
   destination, not the immediate requirement.
5. **Proper in-app chat REQUIRES Brandon's Firebase** (Firestore real-time + Auth). When that lands,
   **fold the harness collections + Storage rules into Brandon's Firebase onboarding** so the chat
   thread, `system/*` docs, the reports collection, and the `orchestratorChat/<uid>/**` Storage paths
   get provisioned in **Brandon's** project — one setup, not two.

---

## 0. How to read this doc (point-form, for fast owner sign-off)

- **TL;DR** (just below) — the recommendation in five lines.
- **§1** — Pete's Q1: does Stock-Track need an in-app orchestrator chat/dev harness like BP? (Yes.)
- **§2** — Pete's Q2: the minimum viable harness before Brandon self-drives.
- **§3** — Pete's Q3: reuse the BP PATTERN without sharing BP data/config/secrets — piece-by-piece map.
- **§4** — Pete's Q4: first harness FORM — in-app vs web/local tool vs terminal+doc vs STAGED (recommend).
- **§5** — Pete's Q5: backend — local/mock first? does in-app chat REQUIRE Brandon's Firebase?
  same-project-separate-collections vs isolated project? what collections/structures?
- **§6** — Pete's Q6: the SEPARATION checklist (status of each piece vs BP).
- **§7** — Pete's Q7: is the harness needed in the NEXT mock APK, or after Firebase/App-Dist? Safest sequence.
- **§8** — risks / things to watch.
- **Appendix A** — the BP PATTERN sources read (read-only, pattern only).

### TL;DR (the recommendation)

- **Yes**, Brandon needs the same owner↔orchestrator harness shape BP has — so a non-coder can run his
  own project from his phone.
- **Recommended first FORM = STAGED, landing on an in-app dev chat** (exactly BP's shape), because it
  lives where Brandon already is (his dogfood phone) and reuses Firestore real-time for free. **Do not**
  build a throwaway web/local chat tool.
- **Minimum viable harness (MVH)** = an in-app owner↔orchestrator **text chat** on Brandon's Firestore
  + a tiny orchestrator-side `stocktrack_chat.js` (Admin SDK, pinned to Brandon's project) + the poke
  doc + Brandon's Auth + the doc-registers (already exist).
- **Proper in-app chat REQUIRES Brandon's Firebase** (Firestore real-time + Auth). It is the **same one
  gate** as cloud data and App Distribution — so fold the harness into that single onboarding.
- **Recommended backend posture = Brandon's own Firebase project, SAME project, SEPARATE top-level
  collections** (`orchestratorChat`, `system`, a `stockIssueReports` queue) — NOT an isolated second
  project (that's pure overhead for a non-coder; the separation that matters is Brandon-vs-BP, which
  same-project already gives).
- **The next mock APK does NOT need the harness** and must not be blocked on it. The harness rides the
  Firebase/App-Distribution track. **Until Firebase lands, the honest interim is: doc-registers +
  Pete-relay + file-download APK** (the current state).

---

## 1. Does Stock-Track need an in-app orchestrator chat / dev harness like BP? — YES

**Recommendation: YES.** The owner intent is yes, and it is the right call.

Rationale:
- **Brandon is a non-coder, like Pete.** The entire reason BP's harness exists is so a non-coder can
  operate a software project end-to-end: see what's happening, direct the orchestrator in plain English,
  attach a screenshot/file, approve a decision, and coordinate setup — **without** touching a terminal,
  git, or Firebase console. Brandon needs the same affordances to run Stock-Track himself.
- **The owner↔orchestrator channel is the operating surface of the whole workflow.** BP's experience is
  that the durable registers (the orchestrator's memory) are necessary but **not sufficient** — the
  owner also needs a live, two-way channel on the device he already has. Telegram filled this first; BP
  has since moved it **in-app** (`orchestrator_chat_screen.dart`) precisely because the channel belongs
  where the product already is.
- **The doc-based half already exists for Stock-Track.** `DECISIONS.md` (the `AWAITING_PETE.md`-pattern
  ledger), `HANDOVER_NEXT_AI.md` (session-death survival), `ORCHESTRATION_NOTES.md`, and `working/` are
  in place. What's **missing** is the **Brandon-facing live channel** — the chat surface + the
  Firestore comms layer + the dogfood report loop. That is what this plan adds.

**Important nuance (who operates it):** in BP the owner (Pete) sits at the dogfood phone and drives the
orchestrator directly. For Stock-Track, **Brandon is the product owner who will drive it from his
phone**, while **Pete currently coordinates the build and relays for Brandon**. So the chat surface's
"owner" role is **Brandon** (`role: 'brandon'`), and during the interim Pete relays Brandon's words.
The harness must reach **Brandon wherever he is** — which is exactly why an in-app channel on his
dogfood build (delivered via App Distribution) is the right destination, not a tool that only runs on
the dev machine.

---

## 2. Minimum viable harness before Brandon starts using the project himself

"Starts using the project himself" = Brandon installs a build, drives the orchestrator in his own words,
and gets updates/decisions back — **without Pete hand-relaying every message.** The MVH is the smallest
thing that enables that.

**MVH (the must-haves):**
1. **An in-app owner↔orchestrator chat surface** (text-only), dev-gated, one thread — Brandon types,
   the orchestrator replies. (Port of BP's `orchestrator_chat_screen.dart` shape, adapted, in
   Stock-Track's own `lib/features/dev/chat/`.)
2. **Brandon's Firestore comms collection** `orchestratorChat/<brandon-uid>/messages` — the real-time
   two-way store (live snapshot listener on-device, Admin-SDK writes from the orchestrator).
3. **An orchestrator-side `stocktrack_chat.js`** (`--read` / `--send`) — a tiny Node script, Admin SDK,
   **pinned to Brandon's project + Brandon's service account + Brandon's UID** (the BP `chat.js` shape).
4. **The poke doc** `system/orchestratorPoke` — every Brandon message bumps it so the orchestrator loop
   wakes (the message IS the poke; no extra watcher). Pattern reuse, Brandon's project.
5. **Brandon's Firebase Auth** — signs Brandon in on his build so his UID keys the thread and the
   security rules can scope reads/writes to him.
6. **The doc-registers** — `DECISIONS.md` + `HANDOVER_NEXT_AI.md` (the orchestrator's durable memory).
   **Already done.**

**Deferred (layer on AFTER the MVH works — explicitly NOT required for first self-drive):**
- Attachments (send-doc / send-image) + the `orchestratorChat/<uid>/docs|media/**` Storage rules.
- The dogfood **report-queue** panel + its own reports collection (covered as Stage 3 of the
  distribution plan; the comms aspect is here).
- The `system/workflowContext` **dashboard projection** (build + workflows + staleness) and any
  `system/vision`.
- Push / FCM notifications.
- Message tagging / lanes / workflow routing (BP's later, heavier layer — almost certainly overkill for
  a single-lane project; revisit only if Stock-Track grows multiple parallel lanes).

**Honest floor (pre-Firebase interim, what's adequate RIGHT NOW):** `DECISIONS.md` + `HANDOVER` +
Pete-relay + file-download APK. This is sufficient **only while Brandon is dogfooding look-and-feel and
Pete relays.** The moment Brandon needs to self-direct, the MVH above (gated on his Firebase) is the
unlock.

---

## 3. Reuse the BP PATTERN without sharing BP data/config/secrets — piece-by-piece map

The BP owner-comms harness (read-only sources in Appendix A) decomposes into these reusable **pattern
pieces**. Each maps to a Stock-Track-OWN equivalent — same SHAPE, Brandon's identity/infra.

| # | BP pattern piece | What it is in BP | Stock-Track's SEPARATE equivalent | Copy config/secrets? |
|---|---|---|---|---|
| H1 | **In-app chat surface** — `orchestrator_chat_screen.dart` + `lib/features/dev/chat/` (models/services/controllers/widgets), dev-gated (`!kReleaseMode`) | Owner types/dictates; orchestrator replies; one thread | Port the SHAPE into Stock-Track's own `lib/features/dev/chat/`, dev-gated, dark theme (matches Stock-Track's existing `core/theme`). Drop BP-specific deps (RouteRegionClassifier, intake styling, voice). | **No.** Pattern/shape only — re-implement, don't import BP code. |
| H2 | **Firestore comms layer** — `ChatRepository` over `orchestratorChat/{uid}/messages` (live stream, newest-200, warm read) | The real-time two-way store | Same collection shape in **Brandon's** Firestore: `orchestratorChat/<brandon-uid>/messages`. Centralise in one repository class (portable seam). | **No.** Brandon's Firestore instance. |
| H3 | **Message schema** — `{role, text, createdAt: serverTimestamp(), via, area?, attachments?[], tags?[]}` | The doc shape | Same schema; `role: 'brandon' | 'orchestrator'`. `area`/`tags` optional (likely unused early). | **No.** Schema/shape only. |
| H4 | **Poke mechanism** — `system/orchestratorPoke` bumped on every owner write (`{pokedAt, note, by}`) | Wakes the orchestrator loop instantly | Same `system/orchestratorPoke` doc in **Brandon's** Firestore; the orchestrator loop for Stock-Track watches Brandon's poke. | **No.** Brandon's project. |
| H5 | **Orchestrator chat CLI** — `chat.js` (`--read`/`--send`/`--build`/`--media`), Admin SDK via BP's `service-account.json`, hardcoded BP UID, BP bucket | Lets the orchestrator read/reply outside the rules | **`stocktrack_chat.js`** with **Brandon's** service account, **Brandon's** project id, **Brandon's** UID, **Brandon's** bucket. Start with `--read`/`--send` only. | **NO — this is the critical one.** Brandon's `service-account.json` (gitignored), never BP's. |
| H6 | **Attachment senders** — `chat_send_doc.js` / `chat_send_image.js` upload to Storage `orchestratorChat/<uid>/docs|media/...`, write PATH-only, app mints owner URL on-device | Send Brandon a tappable file / inline image | Stock-Track equivalents on **Brandon's** Storage bucket, same PATH-only + on-device-mint pattern; needs the `orchestratorChat/<uid>/**` owner-read `storage.rules`. **Later** (deferred from MVH). | **No.** Brandon's bucket + rules. |
| H7 | **`system/*` projections** — `system/workflowContext` (build + workflows[] + updatedAt; staleness) published each cycle by `workflow_status.js --publish`; read in-app by `WorkflowContextService` | The in-app status dashboard | Optional Stock-Track `system/workflowContext` in **Brandon's** Firestore + a small publisher; read by a ported context service. **Later.** Probably trivial for a single-lane project. | **No.** Brandon's project. |
| H8 | **Dogfood report queue** — `mobileIssueReports` collection + `report_queue_screen.dart` (owner reads own reports, comment/status/flag); `chat.js --build` auto-creates a check-item | Owner files + tracks on-device issues | Stock-Track's **own** reports collection (e.g. `stockIssueReports`) + a ported panel, in **Brandon's** Firestore. Cross-ref: distribution plan Stage 3. **Never** BP's `mobileIssueReports`. | **NO — never BP's collection.** |
| H9 | **Push** — FCM to `users/<uid>.fcmToken` on orchestrator reply | Owner gets a phone notification | Brandon's project messaging + Brandon's `users/<uid>.fcmToken`. **Later.** | **No.** Brandon's project. |
| H10 | **Decision register** — `AWAITING_PETE.md` (durable owner-decision ledger) | Nothing dropped; survives session death | **`DECISIONS.md`** (already in place, mirrors the pattern). | **No.** Already done, separate. |
| H11 | **Handoff schema** — `HANDOVER_NEXT_AI.md` (Status / Next / Open Qs / Don't-Revert / Log) | Context survives session death | **`HANDOVER_NEXT_AI.md`** (already in place). | **No.** Already done, separate. |
| H12 | **Service account / secrets** — BP root `service-account.json` (Admin SDK credential) | Server-side auth for the CLI | **Brandon's own** service account JSON, downloaded from **Brandon's** Firebase console, **gitignored**, never committed, never BP's. | **NO — generate Brandon's own.** |

**Net:** copy the **shape** (H1–H4, H10–H11 = pure pattern / already-present registers); re-instantiate
the infra-bound pieces (H5–H9, H12) entirely inside **Brandon's own** project. The lines that must
**never** be copied verbatim are BP's `service-account.json`, BP's project id, BP's UID
(`9kc4UuT…`), BP's bucket, and the `mobileIssueReports` collection name/store.

---

## 4. First harness FORM — recommend (in-app vs web/local tool vs terminal+doc vs STAGED)

**Recommendation: a STAGED rollout that LANDS ON the in-app dev chat (BP's shape).** Decisively **not** a
throwaway web/local chat tool.

Options weighed:

| Form | Verdict | Why |
|---|---|---|
| **Terminal + handoff-doc only** | Current state; **insufficient as the destination** | It's the orchestrator's durable memory and it works — but Brandon can't drive it. He's a non-coder in the field, not at a terminal. Fine as the orchestrator side + interim, not as Brandon's channel. |
| **Web / local chat tool** | **Rejected** | Extra infra to build, host, secure, and authenticate — duplicating what the app + Firestore give for free, and it would NOT live where Brandon already is (his phone with the product). A non-coder shouldn't have to open a separate web app. Net new attack surface and maintenance for zero benefit over in-app. |
| **In-app dev chat** (BP shape) | **Recommended destination** | Lives on the dogfood build Brandon already installs; reuses Firestore real-time; orchestrator side is a ~100-line Node script. Proven in BP. **But** it requires Brandon's Firebase (Auth + Firestore) — the same gate as everything else. |
| **STAGED (recommended)** | **Recommended path** | Don't over-build before Firebase; don't hand-relay forever. Stage it. |

**Recommended staging:**
- **Stage 0 — NOW (no Firebase):** doc-registers + **Pete relays Brandon's words** + file-download APK.
  Honest stopgap while Brandon dogfoods look-and-feel. Already in place. *Do not build throwaway chat
  infra to bridge this gap* — instead, prioritise standing up Brandon's Firebase so the real channel
  lands.
- **Stage 1 — the MVH (gated on Brandon's Firebase):** the in-app owner↔orchestrator **text chat** on
  Brandon's Firestore + `stocktrack_chat.js` + the poke doc + Brandon's Auth. This is the **first real
  harness form** and the point at which Brandon can self-direct.
- **Stage 2 — enrich:** attachments (doc/image) + the dogfood report-queue panel + `system/*` dashboard
  projection + push. Each additive, none blocking.

Rationale for "in-app, staged" over alternatives: it minimises throwaway work (nothing built before
its gate), puts the channel exactly where the non-coder owner already is, reuses proven BP shape, and
keeps the orchestrator side tiny. The only real cost — needing Brandon's Firebase — is a cost we pay
anyway for cloud data and App Distribution, so the harness adds **no new gate**.

---

## 5. Backend — local/mock first? Firebase required? same-project vs isolated? collections?

### 5.1 Can the harness run local/mock at first? (How useful is that?)

**The chat channel itself cannot be a pure local/mock.** A real-time owner↔orchestrator chat needs a
**shared backend both endpoints can reach**: Brandon's phone (wherever he is) and the orchestrator's
Node process (on the dev machine). A pure in-memory/local mock — like Stock-Track's current
`MockInventoryRepository` — only exists inside one process and **cannot bridge two devices**. So a mock
chat is useful **only for building/previewing the chat WIDGET** against seeded messages (UI work), **not
for a working channel.** Verdict: mock is fine for developing the surface; it is **not** a functioning
harness. Don't mistake "the chat screen renders against fake messages" for "Brandon can talk to the
orchestrator."

### 5.2 Does a real in-app chat REQUIRE Brandon's Firebase?

**YES.** Real-time two-way chat = **Firestore listeners** (exactly how BP does it), and **Firebase Auth**
to key the thread to Brandon's UID and scope the security rules. So **proper in-app chat is gated on
Brandon's Firebase** — the **same single gate** as cloud data (the `FirebaseInventoryRepository` swap)
and App Distribution. There is no separate gate to manage: provision the harness collections + Storage
rules **in the same onboarding**.

### 5.3 Same Firebase project (separate collections) vs an isolated project? — SAME PROJECT, SEPARATE COLLECTIONS

**Recommendation: Brandon's OWN Firebase project, the SAME project as the Stock-Track app, with the
harness in SEPARATE top-level collections.** Not an isolated second project.

Rationale:
- **It mirrors BP.** BP's `orchestratorChat` / `system/*` / `mobileIssueReports` all live in the SAME
  Firebase project as the BP app — isolated only by collection name. The harness is the app's own
  dev/owner channel; it belongs alongside the app's data.
- **An isolated project is pure overhead for a non-coder.** Two projects = two service accounts, two
  Auth domains, two App-Distribution setups, two consoles, two billing surfaces for Brandon to manage —
  with **no separation benefit**, because it's all Brandon's data either way.
- **The separation that MATTERS is Brandon-vs-BP**, and same-project-separate-collections already
  delivers that 100% (it's Brandon's project, never BP's). Collection-name isolation inside Brandon's
  project is enough to keep harness data tidy and rule-scoped.

### 5.4 Collections / data structures (mirror BP, in Brandon's project)

```
orchestratorChat/<brandon-uid>/messages/{auto} = {
  role: 'brandon' | 'orchestrator',
  text: string,
  createdAt: serverTimestamp(),
  via: 'text' | 'voice' | 'image' | 'document',
  area?: string,                 // optional; likely unused early
  attachments?: [ { path, contentType?, bytes?, w?, h?, kind?, filename? } ],  // later
  tags?: [...]                   // later, only if multi-lane ever needed
}

system/orchestratorPoke = { pokedAt: serverTimestamp(), note: string, by: <uid> }
system/workflowContext  = { build: string, workflows: [...], updatedAt }   // later, optional dashboard
system/vision           = { ... }                                          // later, optional

stockIssueReports/{auto} = {     // Stock-Track's OWN dogfood queue — NOT BP's mobileIssueReports
  userId: <brandon-uid>, note, screenshots?: [paths], status, createdAt, ...
}

// Storage (later, for attachments):
//   orchestratorChat/<brandon-uid>/docs/**   (owner-read storage.rule)
//   orchestratorChat/<brandon-uid>/media/**  (owner-read storage.rule)

// Security rules: scope every read/write to request.auth.uid == <owner>, in Brandon's firestore.rules.
```

All of the above live in **Brandon's** Firestore/Storage, keyed by **Brandon's** Auth UID, served by
**Brandon's** service account — never BP's.

---

## 6. The SEPARATION checklist (status of each piece vs BP)

| Piece | BP value (do NOT reuse) | Stock-Track status | Action |
|---|---|---|---|
| **Firebase project id** | `blueprintfitnesssubscriptions` | ❌ TO CREATE | Brandon creates his OWN project (his Google account/billing). Gate for cloud data + App-Dist + harness. |
| **Chat collections** | `orchestratorChat/<pete-uid>` in BP project | ❌ TO CREATE (same-named, Brandon's project) | Provisioned when Brandon's Firebase + first message land. Lives in Brandon's Firestore, **never** BP's. |
| **User IDs** | Pete `<owner-reference-app-test-uid-redacted>` | ❌ TO CREATE | Brandon's Firebase Auth UID, set when Brandon signs in on his build. Never Pete's UID. |
| **Attachments / Storage paths** | BP bucket, `orchestratorChat/<pete-uid>/docs|media` | ❌ TO CREATE (later) | Brandon's bucket `<brandon-project>.firebasestorage.app`, paths under Brandon's UID, owner-read rules. |
| **Dogfood checklist / report queue** | `mobileIssueReports` (BP project) | ❌ TO CREATE | Stock-Track's own `stockIssueReports` (name TBD) in Brandon's Firestore. **Never** BP's collection. (Distribution plan Stage 3.) |
| **Decisions register** | `AWAITING_PETE.md` (BP repo) | ✅ DONE | `Brandons_App/docs/DECISIONS.md` — separate repo, separate ledger. |
| **Handoff / orchestrator-lane state** | BP handovers + `system/*` + BP Node scripts | ⚠️ PARTIAL | Registers (`HANDOVER_NEXT_AI.md`, `ORCHESTRATION_NOTES.md`, `working/`) ✅ DONE; the orchestrator Node scripts (`stocktrack_chat.js`, publisher) + `system/*` docs ❌ TO CREATE, pinned to Brandon's project. |
| **App distribution** | BP App-Dist app id `1:677287134512:…` + group `self` | ❌ TO CREATE | Brandon's App-Dist app id + `stocktrack-testers` group. (Covered by the distribution plan.) Never BP's. |
| **Service account / secrets** | BP root `service-account.json`, `FIREBASE_TOKEN` | ❌ TO CREATE | Brandon's own service account JSON, gitignored, never committed, never BP's. |
| **Push / FCM** | BP messaging + `users/<pete-uid>.fcmToken` | ❌ TO CREATE (later) | Brandon's project messaging + Brandon's `users/<uid>.fcmToken`. |

**Already separate ✅:** the decision register, the handoff/orchestration-notes registers, the working
docs, and the app's package id (`com.stocktrack.app`, per the distribution plan). **To create ❌/⚠️:**
Brandon's Firebase project, the chat collections, Brandon's UID, attachments/Storage, the dogfood
reports collection, the orchestrator Node scripts + `system/*`, App Distribution, Brandon's service
account, and push.

---

## 7. Next APK — is the harness needed in it, or after Firebase/App-Distribution? Safest sequence

### 7.1 Direct answer

- **The NEXT mock APK does NOT need the harness, and must NOT be blocked on it.** The next build is the
  frontend-first shell (mock data, **no Firebase**) iterated via file-download. The real in-app chat
  **requires** Firebase, which that slice deliberately omits — so putting a chat UI in the mock APK
  would be either **dead** (no backend) or would **force Firebase into the frontend-first slice**,
  violating the realignment (`DECISIONS.md`: "first APK does NOT need Firebase"). Keep the shell moving.
- **The harness is NOT optional if Brandon drives the workflow** — but **Brandon does not drive it yet**
  (he's dogfooding look-and-feel; Pete relays). So the harness lands **with / right after Brandon's
  Firebase + App Distribution**, not in the next mock APK.

### 7.2 Safest sequence

1. **Next APK = frontend shell, no harness, no Firebase.** Continue look-and-feel iterations via
   file-download. Don't block it. *(Distribution plan Stage 0.)*
2. **Brandon stands up his Firebase** — the single unlock for cloud data **and** App Distribution
   **and** the harness. **Fold the harness into the SAME onboarding:** when Brandon creates the project,
   provision (or document for first-write) the `orchestratorChat` thread, the `system/*` docs, the
   `stockIssueReports` queue, and the `orchestratorChat/<uid>/**` Storage rules — so the harness backend
   exists the moment Firebase does. **→ Add a short "harness collections + Storage rules" note to
   `BRANDON_FIREBASE_SETUP.md`** (one extra bullet, not a separate setup). *(Distribution plan Stage 1.)*
3. **First Firebase-backed App-Distribution build = the build that ALSO carries the in-app dev chat
   surface (text-only MVH)** wired to Brandon's Firestore, plus `stocktrack_chat.js` on the orchestrator
   side. Now Brandon can self-direct from his phone. *(Distribution plan Stage 2 + this plan's MVH.)*
4. **Layer on** attachments + the dogfood report-queue panel + the `system/*` dashboard + push — each
   additive, none blocking. *(Distribution plan Stage 3 + this plan's deferred list.)*

**Key framing:** because real in-app chat **requires** Firebase, the harness rides the **same Firebase
gate** as cloud data and App Distribution — it adds **no new bottleneck**. The single human-owned
bottleneck remains "Brandon creates his Firebase project"; everything harness-side is agent-executable
once that lands. **Do not** treat the harness as optional once Brandon starts driving — but **do** keep
it off the critical path of the current frontend shell.

---

## 8. Risks / things to watch (facts vs to-confirm)

- **(guardrail, load-bearing)** Every orchestrator-side Stock-Track script (`stocktrack_chat.js`, any
  publisher/sender) must initialise the Admin SDK with **Brandon's** `service-account.json` and a
  hardcoded **Brandon UID** — structurally incapable of reading/writing BP's project. Pin the project
  + UID explicitly; never rely on an ambient default credential (which on this machine is BP's).
- **(fact)** The chat cannot be a pure local mock — it needs a shared cloud backend (Firestore). A mock
  only serves UI development of the chat widget, not a working channel (§5.1).
- **(fact)** Same-project-separate-collections gives full Brandon-vs-BP separation; an isolated second
  project adds management overhead with no separation benefit for a non-coder (§5.3).
- **(fact)** This plan writes NO code, creates NO Firebase project, provisions NO collection, ships
  NOTHING, and touches NO BP file. It is the design only.
- **(to-confirm, owner)** Whether Brandon wants the heavier BP layers at all (tagging/lanes, the
  `system/workflowContext` dashboard, push). For a single-lane project these are likely overkill at MVH;
  recommend deferring until there's a demonstrated need.
- **(to-confirm, owner)** The dogfood reports collection name (proposed `stockIssueReports`) and whether
  the report-queue panel rides the same first Firebase build as the chat, or a follow-up.
- **(to-confirm, owner)** Voice dictation: BP's chat supports voice input; for the Stock-Track MVH,
  recommend **text-only first** (voice is an additive controller, not load-bearing).
- **(dependency)** The whole harness is gated on Brandon creating his Firebase project — the same gate
  as cloud data + App Distribution. No way around it for a real-time channel; fold it into the one
  onboarding so it's a single ask of Brandon, not three.

---

## Appendix A — BP PATTERN sources read (read-only, for the PATTERN only)

| BP source (read-only) | Pattern extracted |
|---|---|
| `lib/features/dev/screens/orchestrator_chat_screen.dart` | Dev-gated in-app owner↔orchestrator chat composition root; decomposed harness subtree `lib/features/dev/chat/` (models/services/controllers/widgets); the message-IS-the-poke design |
| `lib/features/dev/chat/services/chat_repository.dart` | The Firestore comms seam: `orchestratorChat/{uid}/messages` schema (`{role,text,createdAt,via,area,attachments?,tags?}`), live query (newest-200), `system/orchestratorPoke` bump on every write, tag-write merge |
| `lib/features/dev/chat/services/workflow_context_service.dart` | The in-app status dashboard projection: reads `system/workflowContext` (build + workflows[] + updatedAt) with server-first/cache-first regimes + staleness warnings |
| `docs/workflows_established/Agent_Coordination/chat.js` | Orchestrator-side CLI (`--read`/`--send`/`--build`/`--media`), Admin SDK via root `service-account.json`, hardcoded UID, Storage bucket, FCM push, lane tagging |
| `docs/workflows_established/Agent_Coordination/chat_send_doc.js` (+ `chat_send_image.js`) | Attachment-send pattern: upload to Storage `orchestratorChat/<uid>/docs|media/...`, write PATH-only (no signed URL), app mints owner download URL on-device; FCM push |
| `lib/features/dev/screens/report_queue_screen.dart` | Dogfood report-queue panel over `mobileIssueReports`, owner reads own reports (filter/expand/comment/status/flag), rules-scoped to `userId == auth.uid` |
| `docs/DECISIONS.md` ← BP's `AWAITING_PETE.md` pattern; `HANDOVER_NEXT_AI.md` ← BP handover schema | Doc-based owner-decision ledger + session-death-surviving handoff (already present in this repo) |

**Copied from BP: pattern/shape only. Copied from BP: ZERO config, secrets, project ids, app ids,
UIDs, tokens, service accounts, buckets, collections, tester records, or dogfood data.**
