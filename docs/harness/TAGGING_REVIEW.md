# Tagging / Workflow-Labeling — Deep Review + Recommendation

**Scope.** A dedicated review of the owner-chat **workflow-tagging / labeling** capability
in the reference harness, to decide its future as a real, reusable HARNESS feature (not a
one-off app screen). Read-only study of the reference implementation, this port's current
state, and the framework docs. Decision requested: **(a) full two-dimension tagging /
(b) free-form conversation-label only / (c) stay deferred.**

**Patterns-only (this doc rides a shared origin).** No reference-app project ids / owner
ids / collection literals / domain lane-names / hex colours are reproduced. Reference
evidence is cited as `ref: <feature-relative-path>:<lines>` — these are generic
feature-first Flutter paths that carry no app identity (same convention as the existing
`PARITY_MAP_CHAT_AND_CLUSTER.md`). Paths prefixed `ST:` are in this repo; `AH:` are
framework docs.

**Verdict up front.** Tagging IS a genuine reusable harness capability, but it is a
**config-gated** one. Its cheap half (a free-form "which external-LLM conversation is this
for" label) is 100% generic and pays off first; its expensive half (internal work-lane
routing) only earns its keep once an app actually runs a **multi-lane** orchestrator that
routes off the tags. This port declares **one** lane today and its operator bridge is
**off**, so full routing has nothing to route to yet.

---

## 1. What the reference tagging system actually IS

It is **not** a cosmetic label. It is a small, well-factored subsystem with a durable data
model, a purpose-built multi-select UI, and a **live downstream consumer** (the operator
loop) that routes replies off the tags. Three parts:

### 1a. Data model — structured, additive, two-dimension

- **Per-message additive array.** Each chat message carries an optional
  `tags[]` array; one element = `{id, kind, label, addedBy, addedAt}`
  (`ref: chat/widgets/chat_stream_styling.dart:163-251`). It is **orthogonal + additive**:
  a message doc can independently carry a `tags[]` and an `attachments[]` array, either may
  be absent, and an untagged message renders byte-identically to the pre-tagging path. This
  is what let the reference add it with **no backend-rules change** (the array is covered by
  the existing owner-write rule).
- **Two `kind` dimensions:**
  - `kind:'workflow'` — an **internal routing tag**. Its `id` (stable lower-kebab) resolves
    against a **registry** of canonical work-lanes → `{label, colour, ownerAgent}`
    (`ref: chat_stream_styling.dart:253-343`). Rendered **secondary / de-emphasised**.
  - `kind:'chatgpt'` — the owner's **free-form "which external-LLM conversation is this
    for"** label. Deliberately **no seeded taxonomy**: the display name + colour ride **on
    the message element itself** (`label` field), so a fresh device and the operator both
    read the exact label with zero registry (`ref: chat_stream_styling.dart:186-193`,
    `:345-350`). Rendered **primary / full-strength**; its colour drives the bubble stripe.
- **Dedup is on the `(kind,id)` pair**, so a `workflow:x` and a `chatgpt:x` coexist as two
  distinct chips (`ref: chat_stream_styling.dart:213-237`).
- **Provenance.** `addedBy` distinguishes an owner tap (the owner-role value) from
  an operator-applied inherit; manual taps are **always owner-intent, never the
  auto-classifier** (`ref: chat/controllers/chat_tagging_controller.dart:73-92`). `addedAt`
  is a concrete client timestamp (a server-timestamp is illegal inside an array element —
  a real portability landmine, documented in both the app writer and the operator writer).
- **Registry sourcing is layered:** an in-code canonical seed
  (`ref: chat_stream_styling.dart:317-327`) + **device-side overrides** (recolour / rename /
  ad-hoc lanes) persisted to local prefs (`ST`-equivalent `ChatStylingStore`,
  `ref: chat/services/chat_styling_store.dart:184-235`). A shared server-backed registry is
  explicitly noted as a later upgrade, not required for v1.

### 1b. UI — one picker, reached from the existing multi-select

- **Entry point is the multi-select selection-bar**, not a new menu. Long-press a message →
  multi-select → the header is replaced by a bar with `Copy (N)` + a **Tag / Label** action
  (`ref: chat_stream_styling.dart:743-832`). The reference deliberately **collapsed an
  earlier intermediate popup** into this existing flow (owner found the popup annoying).
