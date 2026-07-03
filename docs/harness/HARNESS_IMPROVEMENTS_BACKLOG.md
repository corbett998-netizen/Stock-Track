# Harness Improvements — Prioritized Backlog Board

> **What this is.** A single, prioritized, categorized board of harness-improvement work for
> the Stock-Track owner/operator harness (the machine that lets a non-coder owner run app
> development from their phone). It consolidates the parity/limitations/classification/tagging
> reviews into one picture so the owner can act fast.
>
> **How to read it.** Every item carries **Value / Risk / Effort** and one tag:
> - **[DONE]** — shipped + validated (evidence inline).
> - **[SAFE-NOW]** — safe + self-contained, no owner decision needed; can be built without review.
> - **[NEEDS-OWNER-REVIEW]** — a scope/size/setup call the owner must make first.
> - **[RISKY-NEEDS-PLAN]** — real value but a wrong move would weaken a guard or churn a surface;
>   needs a written plan before anyone touches it.
>
> **Ownership / no-collision map (read before picking up an item):**
> - **Tagging / workflow-labeling** — reviewed by the **tagging-review lane** (review COMPLETE:
>   `docs/harness/TAGGING_REVIEW.md`). Boarded here as **HI-11** with the two owner-decisions.
>   *Do not implement tagging code from this board* — it is a feature with an open owner-decision.
> - **Floating-cluster button layout / colours** — pending **owner review** (the cluster lane).
>   Cross-referenced as **HI-12**; *do not auto-apply* — muscle-memory surface, owner picks order.
> - Everything else below is free to pick up per its tag.
>
> **Sources:** `docs/brandon_handoff/04_HARNESS_SYSTEMS_CLASSIFICATION.md` (the 49-system A/B/C
> pass), `docs/brandon_handoff/06_KNOWN_LIMITATIONS.md`, `docs/harness/PARITY_MAP_CHAT_AND_CLUSTER.md`,
> `docs/harness/TAGGING_REVIEW.md`, `docs/harness/AUDIT_PLAN.md`.

---

## Counts per tag

| Tag | Count |
|-----|:---:|
| **[DONE]** | 5 (3 this pass + 2 prior) |
| **[SAFE-NOW]** | 5 |
| **[NEEDS-OWNER-REVIEW]** | 9 (4 harness + 5 owner-owed/setup) |
| **[RISKY-NEEDS-PLAN]** | 2 |
| **Total** | **21** |

## Top 5 (highest leverage next)

