# Tagging / Workflow-Label SYNCHRONIZATION — Definition, State, Risks, Plan

**Scope.** Define what "synchronization" means for the chat message-tagging feature that
just shipped (commit `ab53332`), assess the current state of each sync surface against the
real code, rank the risks, and produce an ordered, sub-worker-scoped build plan. **Review +
plan only** — no code was edited, no git run, no build. Companion to
`docs/harness/TAGGING_REVIEW.md` (the build recommendation) — this doc is the SYNC follow-up.

**Patterns-only.** No reference-app identifiers or secrets are reproduced. This repo's own
config values (its collection/owner names) are cited where they are load-bearing, since they
are this app's own identity and appear throughout its own source. Reference behaviour is
attributed to "the reference harness / reference operator," never a named app.

**Headline up front.** The generic core (model, parse/dedup, fingerprint, gate, picker,
device store) is well-built and unit-proven on the mock path. But **the one surface that
makes tagging real — persisting a tag to the backend — is very likely BROKEN on-device
against the deployed security rules**: the tag write is a document UPDATE, and the deployed
rule denies client updates on message docs. Every other sync surface is downstream of that
write, so it is the gate for the whole feature. This is code-evident and high-confidence;
the definitive proof is a 2-minute on-device tap or an emulator rules-test (see T1).

---

## 1. What SYNCHRONIZATION means here — the sync surfaces

Tagging is only useful if a tag applied in one place shows up, correctly and without
conflict, everywhere it should. "Synchronization" for this feature = the union of these
surfaces:

| # | Surface | The sync contract (what "in sync" means) |
|---|---------|------------------------------------------|
| 1 | **Owner device ↔ Firestore backend** | A tag the owner applies persists to the message doc and reflects after a reload of the same device. This is the root write; everything else depends on it. |
| 2 | **Cross-device / cross-session** | The same owner on a second device/session sees the same tags (membership) and the same label names/colours. Split into: (2a) tag **membership** on the message, (2b) the label **definitions** (name + colour) shown in the picker. |
| 3 | **Owner ↔ operator** | The operator loop can read the owner's tags and (for the workflow dimension) resolve + mirror a lane; for the label dimension, the operator at least sees which conversation a message belongs to. |
| 4 | **Concurrency / conflict / ordering** | Two tag edits (two devices, or owner-tap racing an operator inherit-write, or a bulk apply-to-all) merge without a lost update; a tag write does not clobber other message fields. |
| 5 | **Real-time vs on-reload** | Tags surface live (push/stream) or within a bounded poll interval, not only on a manual refetch. |

---

## 2. Current state per surface (evidence-anchored)

### Surface 1 — Owner device ↔ Firestore backend: **GAP (likely broken on-device)** ⛔

- **Write path:** `FirebaseChatRepository.writeTags` (`lib/features/dev/chat/services/chat_repository.dart:167-207`)
  patches the message with `_messages(uid).doc(msgId).set({'tags': payload}, SetOptions(merge: true))`
  (`:189-191`). The `addedAt`-inside-an-array landmine is correctly avoided — each element uses
  a concrete client `Timestamp` (`:183-185`, mirrored in `models/workflow_tag.dart:99-103`).
- **Read-back path is correct:** `fetchMessages` reads from the **server** source
  (`chat_repository.dart:108-111`), the watch stream maps snapshots (`:104-105`), and both parse
  `tags` via `WorkflowTag.listFrom(d.data()['tags'])` (`:98`). So *if* the write lands, reload
  reflects it.
- **The gap — the write is an UPDATE, and the deployed rule denies it.** The message-doc rule
  (`firestore.rules:25-28`) is **append-only**:
  ```
  match /orchestratorChat/{uid}/messages/{msg} {
    allow read, create: if signedIn() && request.auth.uid == uid;
    allow update, delete: if false;      // ← tag write is an UPDATE → DENIED
  }
  ```
  A `set(..., merge:true)` on a message doc that **already exists** (every taggable message
  does) evaluates the Firestore **`update`** rule, which is `if false`. So on a real device the
  tag write returns `PERMISSION_DENIED`; the controller catches it and shows
  "Could not save tag" (`controllers/chat_tagging_controller.dart:54-60`), and nothing persists.
