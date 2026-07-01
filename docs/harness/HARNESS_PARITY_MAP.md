# Stock-Track Owner/Operator Harness — Parity Map & Build Plan

**Date:** 2026-07-01
**Owner:** Brandon · **Project:** Stock-Track (`easy-stock-track`, `com.stocktrack.stock_track`, owner role `brandon`)
**Purpose:** Define what the *reusable owner/operator harness* must do, compare it one-for-one to the current Stock-Track port, and give an implementation agent an ordered, no-missing-pieces build plan to turn the current skeleton into a true reusable-harness proof.

> **What this harness IS.** A dev-gated, on-device control surface that lets a non-coder owner *run development of his own app from his phone*: talk to an orchestrator, file bugs with real evidence (screenshots + device logs), triage a queue, and verify shipped fixes — all reachable from anywhere in the app, and all wired to a backend the orchestrator reads/writes off-device. The proof is **workflow power preserved**, not a visual clone and not a skeleton.

> **Source note.** Everything below describes the *reference harness* generically as reusable **patterns** — no other project's internals. All concrete file paths are **Stock-Track's own** (this repo, repo-relative), so this doc is safe to commit here and hand to the next implementation/orchestrator agent.

---

## 0. Reconciliation with the owner's live preview observations

The owner ran the current Stock-Track preview APK and reported: (a) a harness page with Orchestrator chat / File a report / Report queue / Poke exists; (b) chat opens but the **input sits partly behind the Android nav area — awkward/unusable**; (c) chat is **missing mic + image/file/share** controls; (d) file-report has a text box + add-screenshot but **doesn't feel like the full reporting flow**; (e) **no full floating dev-tool layout**; (f) **missing** the full bug-report stack, mic-to-report, issue-list behavior, dogfood checklist, and full command-center tools; (g) overall feels like a **simplified skeleton, not a one-for-one port**.

Every one of these is confirmed in code and mapped to a typed gap below. The honest synthesis matches the owner's read: the port faithfully lands the **two-way text channel + config substrate + strict app separation** (a genuinely strong Rung-0), but the **operator/power surfaces** — copy-out to ChatGPT, export, dashboard, device logs on reports, the dogfood verify loop, and image/mic capture — are absent, which is exactly why it feels like a skeleton for the half that carries the daily workflow power.

| Owner observation | Confirmed cause | Section |
|---|---|---|
| (b) chat input behind nav bar / awkward | `orchestrator_chat_screen.dart` build (L96-116): `Scaffold` has no `resizeToAvoidBottomInset`, body is a bare `Column` ending in `ChatComposer` with **no `SafeArea`** and no bottom inset padding | §7 (exact fix) |
| (c) no mic / image / file in chat | `chat_composer.dart` is text-only (mic + attach deferred); no attachment render in `chat_bubble.dart` | §4 gaps, §5 chunks 4-5, §8 |
| (d) report flow feels thin | `report_repository.dart` `fileReport` writes note/title/screenshots only — **no device logs, no route/region, no deviceInfo, no build**; no draft/resume; no success report-ID | §4 gaps, §8 |
| (e) no floating dev-tool layout | `HarnessOverlay` mounts at `app.dart:21` inside `home:` (not above the Navigator) → covered by any pushed route; single FAB → command center (deliberate) but **no glanceable badges** | §4 gaps, §5 chunk 1 |
| (f) missing bug stack / mic-to-report / issue list / dogfood / tools | logs/diagnostics half absent; dogfood consumption half absent; chat operator surface absent | §1-§5, §8 |
| (g) skeleton, not one-for-one | Rung-0 text channel is faithful; operator/verify surfaces not yet built | whole doc |

---

## 1. Reference harness inventory (patterns, exhaustive)

Each capability is described as a **pattern** (what it does + why it matters for owner workflow power), assembled from all seven harness areas.

### A. Global reachability — the floating dev-tool overlay
- **Release-safe dev gate.** The entire harness is compiled behind a `!kReleaseMode` flag: fully present in dev/dogfood builds, structurally absent (and zero-cost) in a real release. *Why:* one owner can dogfood a real build without shipping dev tooling to end users.
- **Overlay mounted ABOVE the navigator.** The floating entry is injected at the app's *builder* seam, wrapping the Navigator's output, so it floats above **every** route and can never be covered by page content or a pushed full-screen route. *Why:* the whole premise is "reach the harness from anywhere" — the moment the entry can be hidden behind page chrome, the workflow breaks.
- **Draggable, repositionable entry with persistence.** The entry is a draggable puck (long-press-to-drag + a grip handle, haptic on grab, scale-up while dragging), its position stored as a screen *fraction* and restored across restarts/rotation. Drag clamps bake in **nav-bar/gesture clearance** so it can never settle under the system bar. *Why:* the owner parks it out of the way of the control he's testing; drag is the mechanism that keeps it un-hideable.
- **Glanceable status badges on the entry.** The floating entry surfaces merged counts (fixes-ready-to-test, chat-unread, draft-in-progress) as badges *without opening anything*. *Why:* "what needs me" is visible at a glance.
- **One-tap routes to the four owner tools:** owner↔orchestrator chat, file-a-report, report queue (with live open-count), and poke-the-orchestrator. *Why:* these four are the operator's whole control set.
- **Single-instance launcher.** Opening one dev surface closes the others; repeat taps don't stack duplicate routes. *Why:* keeps the small-screen dev UX coherent.
- **Route-region awareness.** A lightweight tracker tags each report/dogfood item with the screen the owner was on. *Why:* "which screen was I on" is the fastest triage signal.