- **One bottom sheet, two sections** (`ref: chat/widgets/tag_picker_sheet.dart:92-234`):
  a **primary "external-LLM conversation"** section (the owner's own free-form labels) and a
  **secondary "internal workflow (optional)"** section (the registry lanes). `+ New label`
  and `+ New workflow` both = name + colour-swatch, persisted device-side.
- **Apply-to-all with common-checked semantics.** A chip reads "checked" only when **every**
  selected message already carries it (set-intersection,
  `ref: chat_stream_styling.dart:391-405`), so single-select and multi-select behave
  identically. The pure apply/common helpers are extracted + unit-tested
  (`ref: chat_stream_styling.dart:399-419`).
- **Chip render** (`ref: chat_stream_styling.dart:421-691`): primary free-form chip row
  first (full strength), secondary workflow row after (de-emphasised), a left-edge stripe
  coloured by the primary tag, per-group `+N` overflow cap so a heavily-tagged bubble can't
  crowd the text.
- **Stream-colour palette** = a device-persisted swatch set with a deterministic default
  colour per tag (stable hash → swatch index, stable across restarts before any override,
  `ref: chat_stream_styling.dart:17-55`).
- **Live re-render on an in-place tag edit.** Tagging mutates an existing doc (its id is
  unchanged), so the render list folds a per-message **tag fingerprint** into its content
  signature — a tag add/remove flips the signature → exactly one targeted rebuild, no new
  message, no scroll-yank (`ref: chat_stream_styling.dart:352-389`,
  `ref: chat/models/chat_item.dart:36-45`).

### 1c. Downstream use — tags REALLY route (this is the load-bearing finding)

The tags are **consumed by the operator loop**, not just displayed. The operator CLI
(`ref: agent-coordination chat.js`) does the following, all as **pure, unit-tested**
(`--selftest`) helpers:

- **Reads the owner's tags** off the live thread and resolves the **active lane** via a
  6-rule state machine — explicit tag wins, an untagged same-topic follow-up **inherits**
  the active lane (continuity), a new tag switches lanes, an explicit "clear" sentinel drops
  the lane, a confident topic-change leaves it untagged, repeated ambiguity raises a drift
  nudge (`ref: chat.js:229-300+`).
- **Mirrors the owner's lane onto its own reply by default** (zero flag), so the owner's tag
  and the operator's replies form one labelled thread (`ref: chat.js:15-25`).
- **Resolves `workflow:id → ownerAgent`** through a registry that **mirrors** the app's
  canonical set and the published workflow-status map, i.e. the tag names the **sub-agent /
  lane that should handle the message** (`ref: chat.js:60-86`).
- **Has an outgoing auto-classifier** (curated keywords ∪ label words ∪ owner-agent words,
  minus stopwords, strictly-greater-wins so ties resolve to *no tag* rather than a wrong
  lane) as a **backstop only** — it never overrides an explicit owner tag, and it **never**
  produces a `chatgpt` tag (`ref: chat.js:96-167`).

**So: the `workflow` dimension is a real routing key into a multi-agent operating model; the
`chatgpt` dimension is a real routing key into multiple external-LLM conversations.** Both
have a live consumer in the reference; neither is decoration.

---

## 2. Is this a reusable HARNESS capability, or app-specific?

**It is a reusable harness capability with a thin app-specific seam.** The split is clean
and the reference already isolates it (`PARITY_MAP_CHAT_AND_CLUSTER.md` §1c reaches the same
line):

| Piece | Generic (harness core) | App-specific (config / seed) |
|---|---|---|
| `tags[]` message schema `{id,kind,label,addedBy,addedAt}` | ✅ | — |
| Two-dimension concept (internal routing + owner free-form external-LLM label) | ✅ | — |
| Selection-bar **Tag / Label** action + picker UX (two sections, apply-to-all, common-checked, `+New` w/ colour) | ✅ | — |
| Chip render (primary/secondary, stripe, `+N` overflow) + stream-colour palette + deterministic default swatch | ✅ | — |
| Tagging controller (guard-real-doc → merge-write → poll → poke) | ✅ | — |
| Device-side override/registry store (recolour / rename / ad-hoc) | ✅ | — |
| Live re-render fingerprint (in-place tag edit → one targeted rebuild) | ✅ | — |
| Operator-side lane state-machine + inherit/continuity rules | ✅ (the *mechanism*) | — |
| The **work-lane SET** (the actual lane names/ids/owners) | — | ✅ app supplies a registry |
| The **classify keyword / alias map** + any export glossary blurbs | — | ✅ app-owned taxonomy |

**Two load-bearing observations:**

1. **The `chatgpt` free-form-label dimension is 100% generic** — no taxonomy, no registry,
   no app data at all. It is pure owner intent carried on the message. This is the slice
   that needs **zero config** to be correct in any app.
2. **Only the internal-`workflow` dimension needs app config** — the lane set + keywords.
   The reference already sources these from a project-level map (the app registry mirrors the
   operator registry mirrors the published workflow-status). The correct harness shape is:
   **the lane set + keywords come from the app's own config, never hardcoded** (this repo
   already has the seam — `ST: harness/project.config.json` carries a `lanes` block, and the
   generated `HarnessConfig` is the app-identity source). A port must **never copy the
   reference app's lanes**; it reads its own.