- **Why the code/review believe otherwise:** the writer comment says "covered by the existing
  owner-write rule — NO firestore.rules change" (`chat_repository.dart:53-55, 188`). That is
  true of the *reference* harness's rules but **false for THIS repo's rules**, whose message
  rule is create-only. The tagging commit `ab53332` did not touch `firestore.rules`
  (last rules change was the FCM commit `edaf1ef`), so no tags-update allowance was added.
- **Why the unit tests are green anyway:** the whole tagging test suite
  (`test/harness_tagging_test.dart`) runs against `MockChatRepository`, which mutates an
  in-memory list (`chat_repository.dart:313-325`) and **never touches Firestore rules**. Per
  doctrine, a green mock/unit test does not establish on-device behaviour.
- **Verification status:** code-evident, high-confidence. **Needs an on-device tap (or a
  Firestore emulator rules-test) to make it a proven fact** — that is exactly what T1's
  acceptance test does.

### Surface 2 — Cross-device / cross-session: **PARTIAL (membership syncs; definitions are local-only)**

- **(2a) Tag membership — SYNCS (conditional on Surface 1).** Membership lives on the Firestore
  message doc's `tags[]` and is read fresh from the server on every poll + watch emission
  (`chat_repository.dart:98,104-111`). A second device reads the same array. The free-form
  **label text also rides on the message element** (the `label` field), so a fresh device with
  no local data still shows the exact label — `ChatTagStore.resolveLabel` falls back to the
  carried label + a deterministic colour (`services/chat_tag_store.dart:113-123`; proven for a
  fresh device by `test/harness_tagging_test.dart:202-210`). **This is the well-designed part.**
  Caveat: it only works if Surface 1's write actually lands.
- **(2b) Label DEFINITIONS — do NOT sync (device-local store).** `ChatTagStore` persists the
  owner's reusable label list and workflow overrides in **SharedPreferences only**
  (`chat_tag_store.dart:25-26`), and the picker list is built purely from that local map
  (`pickerLabels()` `:96-100`, `addLabel` `:104-107`, `upsertWorkflow` `:141-144`). Consequences
  on a second device:
  - The picker will **not list** labels the owner created on device A (he'd have to re-create
    them; the `idForLabel` kebab is deterministic so re-creating "Blue" yields the same id and
    coexists cleanly — no data corruption, just a re-type).
  - A **recolour/rename** done on device A does **not** propagate; device B renders the
    deterministic default colour / carried label, so **chip colours can differ across devices**.
  - This is the "device-store-vs-backend staleness" the brief flagged. Verdict: **real but
    bounded** — it is cosmetic + picker-availability, **not** membership loss (chips still
    render from the carried label).
- **Verification status:** membership-syncs is code-verified for the read path (and depends on
  Surface 1); the colour/picker desync is code-verified. A second-device runtime test would
  confirm end-to-end once Surface 1 is fixed.

### Surface 3 — Owner ↔ operator: **GAP (no operator-side tag consumer exists in this port)**

- The operator CLI `scripts/stocktrack_chat.js` **does not read tags at all.** `cmdRead`
  (`:193-209`) emits only `${m.text}` with `via`; it never inspects `m.tags`. A repo-wide grep
  finds **zero** tag references in either operator script.
- The lane state-machine / continuity-inherit / mirror-onto-reply behaviour that
  `TAGGING_REVIEW.md §1c` describes is a property of the **reference** operator; it was **not**
  ported here. In this port, tags currently route **nowhere**.
- The operator bridge is **`off`** anyway (`harness/project.config.json:53`), so no loop is
  polling. So this gap is *expected* today, but the review's "tags REALLY route" claim must be
  read as "in the reference," not "in Stock-Track."
- **Split by dimension:** the **label** dimension's owner→operator visibility (operator sees
  which conversation a message is for) is a small, generic, buildable slice (T4). The
  **workflow** dimension's full state-machine is gated (`taggingWorkflowEnabled=false`,
  `harness_config.g.dart:53`, derived from `lanes.count>1` in `harness/gen_app_config.js:66-69`)
  and only earns its keep at multi-lane + bridge-live (T5).