1. **HI-1/HI-2 — config-driven separation guard + anti-leak scanner** → **[DONE] this pass.** The
   safety backbone, now generalized to block *any* foreign project (not a fixed reference
   blocklist). The single highest-value non-UI improvement in the whole set (classification #19/#20).
2. **HI-11 — workflow tagging: build the generic core, ship the free-form label dimension**
   [NEEDS-OWNER-REVIEW]. Biggest reusable-capability + biggest parity gap; two owner-decisions.
3. **HI-12 — cluster colour-role palette + layout/mic/poke cleanup** [NEEDS-OWNER-REVIEW]. Daily
   muscle-memory surface; restore glanceable per-function colour identity without hardcoded literals.
4. **HI-9 — agent-first `emit_result` helpers + advisory new-script lint** [SAFE-NOW]. The output
   standard every harness script should conform to (classification #38); unlocks consistent PASS/FAIL.
5. **HI-6 — generalize the schema `$id` reference-app name → template name** [SAFE-NOW]. Cheap
   clean-template win; also closes a minor naming leak the (self-excluded) schema file bypasses.

---

## A. [DONE] — shipped + validated

### HI-1 · Config-driven anti-leak scanner (invert blocklist → allowlist) · [DONE]
- **Value:** HIGH. The scanner no longer depends on a hardcoded table of the reference app's
  literals; it derives the **allowed** project identity from `harness/project.config.json`
  (`firebase.projectId` + `firebase.storageBucket`) and FAILS *any* Firebase/GCP identity-shaped
  token whose slug isn't the configured project. Generalizes to any future project with no edits.
- **Risk:** LOW (net protection is a strict superset — see design note). **Effort:** done.
- **What changed** (`harness/harness_antileak_scan.sh`): added two config-driven layers —
  (1a) foreign Firebase bucket/domain slug check, (1b) foreign Firebase App-ID shape — and
  **retained** the reference-literal blocklist as **Layer 2 (defense-in-depth)**. Non-weakening
  by construction: the allowlist adds coverage; the blocklist stays for shapes an allowlist can't
  safely detect (bare owner UIDs, repo paths, package prefix).
- **Evidence (both directions):**
  - Clean tree → `ANTILEAK RESULT: PASS | 0 foreign identifiers ... | 55 files scanned | allowed=[easy-stock-track]` (exit 0).
  - Planted fixture (temp file, deleted after) → `FAIL` (exit 1) catching all three:
    `acme-widgets-prod.firebasestorage.app` **[foreign-firebase-identity]** (a foreign bucket
    **NOT in any blocklist** — proves generalization), a foreign Firebase App-ID
    `1:999888777666:android:...` **[foreign-firebase-app-id]**, and the reference project-id
    literal (the one the blocklist names) **[ref-firebase-project]** (blocklist backstop still
    fires). Re-scan after cleanup → PASS.
- Source: classification #20.

### HI-2 · Config-driven foreign-identity detection in `bp_guard.js` · [DONE]
- **Value:** HIGH. The runtime separation guard now blocks *any* foreign Firebase identity
  reachable from resolved config, not just the reference app's literals.
- **Risk:** LOW (additive; clean values still pass). **Effort:** done.
- **What changed** (`scripts/bp_guard.js`): added pure `findForeignFirebaseIdentity(values,
  allowedProjectId)` + `FIREBASE_IDENTITY_RX`; wired it into `assertStockTrackOnly` as an added
  block; named the independent pin `EXPECTED_PROJECT_ID` (deliberately **not** read from config so
  a tampered config can't re-point the guard); **kept** `findBpLeak`/`BP_FORBIDDEN` as the backstop.
  Exported the new symbols; extended the self-test.
- **Evidence:** `node scripts/bp_guard.js` → `BP-GUARD RESULT: PASS | 0 failing` (10/10, incl. 4 new
  foreign-identity cases). Downstream unaffected: `stocktrack_chat.js --selftest` 11/11,
  `stocktrack_workflow_status.js --selftest` 7/7.
- Source: classification #19.

### HI-3 · Annotate the inert `firebase.serviceAccountPath` (clean no-key story) · [DONE]
- **Value:** LOW–MED. Documents at the field that the path is a **reference only** — no key file is
  ever read at runtime (ADC-only), `service-account*.json` is gitignored — reinforcing the no-key story.
- **Risk:** LOW. **Effort:** done.
- **Note (corrects the intake premise):** the field is **not** unreferenced — the schema marks it
  `required` and `harness_config.js` self-tests its interpolated value — so **removal is not trivially
  safe** (would touch the schema `required` list + a self-test). Annotating (a schema-permitted
  `_comment`, no `${` so the "no leftover `${`" self-test stays green) was the correct safe action.
- **Evidence:** JSON valid; `harness_config.js --selftest` 18/18; `gen_app_config.js --check` up to
  date (the `_comment` does **not** leak into generated Dart); anti-leak PASS.

### HI-4 · Copy-message fade-to-gray + "copied ✓" badge · [DONE] (prior session)
- Pure presentation + one per-message boolean; matches the reference confirm. Shipped in the fresh
  build (`PARITY_MAP_CHAT_AND_CLUSTER.md` §2, limitations §4). Re-confirm on-device.

### HI-5 · Push-notification foreground banner fix · [DONE] (prior session)
- Foreground heads-up via `flutter_local_notifications` + Android-13 permission + high-importance
  channel + tap deep-link; proven on the builder's device (limitations §3, `PUSH_NOTIFICATIONS.md`).
  Re-confirm on the owner's device + Firebase.

---

## B. [SAFE-NOW] — safe + self-contained, no owner decision

### HI-6 · Generalize the schema `$id` reference-app name → template name · [SAFE-NOW]
- **Value:** MED (clean-template hygiene). `harness/project.config.schema.json` `$id` is
  `https://blueprint-harness/...` — it carries the reference app's name into a would-be-public
  artifact. The config references the schema by **relative path** (`"$schema": "./..."`), not by
  `$id`, so changing `$id` breaks nothing.
- **Why not done here:** it's a **naming decision** (the classification doc calls the public template
  "Appharness") and the schema is **excluded** from the anti-leak scan, so this is the one spot a
  reference-name can hide from the gate — worth an explicit owner nod on the chosen template name.
- **Risk:** LOW. **Effort:** LOW (one line).

### HI-7 · Config-pathed `gather_signals` for the objective harness reviewer · [SAFE-NOW]
- **Value:** MED–HIGH. An outside agent that reviews *how we work* and returns a ranked TOP-5 is
  high-leverage, but the reference signal-gatherer hardcodes repo paths and carries reference
  examples. Re-express it config-pathed + scrub the prompt. (classification #30.)
- **Risk:** LOW. **Effort:** MEDIUM. Not present in this repo yet → net-new, hence boarded not built.

### HI-8 · Logging enable/capture scripts — config-driven + cross-platform · [SAFE-NOW]
- **Value:** MED. Keep the pattern (logs off-by-default for perf; enable + capture on demand); the
  current scripts are PowerShell + reference paths. Re-express reading `paths.logsDir` from config,
  cross-platform. (classification #49.)
- **Risk:** LOW. **Effort:** MEDIUM.

### HI-9 · Agent-first `emit_result` helpers + advisory new-script lint · [SAFE-NOW]
- **Value:** HIGH. The output contract every harness tool obeys (one `RESULT: PASS/FAIL/BLOCKED`
  line, documented never-swallowed exit map, `class=`/`retryable=`, definitive empty states,
  `--help`, human-vs-agent modes). Ship `tool_lib.sh`/`tool_lib.ps1`/`tool_result.js` + an advisory
  new-script lint so future scripts conform. (classification #38.)
- **Risk:** LOW (additive helpers). **Effort:** MEDIUM.

### HI-10 · File-size / refactor tripwire reading `fileSizeGuard` from config · [SAFE-NOW]
- **Value:** MED. Deterministic god-file gate (WARN>500 / JUSTIFY>800 / HARD-STOP>1200, growth-aware,
  `ARCH-OK` exemption) — thresholds already sit in `fileSizeGuard` in config. No-LLM, milliseconds.
  (classification #32.)
- **Risk:** LOW. **Effort:** LOW–MEDIUM.

---

## C. [NEEDS-OWNER-REVIEW] — scope / size / setup calls

### HI-11 · Workflow tagging — build the generic core, ship the free-form label dimension · [NEEDS-OWNER-REVIEW]
> First-class board item, sourced from the **completed** review `docs/harness/TAGGING_REVIEW.md`.
> *Do not implement in this pass* — feature with an open owner-decision. (`PARITY_MAP...` §1,
> classification #6.)
- **Recommendation (from the review):** reclassify tagging from "deferred UI port" to a
  **harness-core capability, config-gated**. **Build the generic core now** (schema / tagging
  controller / picker / chip render / stream palette / device store) and **ship dimension (b), the
  free-form "which external-LLM conversation is this for" LABEL, by default** (100% generic, zero
  config, MEDIUM effort / LOW risk). **Gate the full internal work-lane ROUTING dimension (a) behind
  `lanes.count > 1`** — this port declares **one** lane and its operator bridge is **off**, so
  routing has nothing to route to yet (building it now = infrastructure for lanes that don't exist).
- **Generic core vs app-specific seam:** generic = schema `{id,kind,label,addedBy,addedAt}` +
  picker + chip render + palette + store + controller. App-specific = **only** the lane-set +
  keyword map, and those must be **read from config, never hardcoded** (never copy the reference
  app's lanes).
- **⚠ Portability landmine (must carry into any build):** the tag `addedAt` must be a **concrete
  client timestamp** — a `serverTimestamp()` is **illegal inside an array element**. Document it in
  both the app writer and the operator writer.
- **Effort:** (a) HIGH / (b) MEDIUM. **Risk:** (a) MEDIUM / (b) LOW.
- **OWNER-DECISION 1:** build the generic core **now** vs. **wait** for the operator bridge to go
  live (even (b) has no in-app consumer until the bridge is `live`).
- **OWNER-DECISION 2:** confirm this port **stays single-lane** for the foreseeable future (a
  near-term multi-lane plan would raise dimension (a)'s priority).

### HI-12 · Floating-cluster layout/colours + colour-role palette · [NEEDS-OWNER-REVIEW]
> Owned by the **cluster / owner-review** lane. Cross-ref only — *do not auto-apply* (muscle-memory
> surface). (`PARITY_MAP...` §3, limitations §5.)
- **Recommendation (held for owner):** (a) restore a small themeable **colour-role palette**
  (`primaryAction`/`report`/`utility`/`mic`/`review`) feeding `HarnessToolSpec.color` so tools are
  glanceable by colour again (currently all one accent) — no hardcoded literals; (b) move the **mic
  off the top slot** (reference keeps it low); (c) demote the redundant **Poke** (the send/tag nudge
  already pokes) + the vestigial **Command center** button. All one-line config edits.
- **Effort:** LOW. **Risk:** LOW — but the **final button ORDER is the owner's call**.

### HI-13 · Chat-header parity (stream-colour palette, copy-work-area) · [NEEDS-OWNER-REVIEW]
- The 3 missing header actions are the render/UX half of tagging and **ride on HI-11's scope
  decision**. Defer until HI-11 scope is set. (`PARITY_MAP...` §1b/§4.5.)

### HI-14 · Run the independent readiness AUDIT (8 GO/NO-GO gates) · [NEEDS-OWNER-REVIEW]
- A written 8-gate GO/NO-GO plan exists (`docs/harness/AUDIT_PLAN.md`: separation, no-secrets, real
  no-key access, live chat loop, reports-with-evidence, dogfood loop, on-device reachability,
  stand-up-from-docs) but has **not** been executed by an independent reviewer (limitations §10).
  Owner commissions the independent pass; some gates only green on the owner's own setup.

### Owner-owed / setup (from Known Limitations — owner action required) · [NEEDS-OWNER-REVIEW]
- **HI-17 · Signed release keystore + iOS build** — debug APK today; a deliberate, long-lead
  owner-generated keystore (never committed) + a Mac for iOS are owed later (limitations §1).
- **HI-18 · App Distribution pipeline** — owner enables App Distribution + tester group in their
  Firebase console; until then delivery is by file/link (limitations §2).
- **HI-19 · Enable Storage** — owner switches Storage on (off by default) to unlock screenshot
  attach/retrieval and in-chat images; orchestrator deploys `storage.rules` (limitations §7).
- **HI-20 · Real saved data (replace in-memory mock)** — a later, well-scoped slice behind the
  existing data interface (limitations §6).
- **HI-21 · In-chat image/file send** — Storage-gated deferred fast-follow (limitations §9).

---

## D. [RISKY-NEEDS-PLAN] — real value, but needs a plan first

### HI-15 · Full inversion: remove the reference-literal blocklist entirely · [RISKY-NEEDS-PLAN]
- **Deliberately NOT done.** The task's ideal is a *pure* allowlist ("flag anything foreign, drop the
  blocklist"). A pure allowlist **cannot** safely detect **bare owner-UID** leaks (a 28-char
  alphanumeric is indistinguishable from a legitimate Firestore doc id) or bare foreign project-ids
  with no domain suffix — so removing the blocklist would **weaken** protection for exactly those
  shapes. Per the guardrail ("if it can't be done without weakening the guard, board it"), I kept the
  blocklist as defense-in-depth and added the config-driven allowlist on top (HI-1/HI-2).
- **Proposed approach if pursued:** a shape/entropy heuristic for bare identifiers (length + charset
  + entropy) plus an **allowlist of legitimate doc-id patterns** the harness itself uses, validated
  against the whole clean tree for zero false positives before the blocklist is retired. Non-trivial;
  needs its own validation harness. **Value:** LOW (current dual-layer already generalizes).
  **Risk:** HIGH if rushed.

### HI-16 · App-ID shape detection inside the *runtime* `bp_guard` value scan · [RISKY-NEEDS-PLAN]
- **Deliberately NOT added to the runtime guard.** The static file scanner flags foreign App-IDs
  safely (no legit own App-ID appears in the scanned framework files), but if the runtime guard
  scanned config **values** for App-ID shapes, a future legit `distribution.appDistributionAppId`
  (the app's **own** App-ID) could be a **false-positive block**. **Plan:** only add it once the
  guard can compare against the app's own configured App-ID (allowlist-aware), not a bare shape
  match. **Value:** LOW. **Risk:** MED (false-green vs false-block).

---

## Design note — why "additive, not pure-inversion" is the correct guard change

The intake asked to invert the guard to config-driven "instead of a hardcoded blocklist," *while
keeping the current protection*. Those pull in opposite directions for shapes an allowlist can't
detect. The resolution shipped here: the **config-driven allowlist is the new generalizing PRIMARY
mechanism** (it blocks any foreign project, proven against a bucket that was never in the blocklist),
and the **reference-literal blocklist is retained as a defense-in-depth backstop** for bare
UID/path/package shapes. Net protection is a **strict superset** of the prior version — nothing was
weakened, and the guard now generalizes to any project via `project.config.json`. The pure-removal
variant is boarded honestly as **HI-15 [RISKY-NEEDS-PLAN]**.