**Where a generic capability lands in the framework.** The framework docs already carve out
the exact home and the exact gate:
- Harness-core ships the owner tools including **orchestrator chat** as a core surface
  (`AH: docs/ARCHITECTURE.md:152-154`), and identity/labels flow from one committed config
  through the generated config (`AH: ARCHITECTURE.md:70-114`). A tagging module belongs
  beside the chat feature in harness-core, fed by config.
- **The multi-lane operating model is explicitly a documented-but-deferred layer, not the
  v0.1 baseline.** The framework keeps a **single orchestrator** as v0.1 and treats
  **sub-agent / lane fan-out** as "the bigger operating model," with an **open question** of
  whether it is even productized vs. kept as the owner's own practice
  (`AH: docs/OPERATING_MODEL.md:50-51, 113-125, 160-161`). That is exactly the gate the
  `workflow` dimension depends on.

---

## 3. The three options

Effort/risk are relative to this port. "Who benefits" is the decisive column.

### (a) Full two-dimension tagging (internal work-lane routing + free-form label)
- **Effort: HIGH.** Schema + tagging controller + two-section picker sheet + chip render +
  stream palette + device override store + a config-driven lane registry + the operator-side
  lane state-machine. It is the whole subsystem.
- **Risk: MEDIUM.** The design is additive (no rules change per the reference), but it is a
  large new UI surface + a new persistent store + a new operator code path — a lot to keep
  correct and anti-leak-clean.
- **Who benefits:** **only an app that runs a multi-lane orchestrator** that routes off
  per-message tags. With one lane there is nothing for the `workflow` dimension to route to —
  the tag would resolve to the single lane every time. **No payoff at one lane.**

### (b) Free-form conversation-label only (the generic, low-config slice)
- **Effort: MEDIUM.** Schema (one array) + controller + a **one-section** picker + chip
  render + palette + device store. **No registry, no keyword taxonomy, no operator
  state-machine** — the label just rides on the message and is echoed back on the reply.
- **Risk: LOW.** Additive array, no rules change, no app-specific data, no fuzzy classifier
  to get wrong.
- **Who benefits:** **any owner who juggles more than one external-LLM conversation** and
  wants replies to come back tagged into the right one. Independent of whether the app has a
  multi-lane orchestrator. This is the slice that delivers value **first**.

### (c) Stay deferred
- **Effort: ZERO.** The port already marks it deferred in its own code
  (`ST: chat/models/chat_item.dart:6`, `ST: chat/controllers/chat_message_controller.dart:12`).
- **Risk: ZERO now**, but it is a **standing parity gap** and leaves the reusable core
  unbuilt, so every future app re-derives it.
- **Who benefits:** correct **only while nobody consumes the tags** — i.e. while the operator
  bridge is off and no external-LLM routing need exists.

---

## 4. Recommendation

**Reclassify tagging from "deferred UI port" to "harness-core capability, config-gated,"
and build the GENERIC CORE — but ship scope (b) as the default and gate (a) behind a
`lanes` config flag. Recommended immediate scope: (b), architected so (a) is a config
flip, not a rebuild. Explicitly NOT (a) for this port yet; and (c) only as a deliberate
sequencing choice tied to the operator bridge (see caveat).**