- **Verification status:** code-verified (absence is definitive).

### Surface 4 — Concurrency / conflict / ordering: **GAP (lost-update risk; structurally last-write-wins)**

- **Read-modify-write over the WHOLE array, not atomic.** `applyTag`/`removeTag` read the
  currently-rendered tags via `currentTagsOf(msgId)` (`chat_tagging_controller.dart:64-97`),
  compute the full desired list, and hand it to `writeTags`, which `set`s the entire `tags`
  array with `merge:true` (`chat_repository.dart:176-191`). There is **no** `arrayUnion` /
  `arrayRemove` / transaction.
- `currentTagsOf` reads the **local rendered snapshot** (`chat_message_controller.dart:77-82`),
  which can be stale relative to the server. So two writers each overwrite the full array from
  their own snapshot → **lost update** (the later writer clobbers the earlier writer's tag).
- **Bulk apply-to-all is sequential** (`chat_tagging_controller.dart:102-135`), each message its
  own read-modify-write, widening the stale-snapshot window.
- **Probability today: LOW** — a single owner, operator off. **But it becomes real exactly when
  the workflow dimension ships**, because that design has the operator *inherit-write* tags
  concurrently with owner taps (multi-writer is the whole point). The current write shape is
  structurally unsound for that future. Note: a tag write does **not** collide with a *message*
  write — `sendMessage` only `add`s new docs (`chat_repository.dart:121-129`) and `writeTags`
  merges only the `tags` field — so the risk is **tag-vs-tag**, not tag-vs-message.
- **Verification status:** code-verified (the write shape is last-write-wins by construction).

### Surface 5 — Real-time vs on-reload: **WORKS (poll-based, conditional on Surface 1)**

- Two delivery mechanisms: the Firestore `snapshots()` watch stream
  (`chat_repository.dart:104-105`) and a **3-second foreground server poll**
  (`chat_message_controller.dart:34,128-129,150-165`). The controller folds a per-message **tag
  fingerprint** into the content signature (`_sigOf` `:217-236`; `ChatItem.tagFingerprint`
  `models/chat_item.dart:42`), so an in-place tag edit (same doc id) flips the signature and
  triggers exactly one targeted rebuild — no scroll-yank.
- **Owner's own device:** after his write, `writeTags`→`pollOnce()` fires an immediate server
  re-get (`chat_tagging_controller.dart:56`, wired at `orchestrator_chat_screen.dart:78`), so the
  chip surfaces near-instantly.
- **Second device:** surfaces within ~3s via the poll (or on the next stream emission). There is
  **no FCM push for a tag change** — `writeTags` only bumps the operator poke
  (`chat_repository.dart:192-206`); `sendPush` fires only on operator replies. So a second owner
  device relies on poll/stream, which is acceptable (bounded latency), not push-instant.
- **Verification status:** code-verified for the mechanism; end-to-end depends on Surface 1.

**Sync-surface map (one line each):**
1. Owner↔backend — **GAP** (tag write is an UPDATE; deployed rule denies it) — needs on-device/emulator confirm.
2. Cross-device — **PARTIAL** (membership + label-text sync; picker list + colours are local-only).
3. Owner↔operator — **GAP** (operator reads no tags; state-machine not ported; bridge off).
4. Concurrency — **GAP** (full-array last-write-wins; lost-update risk, latent until multi-writer).
5. Real-time/reload — **WORKS** (3s poll + fingerprint; no push for tags), conditional on #1.

---

## 3. Risks — ranked

### R1 (CRITICAL) — Tag writes are denied by the deployed security rules
The merge-set is a document UPDATE; `firestore.rules:28` is `allow update, delete: if false`
for message docs. On-device, every tag apply/remove very likely returns `PERMISSION_DENIED` →
"Could not save tag" → **nothing persists**, which makes Surfaces 2, 3, and 5 moot. The
pervasive "no rules change needed" comment is false for this repo. **This is the prime suspect
and the gate for the entire feature.** Confidence: high (deterministic from reading the rules).
Confirm with a 2-minute on-device tap or an emulator rules-test.

### R2 (MEDIUM) — Full-array last-write-wins = lost update under concurrent tag edits
No `arrayUnion`/transaction; each writer overwrites the whole `tags` array from a possibly-stale
local snapshot. Low probability with one owner + operator off, **but structurally unsound for
the exact multi-writer future the workflow dimension is designed for** (operator inherit-write
racing owner taps). Fixing R1 without R2 leaves a latent correctness bug that surfaces the day a
second writer exists.

### R3 (LOW-MEDIUM) — Device-local tag store staleness across devices
Label definitions (name + colour) and workflow overrides live only in SharedPreferences
(`chat_tag_store.dart:25-26`), so a second device's picker won't list the owner's labels and
won't reflect his recolours/renames. Applied chips still render (carried label + deterministic
colour), so **no membership loss** — this is cosmetic + picker-availability. Bounded, but it is
the "device-store-vs-backend" divergence the brief asked to assess concretely: real, low blast
radius.