### B. The two-way channel — orchestrator chat
- **Keyboard/nav-safe composer.** The chat Scaffold resizes for the keyboard and wraps its body in a bottom `SafeArea`, so the input always rides clear of the Android nav bar and above the keyboard. *Why:* the input **is** the harness; behind the nav bar it's unusable (this is exactly the owner's preview complaint).
- **Live two-way text with resilient delivery.** A single stream listener + a short foreground server-poll + an offline send-queue with ack-timeout/retry. *Why:* replaces an external chat tool; must feel instant and never silently drop a message.
- **Copy-out: per-bubble copy + multi-select bulk copy + copy-a-work-area block.** *Why:* copying orchestrator replies out to paste into an external LLM is the owner's single most-used daily lever.
- **ChatGPT-context export (full + recent-since-last-export) as paste-ready frames.** *Why:* the headline "run the build from your phone" power — hand a curated, paste-ready context to an external model.
- **Workflow dashboard sheet (read-only "state + evidence + waiting-on-owner", with stale/fresh banners).** *Why:* the operator's at-a-glance control panel; stale build/context must loudly read as stale.
- **Structured two-dimension tagging + per-stream colours + persistence.** *Why:* routing power when multiple lanes/conversations run at once.
- **Voice/mic dictation into the composer.** *Why:* the owner talks to his phone.
- **Image + file attachments (send from phone, render inline, tap-to-zoom / open doc).** *Why:* the owner shows a visual bug or reference by sending a screenshot.
- **Floating "new messages" pill + multi-frame autoscroll.** Opens pinned to newest, never yanks the view while reading history, lands at the true bottom even with variable-height/image bubbles. *Why:* correctness of the read experience on real content.
- **Unread badge anchored to a server clock + push deep-link into chat.** *Why:* the owner sees "N new" and taps a notification straight into the thread.

### C. Evidence intake — the bug/report flow
- **Always-reachable one-tap report entry with a resume badge.** File a bug mid-use; a persistent draft (note + screenshots frozen to the screen you were on) survives leaving and returning; a badge shows a draft is waiting. *Why:* fast filing while reproducing is the point.
- **Note + multi-screenshot capture, uploaded to owner-scoped Storage as `{url,path,bytes,contentType}`.** *Why:* images are how a non-coder shows a visual bug; the `path` is what the operator-side download keys off.
- **Device logs captured at submit — inline tail + full-buffer Storage upload.** A report carries the recent device-log ring buffer (clipped inline, full buffer uploaded). *Why:* **logs-first, no guessing** — a report without logs can't be diagnosed remotely; this is the single biggest harness power.
- **Mic-to-report dictation.** Dictate the bug straight into the note (even while navigating to reproduce it). *Why:* headline phone capture affordance; the owner explicitly named "mic-to-report."
- **Rich report metadata.** userId, server-timestamp createdAt, `status:new`, deviceInfo/platform, current route + classified region/area, build/version. *Why:* cheap, high-value triage context.
- **Submit-success with a short report ID + copy button.** *Why:* the owner needs a handle to reference the report in chat.
- **Linked "still broken" sub-reports (parent→child).** *Why:* threads a reopened issue under the original.
- **Operator-side queue CLI.** An off-device Admin-SDK tool to list/read/pick reports, download their screenshots and logs, and transition status. *Why:* this is *how reports land for the operator* — the loop can't be run outside the app without it.

### D. Triage — the report queue
- **Live stream of the owner's own reports** with a **tolerant read model** (schema-tolerant, additive fields optional). *Why:* the owner triages his own reports even before the orchestrator replies.
- **Filter buckets** (all / pending / in-progress / resolved / needs-review / flagged) with per-report predicates. *Why:* see state at a glance.
- **Collapsed card + expand**, status/area/time chips, screenshot thumbnail + count. *Why:* the at-a-glance list is the operator's primary surface.
- **Recommend-then-act triage strip** — an always-visible RECOMMENDED FIX line + Execute (disabled until a recommendation exists) / Discuss, a decision tag with Undo, and a resolved tag that **wins over a stale decision** and distinguishes **Fixed** vs **Won't-fix**. *Why:* "nothing sits at 'new'" — the single most owner-specific behavior of the whole harness.
- **Manual status control** (dropdown of the full status set) + Resolved / Flag-for-orchestrator / Misread toggles, with a correct **reopen path** that clears the manual-resolved flag. *Why:* the owner can override the agent, including reopening.
- **Comments composer** that flags the orchestrator on write. *Why:* an inline back-channel without leaving the queue.
- **Full-screen screenshot gallery / pinch-zoom.** *Why:* reading a bug screenshot on a phone requires zoom.
- **Device-log-tail view** in the detail. *Why:* diagnose from evidence, in-app.
- **Poke-with-optional-note.** *Why:* wake the loop now, optionally carrying context.
- **Live "N agents engaged" header signal.** *Why:* the owner sees who's working.
- **One canonical resolved/reopened field-set** shared by the queue and the dogfood surface. *Why:* two live surfaces over the same docs must not drift.

### E. Verification — the dogfood checklist loop
- **Operator "announce a build" action** that atomically (1) posts a build message to chat, (2) auto-creates a **check-item** in the reports collection (`status:fixed, awaitingVerification:true, backfilled:true`), and (3) signals the device. *Why:* every shipped thing-to-check becomes a verify item the owner sees.
- **In-app "Ready to test" surface** — a count-badged entry → a checklist sheet listing each check-item with the **screen to test on**, grouped by lane, with per-item **Works** / **Still broken** and per-group **Accept all** / **View in panel**. *Why:* without a consumption surface the check-items are dead writes and the "owner tests from his phone" premise fails.
- **Works → canonical resolved write** (clears `awaitingVerification`, stamps verified-by-user). **Still broken → reopen write** (status `new`, flag orchestrator, keep `awaitingVerification`) and start a **linked sub-report on the current screen with mic on**. *Why:* it's a *gate*, not an accept-only rubber stamp.

### F. Diagnostics context — logs, build, backend, status
- **In-app logging system:** a master gate + a few category toggles, a bounded in-memory **ring buffer** with a `snapshot(percent)` slice, dead-code-eliminated in release. *Why:* the source of the device logs a report carries.
- **Owner context surface (command center):** backend mode (Firebase/Mock), owner role, copyable owner UID, open-report count, and an **actionable "backend not ready" state** instead of a crash. *Why:* the operator always knows which backend/user a session belongs to.
- **Build/version identity, displayed and stamped on reports.** *Why:* "which build produced this bug / is the owner on the fix?" must be answerable — the dogfood loop depends on it.
- **Workflow/status projection** published to a `system/workflowContext` doc and read in-app (with staleness banners). *Why:* an at-a-glance "current state + which build" surface.