**Rationale — anchored to the evidence:**

1. **(a) has no consumer here.** This port declares a **single** lane
   (`ST: harness/project.config.json` → `lanes.names` has one entry) and its **operator
   bridge is `off`** (`ST: harness/project.config.json` → `harness.orchestratorBridge`).
   The `workflow` routing dimension routes to sub-agent lanes; with one lane and no live
   loop, building it now is infrastructure for lanes that don't exist. The framework agrees:
   multi-lane is the deferred "bigger operating model," not the v0.1 baseline
   (`AH: OPERATING_MODEL.md:113-125`).
2. **(b) is the generic, first-payoff slice.** The `chatgpt` dimension is 100% generic
   (§2 obs. 1) — zero config, low effort, low risk — and it delivers the concrete win
   (route replies to the right external conversation) **without** a multi-lane orchestrator.
   Building it lands the reusable schema/controller/picker/chip/palette/store — i.e. the
   whole reusable **core** — as the by-product.
3. **(a) becomes a config flip, not a second project.** Because the split is clean (§2), the
   internal-`workflow` dimension is: turn on a second picker section + read the lane set +
   keywords from `lanes` in config + enable the operator lane state-machine. Gate it on
   `lanes.count > 1`. An app that grows a multi-lane orchestrator flips one flag and reuses
   the same core. **Never hardcode the lanes — always read the app's own config** (owner
   doctrine + the reference's own seam).
4. **(c) is the honest status-quo only until there is a consumer.** If the near-term
   priority is strictly "live value," even (b) has no consumer until the operator bridge goes
   `live`. That is a legitimate reason to *sequence* the build behind the bridge — but it is
   **not** a reason to leave the capability unbuilt in harness-core. The reusable core is the
   asset; build it once, gate its exposure per app.

**Net:** build the generic core now (value = the reusable asset + parity), **expose (b) by
default**, keep **(a) behind the `lanes` gate**, and let the operator-bridge state decide
*when* to surface even (b) in this particular port.

**Owner decision needed:** (i) approve building the generic core now vs. waiting for the
operator bridge to go live; (ii) confirm this port stays single-lane for the foreseeable
future (if a multi-lane operating model is imminent, that raises (a)'s priority).

---

## 5. Implementation outline (if "build it")

### 5a. Generic core (harness-core / this-repo `lib/features/dev/chat/`)

Land these as **app-agnostic** modules (no domain noun, no hardcoded lanes):

1. **Model** — extend the chat row with an optional `tags[]` and a `WorkflowTag`
   value-type `{id, kind, label, addedBy, addedAt}` + a defensive `listFrom(raw)` parser
   (skip malformed entries, normalise `kind` to `workflow|chatgpt`, dedup on `(kind,id)`).
   Additive: an untagged row is unchanged. (Mirror `ref: chat_stream_styling.dart:163-251`.)
2. **Tagging controller** — `applyTag/removeTag` + bulk `applyToAll`, each a
   **guard-real-doc → merge-write → immediate poll → poke** sequence; manual taps stamped
   owner-provenance; `addedAt` a **concrete** client timestamp (never a server-timestamp
   inside an array). (Mirror `ref: chat/controllers/chat_tagging_controller.dart`.)
3. **Picker sheet** — reached from the **existing** multi-select bar (add a `Tag / Label`
   action to `ST: chat/widgets/chat_selection_bar.dart`). Scope (b) = **one** section
   (free-form labels + `+ New label`); scope (a) adds the second **workflow** section fed by
   config. Apply-to-all with common-checked intersection semantics.
4. **Chip render + palette** — primary/secondary chip rows, left stripe by primary colour,
   `+N` overflow, deterministic default swatch (stable hash → swatch index), device-persisted
   overrides. (Mirror `ref: chat_stream_styling.dart:421-691`, `:17-55`.)
5. **Device store** — prefs-backed: stream colours, free-form labels (name+colour), workflow
   overrides, copied-set. Non-fatal load (defaults on any error).
   (Mirror `ref: chat/services/chat_styling_store.dart`.)
6. **Live-render fingerprint** — fold a per-message tag fingerprint into the render content
   signature so an in-place tag edit triggers one targeted rebuild, no scroll-yank.
7. **(a) only) Operator-side** — a pure, `--selftest`-covered lane state-machine in the
   operator CLI: resolve active lane (explicit > continuity-inherit > switch > clear-sentinel
   > topic-break), mirror onto replies, resolve `workflow:id → ownerAgent` from config, with a
   strictly-greater-wins keyword backstop that never overrides an owner tag and never emits a
   `chatgpt` tag. (Mirror `ref: chat.js:60-300+`.)