*(Surface 3's operator blindness is a not-yet-built consumer rather than a defect, so it is
carried as build tasks T4/T5, not ranked as a live risk while the bridge is off.)*

---

## 4. Prioritized build plan (each task scoped for a sub-worker)

### MUST-FIX for correct sync

#### T1 — Allow the owner to patch `tags` on their own message (fix R1) · effort: S · risk: MEDIUM
- **Change:** In `firestore.rules`, add a narrow `update` allowance on
  `orchestratorChat/{uid}/messages/{msg}` that lets the owner mutate **only** the `tags` field
  and nothing else, preserving append-only for message content. Sketch:
  ```
  allow update: if signedIn() && request.auth.uid == uid
    && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['tags']);
  allow create: if signedIn() && request.auth.uid == uid;
  allow delete: if false;
  ```
- **Files:** `firestore.rules` (message-doc match block, `:25-28`). No app-code change required;
  `writeTags` already merges only `tags`.
- **Acceptance (product-facing — mock/unit is NOT sufficient):** either (a) on-device: owner
  taps a conversation label → no "Could not save tag" snackbar → the chip persists across a
  reload and appears on a second device within one poll; **or** (b) a Firestore emulator
  rules-test proving an `update` whose diff is `{tags}` is ALLOWED while an `update` touching
  `text` (or any other key) is DENIED, and `create`/`delete` behaviour is unchanged.
- **Deploy note:** rules must be deployed to the live project for the on-device path to change;
  the emulator test can gate the merge before deploy.
- **Why first:** nothing else about sync is real until this lands. Also reconcile the false
  "no rules change needed" comments in `chat_repository.dart:53-55,188` when this ships.

#### T2 — Make tag writes conflict-safe (fix R2) · effort: M · risk: MEDIUM
- **Change:** Replace the full-array `set(merge:true)` read-modify-write with either
  (a) a Firestore **transaction** that re-reads the doc's `tags` server-side, applies the
  add/remove **intent**, and writes back; or (b) `arrayUnion`/`arrayRemove` on the exact tag
  element. Prefer the transaction — `arrayRemove` needs an exact element match, which is fragile
  with per-element timestamps. This means passing an **intent** (`{op: add|remove, tag}`) down to
  the repository rather than a fully-computed desired array.
- **Files:** `services/chat_repository.dart` (`writeTags` → transactional add/remove; likely a
  new `applyTag`/`removeTag` repo method), `controllers/chat_tagging_controller.dart:48-135`
  (pass intent instead of the full list; keep the durable-doc guard + poke bump), and the mock
  repo (`chat_repository.dart:313-325`) for parity.
- **Acceptance:** an emulator/integration test where two writers add *different* tags to the same
  message near-simultaneously → **both survive** (no lost update); and add-then-remove of the
  same tag converges. Existing `harness_tagging_test.dart` cases stay green.
- **Sequence:** after T1 (same files/area; T1 unblocks any on-device proof T2 needs).

### NICE-TO-HAVE / follow-on

