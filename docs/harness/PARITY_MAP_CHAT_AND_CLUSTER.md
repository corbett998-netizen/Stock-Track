# Parity Map — Owner Chat controls + Floating Dev-Tool Cluster

**Scope:** two owner-facing harness surfaces, source-of-truth harness vs this port.
1. The **chat top-bar / workflow-tagging** controls (+ copy-message fade-to-gray).
2. The **floating dev-tool cluster** (the draggable on-top overlay).

**Method:** read-only study of both codebases. Every source-harness claim cites
`file:line`. Paths prefixed **SRC:** are in the source-of-truth harness repo (read for
pattern evidence only — no literals copied). Paths prefixed **ST:** are in this repo.
This doc is patterns-only by design (it rides a shared origin): colours are named, not
dumped as hex; no external project ids/uids are reproduced.

**Verdict up front:** the cluster is at near-parity structurally but diverges on
button **count, order, mic placement, and colour identity**. The chat surface has a
**large deliberate gap** — the entire workflow-tagging capability + the copy
fade-to-gray confirm are **absent** in the port (both flagged DEFERRED in the port's
own code).

---

## 1. Chat top-bar / workflow-tagging

### 1a. Source-of-truth behaviour (evidence)

**Normal-mode header — 5 action buttons**
`SRC: lib/features/dev/chat/widgets/chat_header.dart:60-91`
| # | Button | Icon (pattern) | Does |
|---|--------|----------------|------|
| 1 | Stream colours | palette-outline | opens a palette panel to pick/persist a colour per tag-stream `:96-102` |
| 2 | Workflow dashboard | dashboard-outline | read-only per-workflow state/evidence sheet `:106-112` |
| 3 | Copy FULL context | smart-toy | paste-ready onboarding block for an external LLM; hidden until docs load `:116-123` |
| 4 | Copy RECENT | update | only messages since last export `:127-134` |
| 5 | Copy a work-AREA | folder-copy (popup) | lists distinct work-areas w/ counts; picks one → copies that area as a block `:140-158` |

**Selection-mode bar** (replaces the header on long-press multi-select)
`SRC: lib/features/dev/chat/widgets/chat_stream_styling.dart:756-832`
X-exit · "N selected" · **Copy (N)** · **Tag / Label** (label-outline `:822`).

**Tagging data model — structured, two-dimension**
`SRC: chat_stream_styling.dart:163-251` (`WorkflowTag`)
- Each message carries an **additive `tags[]` array**, one element =
  `{id, kind, label, addedBy, addedAt}`. Additive + optional → an untagged message
  renders exactly as before; no schema break, no rules change (owner-scoped write).