### 5b. Config shape (drives the app-specific seam; never hardcoded)

Extend the existing `lanes` block in `harness/project.config.json`. Sketch:

```jsonc
"tagging": {
  "conversationLabels": { "enabled": true },      // dimension (b): generic, no data needed
  "workflowLanes": {                               // dimension (a): gated on lanes.count > 1
    "enabled": false,
    "lanes": [
      // { "id": "<kebab>", "label": "<Lane>", "ownerAgent": "<agent>", "keywords": ["…"] }
      // read from THIS app's lane set — NEVER the reference app's lanes
    ],
    "stopwords": ["the","and","for","…"],          // generic/ambiguous tokens → no wrong tag
    "inheritWhenLatestUntagged": true,             // continuity master switch
    "topicBreakMinScore": 2,
    "driftThreshold": 3
  }
}
```

- **The generated `HarnessConfig` stays identity-only**; behaviour knobs (the tagging block)
  can live as config the app + operator both read, exactly as the reference keeps voice knobs
  as const-config separate from identity.
- **`workflowLanes.enabled` derives from / is gated on `lanes.count > 1`** so a single-lane
  app can't accidentally ship a routing dimension that routes nowhere.

### 5c. Where it lands in this port

- Core modules under `ST: lib/features/dev/chat/` beside the ported chat feature; the
  selection bar gains the `Tag / Label` action; the header optionally regains the stream
  palette (that header parity is the render half — defer with §1's stream-palette item).
- **Ship (b) enabled, (a) disabled** given today's single lane + `orchestratorBridge:off`.
  The operator lane state-machine lands (behind the flag) in the operator CLI
  (`ST: scripts/…`) so it is ready the day this port goes multi-lane + bridge-live.
- **Anti-leak:** run the existing config/anti-leak guard over any new script; the lane set is
  read from config so no reference-app lane can leak into this repo.

### 5d. How it generalizes to the framework

- The core module is app-agnostic and config-fed → it is a **harness-core** component
  documented alongside the chat surface in `AH: ARCHITECTURE.md` (owner tools) with the
  tagging config block added to the config pipeline (`AH: ARCHITECTURE.md:70-114`).
- Dimension **(b)** ships in the v0.1 single-orchestrator baseline (it needs no lanes).
- Dimension **(a)** is documented as part of the **sub-agent / lane operating model**
  (`AH: OPERATING_MODEL.md`, `SUB_AGENT_WORKFLOW.md`) and is enabled only when an app opts
  into multi-lane. This matches the framework's existing single-vs-bigger split exactly —
  tagging is not a special case; it is one more capability that is generic in core and
  config-gated per app.

---

## Facts / claims / risks / owner-decisions

- **Facts (verified from code):** tags are a structured additive `tags[]` array; two `kind`
  dimensions; the operator CLI reads tags and routes/mirrors replies off them (a live
  consumer, not decoration); this port declares one lane and `orchestratorBridge:off`; the
  framework keeps single-orchestrator as v0.1 and multi-lane as deferred.
- **Claims (asserted):** (b) is buildable at MEDIUM/LOW; (a) becomes a config flip on top of
  the same core; the split is clean enough that "generic core + config-gated dimensions" is
  the right shape.
- **Risks:** (a) is a large surface — schema + picker + store + operator path — and its value
  is **zero** until the app is genuinely multi-lane; building it early is speculative. Even
  (b) has no in-app consumer until the operator bridge goes live.
- **Owner-decisions:** build the generic core now vs. wait for bridge-live; confirm this port
  is single-lane for the foreseeable future (a near-term multi-lane plan would raise (a)).