#### T3 — Sync label definitions (name + colour) across devices (address R3) · effort: M · risk: LOW
- **Change:** Mirror the owner's label defs + workflow overrides to a per-owner **backend** doc
  so a second device's picker lists them and recolours/renames propagate. The thread doc
  `orchestratorChat/{uid}` is already owner read/write (`firestore.rules:33-36`) — reuse it (a
  `tagRegistry` map field) rather than adding a collection. Keep `ChatTagStore` as a
  write-through cache (local stays the fast path; backend is the cross-device source).
- **Files:** `services/chat_tag_store.dart` (add backend load/merge on top of the prefs cache),
  `services/chat_repository.dart` (read/write the registry field). No rules change (reuses the
  existing thread-doc allowance).
- **Acceptance:** create/recolour a label on device A → device B's picker lists it with the same
  colour after a reload. (Chips already render without this; T3 is picker-availability + colour
  parity, so it is genuinely nice-to-have, not correctness.)

#### T4 — Operator reads the LABEL dimension (Surface 3, generic half) · effort: S · risk: LOW
- **Change:** Teach `scripts/stocktrack_chat.js --read` to surface each owner message's
  conversation label(s) from `m.tags` (kind `chatgpt`, using the carried `label`), so the
  operator sees which external-LLM conversation a message belongs to; optionally let `--send`
  echo a label onto the reply. This is the config-free slice — no lane set needed.
- **Files:** `scripts/stocktrack_chat.js` (`cmdRead` `:193-209`; optional `cmdSend` `:211-226`).
  Keep the BP-abort guard + `--selftest` coverage; add a pure test for the label-extraction
  helper.
- **Acceptance:** `--read` (dry-run/emulator) prints the label beside a tagged owner message;
  `--selftest` stays green. **Gated:** only *matters* once `orchestratorBridge` goes `live`, but
  it is buildable + self-testable now.

#### T5 — Port the WORKFLOW-dimension operator state-machine · effort: M-H · risk: MEDIUM · **deferred/gated**
- **Change:** Port the reference operator's lane resolution (explicit > continuity-inherit >
  switch > clear-sentinel > topic-break > drift-nudge) + mirror-onto-reply + `workflow:id →
  ownerAgent` resolution, all as pure `--selftest` helpers reading the lane set from
  `harness/project.config.json:lanes` (never a hardcoded list).
- **Files:** `scripts/stocktrack_chat.js` (or a new operator tagging module).
- **Acceptance:** `--selftest` covers the resolution rules; the classifier never overrides an
  explicit owner tag and never emits a `chatgpt` tag.
- **Gate:** only build when the app goes **multi-lane** (`lanes.count>1` →
  `taggingWorkflowEnabled=true`, `harness_config.g.dart:53`) **and** the bridge is live. At one
  lane it routes nowhere — do not build speculatively. Depends on T2 (concurrency-safe writes)
  because the inherit-write is a second concurrent writer.

**Recommended order:** T1 → T2 (correctness gate + make it multi-writer-safe), then T3 and T4 in
parallel (independent, low-risk), with T5 explicitly deferred behind the multi-lane + bridge-live
gate.

---

## Facts / claims / risks / owner-decisions

- **Facts (verified from code):** tag writes are a merge-set = document UPDATE
  (`chat_repository.dart:189-191`) and the deployed message rule denies client updates
  (`firestore.rules:28`); the operator scripts contain zero tag references; the write is a
  full-array last-write-wins with no transaction/arrayUnion; membership + label-text sync via the
  server-read path while label definitions/colours are SharedPreferences-only; delivery is a 3s
  poll + fingerprint with no push for tag changes; the workflow dimension is config-gated off at
  one lane.
- **Claims (asserted, not yet runtime-proven):** the tag write returns PERMISSION_DENIED
  on-device (high-confidence inference from the rules — **T1's on-device/emulator test converts
  this to a fact**); T1 is a small rules-only fix; T2 makes the write multi-writer-safe.
- **Risks:** R1 (writes denied — gates the whole feature), R2 (lost update once a second writer
  exists), R3 (cross-device colour/picker desync).
- **Owner-decisions:** (i) approve the narrow `tags`-only update allowance in `firestore.rules`
  (T1) and its deploy; (ii) confirm whether cross-device parity (T3) is wanted now or later;
  (iii) T5 stays deferred unless a multi-lane operating model is imminent.