### G. Backend / orchestrator loop
- **Chat CLI** (`--read` with a `maxMillis` cursor, `--send`, `--build`, `--dry-run`, `--selftest`) — the operator's off-device side of the channel. *Why:* the operator runs the loop from a terminal.
- **Poke doc** (`system/orchestratorPoke`) bumped on owner send/report ("the message IS the poke") **and a consumer** that wakes the operator. *Why:* a poll-free wake model needs both a writer and a reader.
- **Report intake** readable by the operator; **orchestrator-side resolve/comment** so the operator can *close* the loop the owner opened. *Why:* "owner files → orchestrator fixes → owner verifies" must be bidirectional.
- **Strict app/project separation** — auth via ADC/permissions (not a shared key), an explicit project-id pin, a runtime guard that refuses to touch any other project's data, and a mechanical anti-leak scan. *Why:* a reusable harness must be provably unable to cross-write another app.
- **Config substrate** — one `project.config.json` → generated app config + shell exports, so all identity (project/owner/collections/push) is data-driven. *Why:* this generator seam is *what makes the harness reusable at all*.
- **Attachment senders** (operator → owner image/doc into chat) + **multi-agent dashboard** + **deterministic lane tagging** + **region-sharded queue CLI**. *Why (context):* real capabilities of the mature harness, most of which a single-lane port should NOT copy verbatim (see §3).

---

## 2. Feature-by-feature parity table