- **Two `kind`s / dimensions:**
  - `workflow` — an INTERNAL routing tag, resolved against a canonical registry
    (`WorkflowRegistry.canonical` `:317-327`, mirrors the orchestrator's workflow map).
    Rendered **secondary / de-emphasised**.
  - `chatgpt` — the owner's **free-form "which external-LLM conversation is this for"**
    label; carries its own display name + colour ON the element (no seeded taxonomy),
    so a fresh device + the orchestrator both read the exact label. Rendered **primary /
    full-strength**; its colour drives the bubble's left stripe.
- Dedup is on the `(kind,id)` pair, so a `workflow:x` and a `chatgpt:x` coexist.
- **Provenance:** manual taps are always `addedBy:'pete'` (owner intent, never the
  auto-classifier) — `SRC: chat_tagging_controller.dart:74-92`.

**Write path** `SRC: chat_tagging_controller.dart`
`applyTag/removeTag` + bulk `applyTagToAll/applyChatgptToAll` — sequential per-message
Firestore merge-writes, then `pollOnce` to surface the chip fast AND poke the
orchestrator so it re-routes off the new tag (`:52-116`). Guards a real message doc
before writing so an overlay-only id can't create a junk doc (`:57-60`).

**Picker UX** `SRC: lib/features/dev/chat/widgets/tag_picker_sheet.dart`
One bottom sheet reached from the selection-bar Tag action (no intermediate popup). Two
sections — **ChatGPT conversation** (primary) + **Internal workflow (optional)**
(secondary). A chip reads "checked" only when EVERY selected message carries it
(`commonWorkflowTagIds` intersection `chat_stream_styling.dart:399-405`) → single-select
and multi-select behave identically. `+ New label` / `+ New workflow` = name + colour
swatch, persisted device-side, then applied to all selected.

**Chip render** `SRC: chat_stream_styling.dart:425-691`
Primary chatgpt chip row first (full strength), secondary workflow row after
(de-emphasised), left-edge stripe coloured by the primary tag, per-group `+N` overflow
cap.

**Auto-classification** `SRC: lib/features/dev/chat/models/chat_taxonomy.dart`
Explicit `[Label]`→workflow aliases (`:76-96`), content-keyword→workflow map
(`:104-140`), else inherit. Drives orchestrator routing + the per-workflow export
filter. **This map is app-specific data** (its lanes are the source app's lanes).

### 1b. Port (ST) current state

- **Header** `ST: lib/features/dev/chat/widgets/chat_header.dart` — only **2** actions:
  workflow dashboard + a single copy popup (Full / Recent / Conversation). No stream
  palette, no copy-work-area menu.
- **Selection bar** `ST: lib/features/dev/chat/widgets/chat_selection_bar.dart` —
  close · "N selected" · **Copy (N)** only. **No Tag / Label action.**
- **Tagging: entirely absent.** The port declares it deferred in its own code:
  `ST: chat/models/chat_item.dart:6` ("workflow-tag arrays are DEFERRED") and
  `ST: chat/controllers/chat_message_controller.dart:12` ("workflow tagging … DEFERRED").
  No `WorkflowTag` model, no registry, no tag picker, no tagging controller, no
  taxonomy, no per-message stripe/chips, no stream-colour palette.

### 1c. Gap + classification

| Piece | Generic (harness core) | App-specific (config/seed) |
|-------|------------------------|----------------------------|
| `tags[]` message schema `{id,kind,label,addedBy,addedAt}` | ✅ generic | — |
| Two-dimension concept (internal routing + owner free-form external-LLM label) | ✅ generic | — |
| Selection-bar Tag action + picker UX (apply-to-all, common-checked, +New w/ colour) | ✅ generic | — |
| Chip render (primary/secondary, stripe, +N overflow) + stream-colour palette | ✅ generic | — |
| Tagging controller (merge-write → poll → poke) | ✅ generic | — |
| The **workflow SET** (the actual lane names) | — | ✅ app supplies a registry |
| The **classify keyword/alias map** + export glossary blurbs | — | ✅ app-owned taxonomy |

The `chatgpt` free-form-label dimension is **100% generic** — no taxonomy at all, pure
owner intent. Only the INTERNAL-`workflow` dimension needs an app-supplied registry +
keyword map. The source harness already isolates that seam (registry mirrors the
orchestrator map; project name comes from a `HarnessConfig` constant) — so the port
should **drive the workflow set + keywords from this repo's own config**, never copy the
source app's lanes.

### 1d. Recommended plan

- **[NEEDS-OWNER-REVIEW] Decide scope before porting.** Tagging is a large surface
  (schema + controller + picker sheet + chip render + palette + a device-persisted
  registry/override store) and it only earns its keep if this app runs a **multi-lane
  orchestrator** that routes off per-message tags. **Effort: HIGH. Risk: MEDIUM**
  (additive arrays, no rules change per the source design, but a lot of new UI + a new
  store). Owner picks one:
  - (a) **Full two-dimension tagging** — internal-workflow routing + free-form label.
  - (b) **Free-form conversation-label only** — the generic, low-config slice: no
    registry, no keyword taxonomy, just the owner's "which external-LLM chat is this
    for" chip + colour. **Effort: MEDIUM, Risk: LOW.** Best value-per-risk if the goal
    is routing replies to the right external conversation without internal-lane routing.
  - (c) **Skip** — keep tagging deferred.
- Whichever scope: land the schema/controller/picker/render/palette in the harness core
  as app-agnostic, and feed the workflow set + keywords from **this repo's** config.

---

## 2. Copy-message fade-to-gray (visual confirm)

**Source behaviour** `SRC: chat_stream_styling.dart:595-606`
Once a message is copied, the bubble body is wrapped in `Opacity(0.5)` (dim-to-gray) with
a small green **"copied ✓"** badge (`_CopiedBadge :697-741`) that is **tappable to UNDO**.
The copied flag is a per-message boolean read from a store (`store.isCopied(id)`,
`SRC: chat/widgets/chat_bubble.dart:82`); the badge colour is a dedicated green,
deliberately NOT the stream-blue so it never collides with a tag colour. Pure
presentation — no message-data change.

**Port state** `ST: chat/widgets/chat_bubble.dart` + `orchestrator_chat_screen.dart:139-156`
**Absent.** `_copyOne` / `_copySelected` set the clipboard + show a `Copied` snackbar and
nothing else — no per-message copied flag, no dim, no badge, no undo. (Confirmed: no
`isCopied` / copied-state symbol anywhere under `ST: lib/features/dev/`.)

**Safe to add now? YES — [SAFE-NOW].** It is pure presentation + one per-message boolean.
No Firestore, no schema, no rules. Implementation (all in this repo):
1. a tiny copied-state store keyed by message id (in-memory, or SharedPreferences to
   survive a restart — mirrors the source pattern);
2. wrap the ST `ChatBubble` body in `Opacity(isCopied ? 0.5 : 1)` + a small "copied"
   badge (optionally tap-to-undo);
3. set the flag in `_copyOne` (and per-message in `_copySelected`).
**Effort: LOW. Risk: LOW.**

---

## 3. Floating dev-tool cluster — button-for-button

Both clusters are the same architecture: a single draggable column mounted at the
`MaterialApp.builder` seam ABOVE the Navigator, long-press-drag anywhere + a grip handle,
position persisted as a screen fraction, re-clamped for safe-area + bottom-nav clearance.
`SRC: lib/features/mobile_testing/widgets/draggable_fab_stack.dart` ·
`ST: lib/features/dev/overlay/harness_fab_cluster.dart`.
The port additionally makes the button set **config-driven** (`ST: overlay/harness_tools.dart`
+ `harness_tool_spec.dart`) — a strict improvement over the source's hardcoded child list.

### Button-for-button (top → bottom)

| Slot | SRC button (icon / colour) | ST button (icon / colour) | Match? |
|------|----------------------------|---------------------------|--------|
| grip | drag handle — black / teal-when-dragging | drag handle — translucent black / white70 | ~ cosmetic |
| 1 | **Ready-to-test / dogfood** — fact-check / **orange**, red count badge | **Mic** — in-place dictation / accent **blue** | ✗ different tool AND colour |
| 2 | **Chat** — chat-bubble / **orange**, red unread badge | **Chat** — chat-bubble / accent **blue**, **no badge** | ~ same tool, colour + badge differ |
| 3 | **Report queue** — list-alt / **teal**, no badge | **Report queue** — list-alt / accent **blue**, red badge | ~ same tool, colour + badge differ |
| 4 | **Mic** — in-place dictation / **red** (pulses) | **Report capture (bug)** — bug / accent **blue** | ✗ different tool |
| 5 | **Bug report** — bug / **red-accent**, amber draft badge | **Ready-to-test** — fact-check / accent **blue**, red badge | ✗ different tool |
| 6 | — (none) | **Poke** — notifications / **muted slate** | ✗ ST-only |
| 7 | — (none) | **Command center** — dashboard / accent **blue** | ✗ ST-only |

`SRC:` slots from `draggable_fab_stack.dart:199-214` + the five FAB widgets
(`dogfood_review_fab.dart`, `orchestrator_chat_fab.dart:115`, `report_queue_fab.dart:48`,
`mobile_issue_voice_button.dart`, `mobile_issue_reporter_button.dart:65`).
`ST:` slots from `overlay/harness_tools.dart:27-159` (order = list order); colours from
`harness_tool_button.dart:54` (`spec.color ?? HarnessTheme.accent`) + `harness_theme.dart:17`.

### Findings

- **COUNT:** source **5** tool buttons; port **7**. The port adds a standalone **Poke**
  and a **Command center** the source cluster does not carry.
- **ORDER:** materially different. Source top slot = the daily "what's ready to test"
  review; port top slot = the mic. The report/review tools are reordered throughout.
- **MIC PLACEMENT:** source mic sits **near the bottom** (slot 4 of 5, just above the bug
  button) — a deliberate low-reach position under the core review/chat/queue stack. Port
  mic sits at the **very top** (slot 1). Mechanism is at parity (both are in-place,
  stateful, engine-toggle-on-long-press dictation widgets); only placement differs.
- **POKE redundancy:** the source cluster has **no dedicated Poke button** — a nudge is
  implicit (sending or tagging a message already pokes the orchestrator,
  `SRC: chat_tagging_controller.dart:52-65`). The port's standalone Poke
  (`ST: harness_tools.dart:118-143`) duplicates that implicit nudge; it is a low-value,
  muted utility slot. **Arguably redundant** — recommend demoting to optional
  (the config list already makes removal a one-line edit).
- **MAIN-STACK vs COMMAND-CENTER:** source dropped the command-center page from the
  cluster path — the buttons ARE the menu, each opens its surface directly and returns to
  the same screen. The port ALSO uses the buttons-are-the-menu model, but retains a
  vestigial **Command center** button (`ST: harness_tools.dart:147-158`, its own comment:
  "still available, but no longer THE entry"). That leftover is the single-FAB→home-page
  model the source already retired from the cluster.

### Reusable colour identity

- **Source:** colours are **hardcoded literals per FAB widget** — orange / teal / red /
  red-accent, one per function. Not themeable, but it IS a **glanceable per-function
  colour identity** (recognise a tool by colour at arm's length).
- **Port:** already better on reusability — one themeable seam
  (`HarnessTheme.accent`, `harness_theme.dart:17`) + a per-spec override hook
  (`HarnessToolSpec.color`). BUT it flattened everything to a **single accent** (only
  Poke deviates), so the source's per-function colour identity is **lost** — every tool
  reads the same blue.
- **Recommendation [SAFE-NOW]:** ship a small **themeable palette of ROLES** (e.g.
  `primaryAction`, `report/destructive`, `utility/muted`, `mic`, `review`) in the harness
  core, and source each `HarnessToolSpec.color` from that role table instead of defaulting
  all to one accent. The override hook already exists — this only adds a named palette,
  so the app keeps the source's glanceable colour-coding WITHOUT hardcoded literals.
  **Effort: LOW. Risk: LOW.**

---

## 4. Clean recommendation (owner-approvable)

**Do now (safe, self-contained):**
1. **[SAFE-NOW] Copy fade-to-gray + "copied" badge** in the chat bubble (§2). Pure
   presentation, one per-message boolean. LOW/LOW.
2. **[SAFE-NOW] Themeable colour-role palette for the cluster** (§3) — restore the
   per-function colour identity via a role table feeding `HarnessToolSpec.color`. LOW/LOW.
3. **[SAFE-NOW] Cluster parity clean-ups:** move the mic OFF the top slot (source keeps it
   low), and demote **Poke** + **Command center** to optional/removed (both are one-line
   config edits; Poke duplicates the implicit send/tag nudge). LOW/LOW — but confirm the
   desired final ORDER with the owner since it's a muscle-memory surface.

**Needs owner review (scope/size):**
4. **[NEEDS-OWNER-REVIEW] Workflow tagging** (§1) — pick scope first: (a) full
   two-dimension, (b) free-form conversation-label only (the low-config generic slice), or
   (c) stay deferred. Only worth (a) if this app runs a multi-lane orchestrator that routes
   off per-message tags. HIGH effort for (a) / MEDIUM for (b). Land generics in harness
   core; drive the lane set + keywords from THIS repo's config, never copy the source lanes.
5. **[NEEDS-OWNER-REVIEW] Stream-colour palette + header parity** (the 3 missing header
   actions: stream palette, copy-work-area) rides on #4's decision — they're the render/UX
   half of tagging. Defer until #4 scope is set.
