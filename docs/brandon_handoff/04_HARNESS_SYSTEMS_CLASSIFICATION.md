# 04 — Harness Systems Classification (A / B / C)

> **What this is.** A deliberate, system-by-system pass over every notable piece of the
> owner/operator **harness** — the machine that lets a non-coder owner run app development
> from their phone — classifying each for a **reusable public template ("Appharness")**.
>
> **Why it exists.** The harness was built for one reference app and then re-instantiated
> and proven a second time in Stock-Track. That second instantiation is the proof it is
> *reusable*. This doc turns that proof into a clean shopping list: what to lift straight
> into the template, what to lift but scrub of app-specific names/assumptions first, and
> what to leave behind.
>
> **Guiding principle (owner-stated):** *generalize — do not delete a useful lesson just
> because it happens to mention the reference app.* A system that names the original app
> is almost never class C; it is almost always class B (keep it, rewrite the names out).
> C is reserved for things that are genuinely private, genuinely app-specific product, or
> dead weight for a single-owner template.
>
> **Patterns-only.** This doc names no reference-app identifiers (project ids, owner uids,
> app ids, bucket names, clean-room names). Those were read only to classify. Destinations
> named here — **Appharness core** (the public template) and **Stock-Track handoff** (this
> repo's own instance) — are this project's own, not the reference app's.

---

## Classification key

| Class | Meaning | Template action |
|-------|---------|-----------------|
| **A** | **Keep as a generic Appharness pattern.** Already app-agnostic (or trivially so) — reads identity from config, names no app. | Lift verbatim into Appharness core. |
| **B** | **Keep, but rewrite / sanitize.** Real, reusable value, but the current artifact bakes in reference-app names, paths, taxonomies, or infra. Generalize it (usually: drive it from `project.config.json` instead of literals). | Lift the *pattern*; regenerate the app-specific parts from config. |
| **C** | **Remove from the public template.** Truly private/sensitive, the reference app's *product* (not harness), or dead weight only a mature multi-lane fleet needs. | Do not ship in the template. (Any generic *lesson* inside it already lives as doctrine.) |

**Destination legend:** *Core* = Appharness core (the reusable template). *Handoff* = the
Stock-Track instance (this repo's concrete, config-pinned copy). *Both* = the generic
pattern lives in Core and a config-pinned instance lives in the Handoff.

---

## Group 1 — In-app owner/operator surfaces (the phone side)

| # | System | Class | One-line rationale | Generic form (A/B) | Lives in |
|---|--------|:---:|--------------------|--------------------|----------|
| 1 | Release-safe dev gate (`!kReleaseMode`) | **A** | Pure compile-time flag; the whole harness is present in dev, structurally absent + zero-cost in a real release. No app identity. | Compile the entire harness behind one dev flag. | Core |
| 2 | Floating dev-tool overlay / draggable cluster | **A** | Mounted above the Navigator at the `MaterialApp.builder` seam so it floats over every route; button set already **config-driven** (a strict improvement over the reference's hardcoded child list). | Overlay at the builder seam + config-driven tool list + persisted fractional position + merged count badge. | Core |
| 3 | Command center / harness home (backend-mode, owner uid, build, open-counts, backend-not-ready state) | **A** | Reads generated config; shows which backend/user/build a session is on; degrades to an actionable "not ready" instead of a crash. | Status card driven by `HarnessConfig`. | Core |
| 4 | Two-way orchestrator chat (keyboard/nav-safe composer, live stream + poll + offline queue, copy-out, multi-select, ChatGPT export) | **A** | The chat modules already read generated `HarnessConfig`; all identity is config. Copy-out + export are the owner's most-used levers and are app-agnostic. | Config-driven chat feature package. | Core |
| 5 | Workflow dashboard sheet (read-only state + stale/fresh banners) | **A** | Generic read-only surface over a config-named `workflowContext` doc; loudly reads "stale" when unpublished. | Read the configured context doc; banner on staleness. | Core |
| 6 | Two-dimension workflow tagging + per-stream colours | **B** | The *mechanism* is generic (additive `tags[]` schema, picker, chip render, palette, controller). But the **workflow SET, keyword/alias map, and export glossary are app data** — the reference lanes must never be copied. | Land schema/controller/picker/render/palette in Core; **seed the lane set + keywords from this app's own config**. Free-form "which external-LLM chat" label is 100% generic; only the internal-routing dimension needs a config seed. | Both |
| 7 | Voice / mic dictation (into composer + mic-to-report) | **B** | Capability is a headline phone lever and belongs in the template — but via the **OS speech seam** (generic), not the reference's bundled offline dual-engine + A/B toggle (that heavy piece is C, row 48). | OS speech-to-text into the composer/report note. | Core |
| 8 | Chat image / file attachments (Storage-backed, inline render, tap-to-zoom) | **A** | Owner-scoped Storage path is config-driven; sending a screenshot to the operator is real workflow power. Gated only on Storage being enabled. | Config-scoped upload seam + inline attachment render. | Core |
| 9 | Push notifications (FCM, carried-message overlay, deep-link, ADC send) | **A** | **Already generalized** — framework files name no app; all identity in `push.*` config; the operator sends via Admin-SDK over ADC (no key). The native channel id is legitimate per-app identity, not framework. Model example of a clean port. | Config-driven FCM service + carried-message overlay + injected `openChatSurface` hook. | Core |
| 10 | Bug/report capture flow (note + multi-screenshot + device logs at submit + rich metadata + report-ID + resume draft) | **A** | Writes to a config-named reports collection; the note/screenshot/logs/metadata bundle is app-agnostic; screenshots are how a non-coder shows a visual bug. | Config-driven capture screen writing `{note, screenshots{url,path,bytes,contentType}, logsInline, deviceInfo, appBuild, route}`. | Core |
| 11 | Device logging system (master gate + ~3 category toggles + bounded ring buffer + `snapshot(percent)`, DCE'd in release) | **A** | The logger is the source of the device logs a report carries — generic. Note: ship ~3 **generic** categories; the reference's verbatim domain-logger list is C (row 47). | Generic ring-buffer logger with a `snapshot` slice. | Core |
| 12 | Report queue / triage (tolerant read model, filter buckets, recommend-then-act strip, correct reopen path, comments, screenshot zoom, device-log-tail view) | **A** | Reads a config collection; "**nothing sits at 'new'** — recommend-then-act, Execute/Discuss, resolved-wins, Fixed-vs-Won't-fix" is a generic owner-triage behavior, not app-specific. | Config-driven queue with the recommend-then-act triage strip. | Core |
| 13 | Dogfood checklist + Works / Still-broken verify loop | **A** | The owner-verify loop *is* the proof: announce-build → auto check-item → in-app "Ready to test" → **Works** (canonical resolved write) / **Still broken** (reopen + flag). Fully app-agnostic mechanism. | Config-driven check-item write + Ready-to-test sheet + shared resolved/reopen helpers. | Core |
| 14 | Report-ID tracing (short id on submit + copy button, used as a handle in chat + `--id` in the CLI) | **A** | A short stable handle to reference a report across chat/queue/CLI — generic. | Short-id stamp + copy + `--id` lookup. | Core |
| 15 | Route/region tagging on reports ("which screen was I on") | **B** | The route *tracker* is generic and the fastest triage signal — but the **region/area taxonomy is app-specific**; the reference route taxonomy must be reseeded, never copied. | Generic route tracker; derive the region taxonomy from this app's own nav. | Both |

---

## Group 2 — Backend / operator loop (the off-device side)

| # | System | Class | One-line rationale | Generic form (A/B) | Lives in |
|---|--------|:---:|--------------------|--------------------|----------|
| 16 | Operator chat CLI (`--read` w/ `maxMillis` cursor, `--send`, `--build`, `--dry-run`, `--selftest`) | **B** | The pattern is generic and already re-instantiated as a config-pinned script here; the reference's own CLI is welded to reference identity. The template ships a **config-driven** CLI, not the literal-bound original. | One CLI reading `project.config.json` for all identity; agent-first PASS/FAIL output. | Both |
| 17 | Poke doc + "the message IS the poke" + poke consumer/wake | **A** | Poll-free wake model; the poke doc path is config-driven and the writer/consumer pair is app-agnostic. | Config-named poke doc bumped on send/report + a consumer loop that wakes `--read`. | Core |
| 18 | **Config substrate** (`project.config.json` → generated app config + shell exports; JSON schema; `gen_app_config.js`) | **A** | This generator seam is *what makes the harness reusable at all* — one file of names/paths/ids (never secrets), `${a.b}` interpolation, `--check` staleness gate. Already fully generic. | The config file + schema + generator, verbatim. | Core |
| 19 | Cross-project separation guard (runtime "refuse to touch any project but the pinned one") | **B** | The *discipline* is a non-negotiable and must be Core — but the current artifact hardcodes the reference app's literals **by design** (a blocklist). For a template, invert it to **config-derived**: allow only the configured project id; block everything else. | A guard that reads the allowed project id from config and aborts on any mismatch. | Both |
| 20 | Anti-leak scanner (mechanical separation gate over the framework file set) | **B** | Same shape as #19: valuable and required, but currently a **hardcoded literal table** of the foreign app's identifiers. Generalize to derive the forbidden set from config (or take the foreign literals as an input list). | Config-driven scanner: FAIL if any identifier not in `project.config.json` appears in framework files; one `RESULT: PASS/FAIL` line. | Both |
| 21 | No-key / ADC auth model | **A** | Pure security principle: the operator authenticates via `gcloud application-default`, never a committed service-account key; the owner grants access by **IAM permission only**. Cross-project, non-negotiable. | "ADC + permission-grant, never a key" as a documented invariant + the wiring that assumes it. | Core |
| 22 | Firebase owner-setup runbook (plain-English console steps) | **B** | A reusable "owner switches on their own cloud" runbook (create project, register app, enable Auth/Firestore/App-Dist, hand back the client config, **never share admin keys**). Already generalized to a target app; just template the app-specific names. | Parameterized plain-English runbook keyed off config values. | Both |
| 23 | Push validation checklist (on-device owner acceptance) | **A** | Already patterns-only and generic: the 6-step "background → operator sends → phone pings → tap deep-links → renders, no dupes" acceptance flow. | The acceptance checklist as-is. | Core |
| 24 | Storage validation / owner-scoped Storage rules | **B** | The owner-scoped rules template is real value, but the concrete rules embed app-specific collection paths. Drive the paths from the configured collections + keep the enable-Storage gate. | Owner-scoped `storage.rules` template keyed off `collections.*` + a validation step. | Both |
| 25 | Backend path verification (a `backendDirs` config list + "the backend actually deploys" check) | **B** | Keep the **principle** — verify the backend path really ships, don't assume a local commit deployed. Sanitize the reference's specific infra (its hosting provider, its ports, its deploy script names → C, row 47). | `backendDirs` in config + a documented "prove the backend deployed" step. | Both |

---

## Group 3 — Build / ship / distribution

| # | System | Class | One-line rationale | Generic form (A/B) | Lives in |
|---|--------|:---:|--------------------|--------------------|----------|
| 26 | Build + deploy APK ship pipeline (clean build → monotonic versionCode → distribute → one PASS/FAIL/BLOCKED line) — incl. the `ship-apk` skill packaging | **B** | The ship *pattern* is generic and already re-instantiated here as a config-pinned script with a defensive separation abort. The reference's **clean-room mechanics** (its named worktree, its Windows-git deploy script) are app/machine-specific → C (row 47); the pattern + a pinned instance stay. | Config-pinned ship script: pinned project/app/tester-group, monotonic versionCode counter, agent-first RESULT line, separation guardrail. | Both |
| 27 | APK signing / install policy | **B** | The **principle** is generic and worth codifying: debug-signed builds for internal dogfood now; the owner's *own* release keystore is a deliberate long-lead item; **signing material is never committed**. The reference's specific keystore is C. | "Debug for internal, deliberate keystore later, never commit signing material" as a policy + `.gitignore` block. | Both |

---

## Group 4 — Orchestration & process doctrine

| # | System | Class | One-line rationale | Generic form (A/B) | Lives in |
|---|--------|:---:|--------------------|--------------------|----------|
| 28 | Sub-agent orchestration operating model (main orchestrator triages/boards/sequences; lanes own workstreams; poke-first, no idle loops; one channel to the owner; delegate to leads) | **B** | The *model* is highly reusable and valuable. But the concrete fleet tooling (the reference's chat scripts, broadcast rule-ledger, terminal-multiplexer fleet, respawn wrappers) is welded to a mature multi-lane setup; a single-owner template ships the **doctrine**, not the fleet. Heavy multi-lane infra → C (row 48). | The operating-model doctrine (roles, poke-first, one-channel, delegate-to-leads) as portable docs. | Core |
| 29 | Startup / boot procedure (arm chat + inbox monitors, a slow safety-net heartbeat, paste-ready lane starters) | **B** | Generic, repeatable boot pattern; the reference's specific boot scripts + multiplexer + bot names are infra-specific. | A documented "bring the control room up" procedure + a paste-ready starter template. | Core |
| 30 | Objective harness reviewer (fresh agent reviews *how we work*; ranked TOP-5; signal-pack gatherer; reviewer prompt; incident + structural-flag ledgers) | **B** | The idea is generic and high-leverage (an outside agent finds the friction the doers normalized). Sanitize the signal-gatherer's hardcoded repo paths → config, and scrub reference examples from the prompt. | Config-pathed `gather_signals` + a generic reviewer prompt + the ranked-TOP-5 output template + ledgers. | Core |
| 31 | Evidence-first validation gate (a separate validator runs an acceptance checklist before "done"; function gate + health gate; independence is mechanical, not self-claimed) | **A** | Pure doctrine; app-agnostic; the backbone of "coherent builds, not half-validated claims." | The two-gate SOP + a validator artifact template. | Core |
| 32 | File-size / refactor tripwire (deterministic god-file gate: WARN>500 / JUSTIFY>800 / HARD-STOP>1200, growth-aware, `ARCH-OK` exemption) + the repeatable monolith-refactor pattern | **A** | No-LLM, milliseconds, thresholds already in `fileSizeGuard` config; growth-aware so it never fights the cleanup it enables. The refactor pattern (isolated worktree + independent reviewer + the stale-base landmine) is generic. | The tripwire script (thresholds from config) + the refactor-pattern doc. | Core |
| 33 | Logs-first debugging doctrine (every report carries device logs; diagnose from logs before coding; investigate → plan → implement, no layered patch-fixes) | **A** | Pure doctrine; generic; realized by the device-logs-on-reports mechanism (#11) + rich capture (#10). | The doctrine, as a portable rule. | Core |
| 34 | Rich evidence intake bundle (screenshot + device-log tail + mic on reports) | **A** | The owner named this as one system; it is the app-agnostic union of #7/#10/#11 — the "no diagnosing blind" affordance. | Bundle doctrine, realized by rows 7/10/11. | Core |
| 35 | Morning-report / status-brief format (self-contained plain-English 6-section brief for pasting into an external LLM; the per-decision ask shape) | **B** | The **format** is generic and excellent (screen-anchored, no jargon, WHERE-WE-ARE → WHAT-CHANGED → WHO'S-ON-WHAT → REQUIRED-OF-YOU → HANGING → NEXT). Sanitize the reference examples + the specific delivery channel. | The 6-section template + the `Decision/Owner/Screen/Why/Options/Default` ask shape. | Core |
| 36 | Owner decision gates (a durable DIRECTED / AWAITING / BLOCKED / RESOLVED decision register; "no report sits at 'new' — recommend + move"; terse-instruction-lock; point-form-requirement-before-spec) | **B** | The mechanism is generic and load-bearing (intent survives session death; the owner acts fast). This repo already has the generalized instance; just template the owner-named doc. | A decision-register template + the recommend-then-act + terse-lock rules. | Both |
| 37 | "No done without evidence" doctrine (evidence over trust; unit tests are NOT sufficient proof for a product-facing fix; reproduce end-to-end; separate facts / claims / risks / owner-decisions) | **A** | Cross-project owner-level doctrine; already portable; the reason the whole validation model has teeth. | The doctrine, verbatim. | Core |
| 38 | Agent-first tool output contract (one `RESULT: PASS/FAIL/BLOCKED` line; documented exit-code map never swallowed → no false-green; failure `class=`/`retryable=`; definitive empty states; `--help`; human-vs-agent modes) + drop-in `emit_result` helpers + advisory new-script lint | **A** | Fully generic already; it is the *standard every harness script obeys* — the contract that makes tool output legible to agents and to a non-coder owner. | The contract doc + `tool_lib.sh` / `tool_lib.ps1` / `tool_result.js` + the advisory lint. | Core |
| 39 | Global agent doctrine (quality-over-assumed-cost, match-depth-to-risk, durable-fixes-over-band-aids, reproduce-before-fix, evidence-over-trust, no-editing-generated-files, preserve-owner-intent, coordinate-via-lanes) | **A** | Explicitly cross-project, owner-level, already written to be portable; the doctrine spine the rest hangs off. | The doctrine file, verbatim. | Core |
| 40 | Handover schema / don't-revert invariants (Status / What's-Next / Open-Questions / **Don't-Revert Invariants** / Session-Log) | **A** | Generic doc contract; already app-agnostic; the "Don't-Revert Invariants" section is the load-bearing safety rail across sessions. | The schema, verbatim. | Core |
| 41 | Orchestrator handoff / fleet restart (rotate the orchestrator, live-state handoff, RESTART MATRIX, per-lane paste-ready starters) — incl. the `orchestrator-handoff` skill | **B** | The **pattern** (beat the "dumb zone," hand off live state repeatably) is generic; the reference's multiplexer/respawn-wrapper infra is not. | The handoff procedure + RESTART MATRIX + starter templates, infra-agnostic. | Core |

---

## Group 5 — Skills (packaged runbooks)

| # | Skill | Class | One-line rationale | Lives in |
|---|-------|:---:|--------------------|----------|
| 42 | `code-health-audit` | **A** | Generic multi-agent code-health audit (architecture, types, quality, observability, perf, a11y, security) — no app identity. | Core |
| 43 | `triage-report` | **B** | Generic pattern (poll the error queue → pull report + screenshots → assess → route → titled-ack → close) but wired to the reference app's collections/uids + footguns. Sanitize to config. | Both |
| 44 | `spinup-agent` | **B** | Generic (produce a paste-ready looping downstream-agent starter) but keyed to the reference fleet's inbox/starter format. Sanitize. | Both |
| 45 | `canonical-profile-restore` | **C** | Domain-specific: recovering a reference-app test fixture (a program/profile regen for one product). Not generally useful. The generic lesson ("a canonical test fixture can get clobbered; verify before you mutate it") already lives as doctrine. | — (drop) |

> (`ship-apk` skill → folded into #26; `orchestrator-handoff` skill → folded into #41.)

---

## Group 6 — Leave behind (C): reference-app product & mature-fleet weight

| # | System | Class | One-line rationale | Lives in |
|---|--------|:---:|--------------------|----------|
| 46 | Reference-app **product / domain pipelines** (intake→program generation, the "rolling evolve" system, per-session capacity/load systems, category/content systems, cardio/interval systems, the frequent-practice screen, exercise databases, ML training + inference, post-workout coaching) | **C** | This is the reference app's *product*, not harness. No template value. Any generic engineering lesson inside it ("verify against real data, not unit logic"; "migration fixes need runtime proof") already lives as doctrine (#33/#37). | — (reference app only) |
| 47 | Reference-specific **infra specifics** (its named clean-room worktree + Windows-git deploy script; its hosting provider + backend ports; its verbatim log-category/domain-logger list; its keystore) | **C** | Machine/infra/product-specific plumbing behind otherwise-generic patterns (rows 11, 25, 26, 27). Keep the pattern; drop these specifics. | — (drop; patterns kept elsewhere) |
| 48 | Mature **multi-lane fleet infra** (region-sharded queue with pick/freeze/reclaim; deterministic two-dimension lane tagging; multi-agent dashboard; terminal-multiplexer fleet + respawn wrappers; a second "backup" orchestrator; the offline dual-engine mic + A/B toggle) | **C** | These exist to coordinate a mature, domain-specific, multi-lane fleet. A single-owner template has nothing to coordinate; copying them adds surface + risk with no reusability signal. Reintroduce only if/when a project actually runs a multi-lane fleet. | — (advanced/optional, not first template) |
| 49 | Logging **enable/capture scripts** (mostly-off-for-perf logging toggled on-demand) | **B** | The *pattern* (logs off by default for perf; enable + capture on demand) is generic and worth keeping; the current scripts are PowerShell + reference paths. Re-express config-driven + cross-platform. | Both |

---

## Summary

### Counts per class

| Class | Count | What it means for the template |
|-------|:---:|--------------------------------|
| **A — keep generic** | **26** | Lift straight into Appharness core. |
| **B — keep + sanitize** | **19** | Lift the pattern; regenerate app-specific parts from `project.config.json`. |
| **C — leave behind** | **4** | Reference-app product / infra specifics / mature-fleet weight. (Their generic lessons already survive as doctrine.) |
| **Total** | **49** | (Rows 42–45 = skills; two more skills folded into #26/#41.) |

> **Read the ratio as the headline:** 45 of 49 systems (A+B) belong in the template — only
> 4 are genuinely leave-behind. That is the owner principle in numbers: the harness
> generalizes almost entirely; naming the reference app made a system **B (sanitize)**, not
> **C (delete)**. The single biggest sanitization theme is "**drive it from config instead
> of hardcoded literals**" — it turns most B rows into A.

### Top 5 to generalize into Appharness first

Chosen by leverage **and** dependency order (each unlocks the ones after it):

1. **Config substrate (#18) — the foundation.** `project.config.json` + schema + generator.
   Everything else reads identity from here; nothing else can be cleanly generalized until
   this is the single source of app identity. Already generic — extract it first.
2. **Separation guard + anti-leak scanner (#19 + #20), made config-driven.** The safety
   backbone. Before any second app wires a backend, the template must be *provably* unable
   to cross-write another project — and it must prove it by reading the allowed id from
   config, not a hardcoded blocklist. Highest-risk to get right; do it early.
3. **Agent-first tool output contract + `emit_result` helpers (#38).** The output standard
   every harness script obeys. Extract it before porting the other tools so they all
   conform (one legible PASS/FAIL/BLOCKED line, no false-green).
4. **The in-app owner/operator surface bundle (#1–#5, #10–#14).** Dev-gate + overlay +
   chat + report capture + queue + dogfood Works/Still-broken loop. Mostly already A and
   config-driven; package it as Core — it *is* the daily workflow power and the whole point
   of the harness.
5. **The operator backend loop (#16 + #17 + #21 + #9), config-driven.** Chat CLI + poke +
   no-key/ADC + push. This is the off-device half that closes the loop; generalize the
   reference's literal-bound CLI into a config-driven one so a new owner's orchestrator can
   read/reply/ship/notify out of the box.

> **Honorable mention — the doctrine spine** (#31, #32, #33, #36, #37, #39, #40): these are
> already portable and cost almost nothing to include. Ship them alongside the top 5 — they
> are what make the harness *trustworthy*, and they are the cheapest wins in the whole set.