Legend — **Class:** MUST (must-have for the reusable-harness proof) · ADAPT (port, re-seamed/leaner) · DEFER (real value, not needed for the first proof) · DONT (would import dead weight / lower fidelity to the port's own design). **State:** present / partial / different / missing / broken.

### Area 1 — Floating dev-tool overlay / launcher

| Reference pattern | Stock-Track current | Required for proof | Class |
|---|---|---|---|
| Release-safe dev gate (`!kReleaseMode`) | present — `dev_gate.dart` `kHarnessEnabled` (+ `kHarnessMode` firebase/mock seam, an improvement) | keep | MUST |
| Overlay mounted **above** the Navigator | **different** — mounts inside `home:` (`app.dart:21`); covered by any pushed full-screen route | move to `MaterialApp(builder:)` seam | MUST |
| Draggable + reposition | partial — plain `Draggable`, immediate pan (`harness_overlay.dart`) | keep; thicken ergonomics later | MUST |
| Position persistence across restarts | missing — `_pos` is State-only, resets each launch | add a fractional store | ADAPT |
| Nav-bar clearance in drag clamp | partial — bottom clamp `size.height - 56`, no nav inset | fold nav/gesture inset into clamp | ADAPT |
| Drag ergonomics (long-press, grip, haptic, scale) | missing | add later | DEFER |
| Route to chat / file-report / queue / poke | present — command center tiles | keep | MUST |
| Glanceable badge on the floating entry | missing — counts live only inside the command center | merge a single count badge onto the entry | ADAPT |
| Poke the orchestrator | present — `_PokeTile` (in-app, exceeds reference's out-of-app poke) | keep | MUST |
| Single-instance launcher | different — plain `Navigator.push`; unneeded with one entry | flag only if multiple direct FABs return | DONT |
| Backend-not-ready actionable state | present (improvement) — `_BackendNotReady` | keep | MUST |
| Multi-FAB cluster of 5 direct buttons | different — deliberate single-FAB → command center | keep the consolidation | DONT |
| Immersive-hide / drawer dev-screen path | absent | n/a to this app | DONT |

### Area 2 — Orchestrator chat

| Reference pattern | Stock-Track current | Required for proof | Class |
|---|---|---|---|
| Keyboard/nav-safe composer (SafeArea + resize) | **broken** — no `SafeArea`, no `resizeToAvoidBottomInset` (§7) | wrap body in bottom `SafeArea`, set inset flag | MUST |
| Live two-way text + poll + offline queue | present (faithful) — controllers + `FirebaseChatRepository`/`MockChatRepository` | keep | MUST |
| Per-bubble copy + multi-select bulk copy | missing — only `SelectableText` | port select + `Copy (N)` | MUST |
| Floating new-messages pill + multi-frame autoscroll | different — inline `TextButton` pill (consumes layout), single-frame autoscroll | float via `Positioned`; 3-frame autoscroll | ADAPT |
| Image attach + inline image + file bubble | missing | port (needs Storage on + a chat upload seam) | ADAPT |
| ChatGPT export (full + recent) + copy-area | missing | port; degrade gracefully when no context published | ADAPT |
| Workflow dashboard sheet | missing | port read-only; needs a publisher (Area 7) | ADAPT |
| Voice/mic dictation into composer | missing | port via OS speech seam | ADAPT |
| Structured tagging + stream colours + store | missing | lightweight-first (colours + copied-state), full tagging trails | ADAPT |
| Message-engine resilience (resubscribe, code-preserving errors, seen-cursor badge) | partial — keeps listener+poll+sig-gate; drops self-heal/badge/latency log | acceptable at Rung-0; add on-device later | DEFER |
| Push overlay + latency carry | missing — no `firebase_messaging` | 3s poll covers it for now | DEFER |
| `PopScope` back-handling | missing | moot until selection mode exists | DEFER |
| Reference lane registry / route taxonomy / latency tags | n/a | reseed with Stock-Track lanes; never copy | DONT |

### Area 3 — Bug / reporting flow

| Reference pattern | Stock-Track current | Required for proof | Class |
|---|---|---|---|
| Note + multi-screenshot capture | present — `report_capture_screen.dart` (cap 4 vs 8) | keep | MUST |
| Screenshot upload `{url,path,bytes,contentType}` | present (near-parity) — `report_capture/services/screenshot_upload_service.dart` → `stockIssueReports/{uid}/…` | keep; enable Storage | MUST |
| Device logs at submit (inline + Storage) | **missing** — no logger, no logs on the doc | add ring buffer + `logsInline` | MUST |
| Operator-side queue CLI (read + download shots/logs) | missing — `stocktrack_chat.js --reports` is read-only list | add a lean report CLI | MUST |
| Report metadata (userId, createdAt, status:new, deviceInfo) | partial — platform/device missing | add `deviceInfo:{platform}` + build | MUST |
| Submit-success report ID + copy | missing — transient snackbar then pop | show short id + copy | ADAPT |
| Mic-to-report | missing (owner-named) | OS speech into the note | ADAPT |
| Always-on one-tap report entry + resume badge | different — 3 taps deep, no resume | surface a faster entry | ADAPT |
| Current-screen/route + region on report | missing — `area:'general'` hardcoded | capture current route/tab | ADAPT |
| Draft minimize/resume | missing — ephemeral screen state | adapt only if cheap | DEFER |
| Bundled offline speech engine + A/B toggle | absent | OS mic proves it | DONT |
| Log-percent selector | absent | full+tail is enough first | DEFER |
| parentReportId / "still broken" sub-report | absent | with the dogfood loop | DEFER |
| `[Region]` prefix + multi-region FIFO/pick/freeze/reclaim | absent | single queue is right | DONT |

### Area 4 — Issue / report queue

| Reference pattern | Stock-Track current | Required for proof | Class |
|---|---|---|---|
| Tolerant report read model | present (better) — backend-agnostic `Report.fromMap` | keep; add fields (Area 5) | MUST |
| Filter buckets + predicates | partial — 5 of 6 (`needsReview` dropped) | keep; add ready-to-test bucket | MUST |
| Live stream of owner's own reports | present | keep | MUST |
| Collapsed card + expand + chips | present | keep | MUST |
| Recommend-then-act triage strip | present | keep | MUST |
| Resolved-wins + Won't-fix distinction | partial — resolved tag hard-codes "Fixed"/green | add wont_fix label | ADAPT |
| Status dropdown + Resolved/Flag toggles | **broken reopen** — `updateStatus` writes only `{status}`, never clears `manualResolved` → `effectiveStatus` still 'fixed' | non-resolved branch also clears `manualResolved` (+flag) | MUST |
| Comments composer + flag-on-comment | present | keep | MUST |
| Full-screen screenshot gallery / zoom | missing — inline thumbnails only | add tap-to-zoom | MUST |
| Device-log-tail in detail | missing | add expandable tail | MUST |
| Poke-with-note dialog | partial — bare fixed-note fire-and-forget | add optional-comment dialog; add `by:uid` | ADAPT |
| "N agents engaged" header badge | missing — `agentStatusDoc` wired, no UI reads it | light it up | ADAPT |
| Count line ("X of Y reports") | missing | add | DEFER |
| Misread flag + filter | missing | with AI curation | DEFER |
| Clarification block (agent↔owner Q&A) | missing | after orchestrator writes it | DEFER |
| Nested follow-ups / out-of-window parent fetch | missing | after sub-reports | DEFER |
| AI-interpretation / curated title+subtitle | missing | after AI curation | DEFER |
| Jump-to-report deep-link + highlight banner | missing | with "View in panel" | DEFER |
| Indexed newest-150 query | different — single-where + client sort (no index) | keep for dogfood volume | ADAPT |
| Canonical resolved/reopened field-set | missing — `setManualResolved` writes `{manualResolved,status:'fixed'}` only | add shared helper (Area 5) | MUST |

### Area 5 — Dogfood / checklist verify loop

| Reference pattern | Stock-Track current | Required for proof | Class |
|---|---|---|---|
| Operator "announce build" → chat msg + check-item + signal | present — `stocktrack_chat.js` `cmdBuild` writes `{status:'fixed',awaitingVerification:true}` + poke | keep; add `backfilled:true` | MUST |
| Read `awaitingVerification` on the report model | **broken** — `Report.fromMap` never reads it → check-items indistinguishable from closed | add the field | MUST |
| In-app "Ready to test" surface (count + checklist) | **missing** — no consumption surface at all | build count badge + sheet | MUST |
| Works → canonical resolved write | missing | resolved helper (clears `awaitingVerification`, stamps verified) | MUST |
| Still broken → reopen write | missing | reopen helper (status `new`, flag, keep `awaitingVerification`) | MUST |
| Shared resolved/reopened helper | missing | add once, used by queue + sheet | MUST |
| Command-center count includes check-items | **broken** — open-count excludes `status=='fixed'` (`harness_home_screen.dart:48`) → check-items vanish | count `awaitingVerification` separately | MUST |
| "Ready to test" filter bucket | missing | add bucket | ADAPT |
| Workflow grouping in the sheet | missing | re-key to ST lanes or defer | ADAPT |
| Region label ("which screen to test on") | missing | after route capture | ADAPT |
| Accept-all / View-in-panel | missing | after base loop | DEFER |
| Still-broken → mic + draft frozen to screen | missing | plain text field first | DEFER |
| Dedicated count-badged dogfood FAB in a cluster | different — one harness FAB | badge on the existing entry | DONT |
| FCM push on `--build` | missing | poke + in-app badge carries it | DEFER |

### Area 6 — Logs / context / diagnostics

| Reference pattern | Stock-Track current | Required for proof | Class |
|---|---|---|---|
| In-app logger + ring buffer + `snapshot(percent)` | **missing** — zero logging anywhere in `lib/` | add a generic logger | MUST |
| `logsInline` on the report + DEVICE LOG TAIL view | missing | add both | MUST |
| Build/version displayed + stamped on report | missing — no `package_info_plus`; version never read | add `package_info_plus`, show + stamp | MUST |
| Backend mode + owner UID surface | present — command-center status card | keep | MUST |
| `deviceInfo:{platform}` on report | missing | add | MUST |
| Route capture on report | missing — no route tracker | adapt to ST nav | ADAPT |
| Region/area classification | different — `area:'general'` hardcoded | adapt taxonomy or generic area | ADAPT |
| Full-log Storage upload | missing | fast-follow after inline | ADAPT |
| On-disk log file + operator capture scripts | missing | after report-carried logs | DEFER |
| `system/workflowContext` in-app dashboard + staleness | missing — doc declared, nothing reads/writes it | publish minimal or hide | DEFER |
| `logPercent` selector | missing | ship full-buffer first | DEFER |
| Report richness (AI/misread/clarification/parent/reviewStatus) | missing | after AI/agent writes | DEFER |
| Domain-specific feature loggers | absent | never port | DONT |
| Verbatim category list | n/a | port the toggle mechanism, ~3 generic categories | DONT |

### Area 7 — Backend / orchestrator loop

| Reference pattern | Stock-Track current | Required for proof | Class |
|---|---|---|---|
| Chat CLI `--read` + `maxMillis` cursor | present — `stocktrack_chat.js` | keep | MUST |
| Chat CLI `--send` | present | keep | MUST |
| Poke bump on owner send + app wake button | present (write side) | keep | MUST |
| `--build` → auto check-item | present | add `backfilled:true` | MUST |
| Report intake readable by operator | present (read-only `--reports`) | keep | MUST |
| Zero-cross-project separation, ADC not a key | present (**exceeds reference**) — ADC + explicit projectId pin + `bp_guard.js` + antileak scan | keep | MUST |
| Config substrate + generated app config | present — `harness/project.config.json` → `harness_config.g.dart` | keep | MUST |
| Orchestrator-side resolve/close | missing — CLI can't close a report | add `--resolve`/`--comment` | ADAPT |
| `system/workflowContext` publisher | missing — dangling wire | publish 1-line projection or hide surface | ADAPT |
| Poke CONSUMER / wake automation | partial — write side only, no reader/Monitor | document/script the consumer | ADAPT |
| `--dry-run` on chat CLI | missing | add non-destructive preview | ADAPT |
| FCM push / latency carry | missing (deferred) | flag latency; not first-proof | DEFER |
| Attachment senders (`--media`, doc/image push) | missing — Storage off | after Storage on | DEFER |
| Multi-agent dashboard | absent | single lane | DONT |
| Deterministic lane / two-dimension tagging | absent | single lane; would add risk | DONT |
| Region-sharded queue CLI (pick/freeze/reclaim) | absent | single queue is right | DONT |

---

## 3. Classification summary (why)

### MUST-HAVE for a true reusable-harness proof
The loop must actually close on a different app, with real evidence, from the phone:
- **Reachability & usable input:** overlay above the Navigator; **keyboard/nav-safe chat composer** (the owner's #1 complaint); dev gate; command center; poke.
- **Two-way channel:** live text send/receive + offline queue; **copy-out of orchestrator replies** (the owner's most-used lever).
- **Evidence intake:** note + screenshots (Storage on); **device logs on the report**; report metadata incl. platform + build; **operator-side queue CLI** to read reports + pull screenshots/logs.
- **Triage:** tolerant read model; filter buckets; recommend-then-act strip; correct **reopen path**; comments; full-screen screenshot zoom; device-log-tail view; canonical resolved/reopened helper.
- **Verify loop:** `--build` check-item (present); **in-app Ready-to-test surface**; **Works/Still-broken canonical writes**; model reads `awaitingVerification`; command-center counts it.
- **Diagnostics context:** logger + ring buffer; backend-mode + UID surface (present); build/version.
- **Backend:** `--read`/`--send`/`--build`; poke; strict separation + config substrate (both present and strong).

*Why these and not more:* each is load-bearing for one of the five verbs the harness performs — reach, converse, capture-with-evidence, triage, verify. Drop any and the owner can't run that verb from his phone.

### CAN-BE-ADAPTED (port, but leaner / re-seamed)
Position persistence; nav-bar clamp; glanceable entry badge; floating pill + multi-frame autoscroll; **image/file attach in chat** (needs Storage + a chat upload seam); ChatGPT export + copy-area (degrade gracefully); dashboard sheet; **mic/voice via the OS speech seam** (not the heavy engine); lightweight tagging/colours; success report-ID; faster report entry; route/region capture; wont_fix label; poke-with-note; agents-engaged badge; orchestrator-side `--resolve`/`--comment`; `workflowContext` minimal publisher + consumer; `--dry-run`. *Why adapt not copy:* the value transfers but the reference implementation is welded to multi-lane infra or a bespoke recognizer/route taxonomy — port the pattern, re-seam to Stock-Track.

### CAN-BE-DEFERRED (real value, not needed to PROVE reuse now)
Drag ergonomics; message-engine self-heal/seen-cursor; push overlay/latency carry; `PopScope`; draft resume; log-percent; parent/child sub-reports; count line; misread; clarification block; nested follow-ups; AI-interpretation fields; jump-to-report; full-log Storage upload; on-disk logs; workflowContext dashboard richness. *Why defer:* each is a second layer on top of an already-provable loop, or depends on an agent/AI/push capability that isn't part of Rung-0.

### SHOULD-NOT-BE-PORTED (would import dead weight / lower fidelity)
Multi-FAB cluster verbatim; immersive-hide; drawer dev-screen path; bundled offline speech engine + A/B toggle; the reference lane registry / route taxonomy / latency tags; deterministic two-dimension tagging; region-sharded queue with pick/freeze/reclaim; multi-agent dashboard; single-instance launcher (until multiple direct FABs return); verbatim log-category list; another app's clean-room build specifics. *Why:* these exist to serve a mature multi-lane, domain-specific fleet. Stock-Track is single-lane; copying them adds surface and risk with nothing to coordinate, and reproducing the cluster verbatim would be *lower* fidelity to the port's own cleaner single-FAB→command-center design.

---

## 4. All current preview gaps (typed + severity), reconciled with owner observations

**BROKEN**
1. **[BROKEN · HIGH] Chat input hidden behind the Android nav bar / awkward under keyboard.** `chat/screens/orchestrator_chat_screen.dart` build (L96-116): `Scaffold` has no `resizeToAvoidBottomInset`, body is a bare `Column` ending in `ChatComposer` with no `SafeArea` and no bottom inset padding (confirmed: no `SafeArea`/`viewInsets`/`viewPadding` in the chat dir). → owner (b). **Fix in §7.**
2. **[BROKEN · CRITICAL] Dogfood loop severed at the data layer.** `--build` writes `{status:'fixed', awaitingVerification:true}`, but `report_queue/models/report.dart` `Report.fromMap` (L64-98) **never reads `awaitingVerification`**, and `harness_home_screen.dart` open-count (L48) **excludes `status=='fixed'`** → every check-item is created then silently swallowed; nothing shows the owner what to test. → owner (f).
3. **[BROKEN · MEDIUM] Reopen-from-dropdown doesn't reopen.** `report_repository.dart` `updateStatus` (L107) writes only `{status}` and never clears `manualResolved`; after a Resolved-toggle, `Report.effectiveStatus` still returns `'fixed'`, so the row contradicts the dropdown and can't be reopened. → owner (f, "issue-list behavior").

**MISSING**
4. **[MISSING · CRITICAL] No device logs anywhere.** No logger, no ring buffer, no `logsInline`/`logsRef` on the report doc; `report_detail.dart` has no log-tail view. The operator diagnoses blind — violates logs-first. → owner (d).
5. **[MISSING · CRITICAL] No in-app "Ready to test" surface.** No count badge, no checklist sheet, no Works/Still-broken, no shared resolved/reopened helper. → owner (f).
6. **[MISSING · HIGH] No operator-side report CLI.** `stocktrack_chat.js --reports` is a read-only list; no read/pick/close/screenshots/logs download; the orchestrator can't consume or close a report off-device. → owner (f).
7. **[MISSING · HIGH] Chat operator surface absent.** No copy-out (per-bubble/multi-select), no ChatGPT export, no copy-area, no dashboard sheet, no header command buttons. → owner (f, "full command-center tools").
8. **[MISSING · HIGH] No mic anywhere.** No mic-to-report, no chat dictation. → owner (c, f).
9. **[MISSING · MEDIUM] No image/file sharing in chat.** No attach button, no inline image/file render; owner can't send a screenshot from the phone in chat. → owner (c).
10. **[MISSING · MEDIUM] No build/version identity.** No `package_info_plus`; version never displayed or stamped on a report; "which build?" unanswerable. → owner (d).
11. **[MISSING · MEDIUM] No route/region/deviceInfo on reports.** `area:'general'` hardcoded; no current-screen capture; no platform. → owner (d).
12. **[MISSING · MEDIUM] No full-screen screenshot zoom** in report detail (inline thumbnails only). → owner (d).
13. **[MISSING · LOW] No submit-success report ID/copy; no draft resume; no poke-with-note; no agents-engaged badge; no count line; no `--dry-run`; `system/workflowContext` declared but unpublished (dangling wire).**

**PARTIAL**
14. **[PARTIAL · MEDIUM] Message engine** keeps listener+poll+sig-gate but drops self-heal / seen-cursor badge / code-preserving errors — acceptable at Rung-0.
15. **[PARTIAL · MEDIUM] Poke** write side present, **consumer/wake automation** unscripted.
16. **[PARTIAL · LOW] `--build`** omits `backfilled:true` → build items mix into the report list.

**DIFFERENT (mostly intentional)**
17. **[DIFFERENT · MEDIUM] Overlay mount point** — inside `home:` (`app.dart:21`), covered by any pushed route; the reference floats above the Navigator. → owner (e).
18. **[DIFFERENT · LOW] Single-FAB → command center** (vs a floating cluster) — a deliberate, cleaner consolidation, but combined with #17 and no glanceable badges it reads to the owner as "no floating dev-tool layout." → owner (e).
19. **[DIFFERENT · LOW] Inline new-messages `TextButton`** (not a floating pill); single-frame autoscroll; no position persistence; no nav-clamp; screenshot cap 4 vs 8; client-sort query (no index); resolved tag hard-codes "Fixed". All acceptable Rung-0 adaptations.

**Gap count by severity:** **2 CRITICAL** (severed dogfood loop; no device logs), **1 HIGH-broken** (chat input) + **3 HIGH-missing** (operator report CLI, chat operator surface, mic) = **4 HIGH**, **~7 MEDIUM**, **~6 LOW/PARTIAL/DIFFERENT**.

---

## 5. Proposed chunked build plan

Ordered so no chunk depends on a later one. Each chunk is independently shippable and dogfood-testable.

### Chunk 1 — Make it reachable & usable (layout + mount)
**Scope:** Fix the two most visible defects: the chat input occlusion and the coverable overlay; add cheap reachability polish.
**Touch:**
- `lib/features/dev/chat/screens/orchestrator_chat_screen.dart` — wrap body in `SafeArea(top:false)`, set `resizeToAvoidBottomInset:true` (§7).
- `lib/app.dart` — move `HarnessOverlay` from `home:` to `MaterialApp(builder: (ctx, child) => HarnessOverlay(child: child ?? const SizedBox.shrink()))`, keep `home: AppShell()`; so the entry floats above every pushed route.
- `lib/features/dev/harness_overlay.dart` — fold nav/gesture inset into the drag clamp (`size.height - media.padding.bottom - kBottomNavHeight - 56`); add a simple `SharedPreferences` fractional position store; add a merged count badge on the entry (open + ready-to-test + chat-unread once those providers exist).
**Acceptance:** with the soft keyboard open, the composer sits directly above it; with it closed, the composer clears the nav bar; pushing any full-screen route still shows the floating entry; the entry can't be parked under the nav bar; its position survives a restart.

### Chunk 2 — Logs & context (the missing diagnostics half)
**Scope:** Give reports real evidence; make build/backend/user answerable.
**Touch:**
- `lib/core/utils/harness_logger.dart` (new) — master gate (`!kReleaseMode`) + ~3 categories + a bounded ring buffer + `snapshot(percent)`; dead-code-eliminated in release.
- Wire `harness_logger` into a few harness call sites (chat send/receive, report file, poke).
- `lib/features/dev/report_queue/services/report_repository.dart` — `fileReport` adds `logsInline` (100 KB tail, newline-boundary clip), `deviceInfo:{platform}`, `appBuild` (from `package_info_plus`).
- `pubspec.yaml` — add `package_info_plus`.
- `lib/features/dev/report_queue/models/report.dart` — read `logsInline`, `deviceInfo`, `appBuild`.
- `lib/features/dev/report_queue/widgets/report_detail.dart` — expandable "DEVICE LOG TAIL".
- `lib/features/dev/harness_home_screen.dart` — show app build on the status card.
**Acceptance:** a filed report carries a non-empty `logsInline`, `deviceInfo.platform`, and a build string; the report detail shows the log tail; the command center shows the build.

### Chunk 3 — Close the dogfood verify loop
**Scope:** Make `--build` check-items visible and closeable on-device.
**Touch:**
- `lib/features/dev/report_queue/models/report.dart` — read `awaitingVerification` (+ `region`, `verifiedByUser`).
- `lib/features/dev/report_queue/services/report_repository.dart` — add `resolvedFields()`/`reopenedFields()` canonical helpers; route Works → resolved (clears `awaitingVerification`, stamps `verifiedByUser`/`resolvedAt`); Still-broken → reopen (status `new`, flag orchestrator, keep `awaitingVerification`); **fix the reopen bug** (`updateStatus` non-resolved branch also writes `manualResolved:false`).
- `lib/features/dev/report_queue/models/report_filter.dart` — add a `readyToTest` bucket (`awaitingVerification==true`).
- `lib/features/dev/harness_home_screen.dart` — count `awaitingVerification` items separately ("N ready to test") and surface a tile/badge.
- `lib/features/dev/dogfood/ready_to_test_sheet.dart` (new) — checklist sheet: per-item title + region label + Works / Still-broken.
- `scripts/stocktrack_chat.js` — `cmdBuild` adds `backfilled:true`.
**Acceptance:** running `stocktrack_chat.js --build "1.0(N) — x"` makes an item appear under "Ready to test"; **Works** removes it and it reads resolved in the queue; **Still broken** reopens it (status `new`, flagged) and it leaves the ready list; a Resolved-then-dropdown-reopen now actually reopens.

### Chunk 4 — Chat operator surface (copy-out, export, dashboard)
**Scope:** The daily "run the build from your phone" power.
**Touch:**
- `lib/features/dev/chat/widgets/chat_bubble.dart` — per-bubble copy icon + long-press/tap multi-select.
- `lib/features/dev/chat/widgets/chat_selection_bar.dart` (new) — "N selected", Copy(N).
- `lib/features/dev/chat/widgets/chat_new_messages_pill.dart` (new) — floating `Positioned` pill; move it off the `Column` flow in `orchestrator_chat_screen.dart`; make `_autoScroll` re-jump across 3 frames.
- `lib/features/dev/chat/widgets/chat_header.dart` (new) — header actions: Copy FULL context, Copy RECENT, Copy work-area, Dashboard.
- `lib/features/dev/chat/services/chat_export.dart` (new) — paste-ready frames; degrade gracefully when no `workflowContext` is published.
- `lib/features/dev/chat/widgets/workflow_dashboard_sheet.dart` (new) — read-only state + stale banner (reads `system/workflowContext`).
**Acceptance:** the owner can copy a single reply, multi-select and bulk-copy, and copy a full paste-ready context block; the new-messages pill floats without shifting the composer; the dashboard opens (empty-but-honest if nothing is published).

### Chunk 5 — Rich capture: image/file share, mic, report ergonomics
**Scope:** The capture affordances the owner named. Requires Storage enabled in `easy-stock-track`.
**Touch:**
- `firebase` — enable Storage; confirm `storage.rules` owner-scoping for `orchestratorChat/{uid}/media/**` and `stockIssueReports/{uid}/**`.
- `lib/features/dev/chat/services/chat_upload_service.dart` (new) — stage + upload chat images (owner-scoped path).
- `lib/features/dev/chat/widgets/chat_composer.dart` — add attach-image button + mic button (OS speech-to-text seam), staged-image strip.
- `lib/features/dev/chat/widgets/chat_bubble.dart` — inline image + tappable file/doc render.
- `lib/features/dev/report_capture/screens/report_capture_screen.dart` — mic-to-note (OS speech); submit-success short report-ID + copy; a faster/one-tap entry.
- `lib/features/dev/report_queue/widgets/report_detail.dart` — full-screen screenshot gallery / pinch-zoom.
**Acceptance:** the owner sends a screenshot in chat and it renders inline; dictates a report by voice; sees a copyable report-ID on submit; pinch-zooms a report screenshot.

### Chunk 6 — Close the operator loop off-device (backend)
**Scope:** Let the orchestrator resolve what the owner opened; make the wake model real; publish status.
**Touch:**
- `scripts/stocktrack_reports.js` (new) or extend `stocktrack_chat.js` — `--read`/`--pick`/`--resolve <id>`/`--comment <id>`/`--screenshots <id>`/`--logs <id>` (Admin-SDK download), reusing `bp_guard.js` + ADC.
- `scripts/stocktrack_workflow_status.js` (new) — publish a minimal `system/workflowContext` (`{updatedAt, build, lane, waitingOnOwner}`); OR hide the in-app dashboard until published.
- `scripts/stocktrack_chat.js` — add `--dry-run`; document a poke **consumer** (a Monitor/cron loop that reads `system/orchestratorPoke` and wakes `--read`).
- `lib/features/dev/report_queue/widgets/` — poke-with-note dialog; "N agents engaged" header badge (reads `agentStatusDoc`).
**Acceptance:** the orchestrator closes a report from the CLI and the owner sees it resolved in-app; `--dry-run` previews without writing; the dashboard reads a published projection; a poke wakes the operator loop.

**Chunk count: 6.**

---

## 6. Validator checklist (concrete, checkable)

**Reachability**
- [ ] Release build: harness fully absent (no entry, no dev routes).
- [ ] Dev build: floating entry visible on every tab AND after pushing a full-screen route.
- [ ] Entry is draggable, can't be parked under the nav bar, and its position survives a restart.
- [ ] Entry shows a merged count badge when there are open reports / ready-to-test items / unread chat.

**Chat**
- [ ] Keyboard open → composer sits directly above the keyboard (no dead gap, not clipped).
- [ ] Keyboard closed → composer clears the Android nav/gesture bar.
- [ ] Send text → appears locally immediately; orchestrator `--send` reply appears within the poll window; offline send queues and flushes.
- [ ] Copy a single reply; multi-select and Copy(N); copy a full paste-ready context block.
- [ ] New-messages pill floats over the list and does not shift the composer; opening the screen lands pinned to newest on image-heavy content.
- [ ] (Chunk 5) Attach + send an image → renders inline; mic dictates into the composer.

**Report capture**
- [ ] File a note + screenshot → a `stockIssueReports` doc is created with `userId`, server `createdAt`, `status:new`, screenshots `{url,path,...}`.
- [ ] The doc carries a non-empty `logsInline`, `deviceInfo.platform`, and an app build string.
- [ ] Submit-success shows a short report-ID with a copy button.
- [ ] (Chunk 5) Mic dictates the note; report detail pinch-zooms the screenshot.

**Report queue**
- [ ] Owner sees only their own reports, newest first, across the filter buckets.
- [ ] Recommended-fix line renders; Execute is disabled until a recommendation exists; decision tag + Undo work.
- [ ] Resolved tag wins over a stale decision; a wont_fix report reads "Won't fix", not "Fixed".
- [ ] Reopen: after Resolved-toggle, choosing a non-resolved status in the dropdown actually reopens (chip + triage tag update).
- [ ] Comment flags the orchestrator; device-log-tail is viewable in detail.

**Dogfood verify loop**
- [ ] `stocktrack_chat.js --build "1.0(N) — x"` posts to chat AND creates a check-item with `awaitingVerification:true, backfilled:true`.
- [ ] The check-item appears under "Ready to test" in-app and in the command-center count.
- [ ] Works → item leaves the list and reads resolved with `verifiedByUser`.
- [ ] Still broken → item reopens (status `new`, orchestrator flagged) and leaves the ready list.

**Backend / separation**
- [ ] `--read` prints owner messages + a `maxMillis` cursor; `--send`/`--build` write to `orchestratorChat/{uid}/messages` and bump `system/orchestratorPoke`.
- [ ] `bp_guard`/antileak: every script refuses to run against any project other than `easy-stock-track`; no other project's literals reachable; auth is ADC, not a committed key.
- [ ] (Chunk 6) Orchestrator `--resolve <id>` closes a report the owner filed; owner sees it resolved.
- [ ] `system/workflowContext` is either published (dashboard reads it) or the in-app dashboard is hidden — never a dead empty doc read as "broken".

---

## 7. The chat-input-behind-the-nav-bar fix (exact)

**File:** `lib/features/dev/chat/screens/orchestrator_chat_screen.dart` — method `_OrchestratorChatScreenState.build` (L96-116).
**Root cause (verified in code):** the `Scaffold` sets no `resizeToAvoidBottomInset`, and its `body:` is a bare `Column` whose last child (`ChatComposer`) is drawn at the physical bottom of the screen with **no `SafeArea`** and **no `MediaQuery` bottom inset**. On Android edge-to-edge / any device with a gesture or 3-button nav bar, the body extends under the system bar, so the send button and the composer's 8px bottom padding sit behind it. (`ChatComposer` in `chat_composer.dart` L25 pads `EdgeInsets.fromLTRB(8, 6, 8, 8)` with no inset.)

**Fix — wrap the body `Column` in a bottom `SafeArea` and set the inset flag explicitly:**

```dart
return Scaffold(
  backgroundColor: HarnessTheme.background,
  resizeToAvoidBottomInset: true, // keyboard shrinks the body so the composer rides above it (default, set explicitly to document intent)
  appBar: AppBar(
    title: const Text('Orchestrator chat'),
    backgroundColor: HarnessTheme.panel,
  ),
  body: SafeArea(
    top: false, // AppBar already consumes the top status-bar inset; only the bottom nav inset needs padding
    child: Column(
      children: [
        Expanded(child: _body()),
        if (_messages.hasUnreadBelow) _newMessagesPill(),
        ChatComposer(
          compose: _compose,
          controller: _input,
          focusNode: _focus,
          accent: HarnessTheme.accent,
        ),
      ],
    ),
  ),
);
```

**Why it fixes both symptoms:**
- **Nav bar (keyboard closed):** `SafeArea` pads the Column's bottom by `MediaQuery.viewPadding.bottom` (the nav-bar height), lifting the composer clear of the gesture/nav bar.
- **Keyboard (open):** `resizeToAvoidBottomInset:true` shrinks the body by `viewInsets.bottom`; `SafeArea`'s bottom padding auto-collapses to 0 when the keyboard consumes the nav inset, so the composer sits snug above the keyboard with no dead gap.

**Minimal alternative (if you must not touch the screen):** in `lib/features/dev/chat/widgets/chat_composer.dart` (L25) change the padding to include the inset:
```dart
padding: EdgeInsets.fromLTRB(8, 6, 8, 8 + MediaQuery.of(context).viewPadding.bottom),
```
The `SafeArea(top:false)` wrap is preferred — it is the reference pattern, keeps the composer context-free, and also protects the list/pill. Do **not** use `extendBody`/`extendBodyBehindAppBar` here (that pushes content further under the bars). Apply the same `SafeArea`-bottom treatment to `report_queue_screen.dart` and the capture screen so the last card's controls and the comment composer also clear the nav bar.

---

## 8. Verdict — are mic, image/file sharing, screenshot attachment, logs, and the dogfood checklist in the FIRST proof, or deferred?

Honoring the owner's framing (the proof must preserve the **workflow power** of the whole system — not a visual clone, but not a skeleton):

| Feature | In the FIRST proof? | Why |
|---|---|---|
| **Device logs (on reports)** | **YES — MUST-HAVE (Chunk 2)** | Logs-first is the doctrine that makes the harness powerful. A report with no device logs can't be diagnosed remotely, so the operator loop can't be *proven*. A lightweight ring buffer + `logsInline` restores diagnose-from-evidence — non-negotiable for the first proof. |
| **Dogfood checklist** | **YES — MUST-HAVE (Chunk 3)** | The owner-verify loop ("ship → owner tests on his phone → Works/Still-broken") *is* the proof. The creation half already works; the consumption half is missing and the loop is currently severed at the data layer. Without it the whole premise fails. |
| **Screenshot attachment (on reports)** | **YES — MUST-HAVE (enable Storage; capture UI already ported)** | Screenshots are how a non-coder demonstrates a visual bug, and the upload path + capture UI are already built near-parity — this is the cheapest must-have. Just turn Storage on so the `path` an operator downloads actually exists. |
| **Mic input (mic-to-report + chat dictation)** | **YES — but ADAPTED (Chunk 5): OS speech seam; heavy engine DEFERRED** | The owner explicitly named mic-to-report; dictation is a headline phone workflow power, so the *capability* belongs in the first proof. Implement it via the platform/OS speech-to-text seam (light). The reference's bundled offline dual-engine + A/B toggle is a whole local package — **don't port**; it adds no reusability signal. |
| **Image / file sharing (in chat)** | **NEXT WAVE — gated on Storage, fast-follow (Chunk 5)** | Sending a screenshot to the orchestrator from the phone is real workflow power the owner flagged, and it's must-have for the *complete* harness. It is the one item legitimately gated: Storage is deliberately off for the first backend proof. Recommendation: flip Storage on (already required for report screenshots) and include chat image sharing in the same wave; treat file/doc sharing and operator→owner doc push as the trailing edge. It is **not** required to demonstrate the loop *closes*, but should land immediately after, because the owner named it and it preserves daily power. |

**Bottom line:** four of the five (logs, dogfood checklist, screenshot attachment, mic-adapted) belong in the first true reusable-harness proof; only **chat image/file sharing** is a deliberate fast-follow, purely because Storage is off — and it should be included the moment Storage is enabled (which the screenshot must-have already requires). This keeps the proof at "full workflow power," not a skeleton, while not porting the heavy, app-specific pieces (offline speech engine, multi-lane tagging, region-sharded queue) that would add weight without proving reuse.
