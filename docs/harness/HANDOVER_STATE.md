# Stock-Track Harness — Current State / Handover (2026-07-01)

> Snapshot for durability (backed up to GitHub). Where the reusable owner/operator harness stands, what's proven, and what's next. Patterns-only, no reference-repo internals.

## Where we are
The Stock-Track harness went: skeleton → parity map → full parity build → owner dogfood corrections → sub-orchestrator rebuild → **corrected build (all 12 acceptance criteria pass)** → **exact reference mic ported** → **wired live-loop build delivered**. Owner-first dogfood throughout; **nothing sent to the second developer yet**.

## Committed + pushed to origin/main (this repo — durable off-site)
- **Parity map** `docs/harness/HARNESS_PARITY_MAP.md` + **correction signoff** `docs/harness/CORRECTION_SIGNOFF.md` + per-area evidence in `docs/harness/validation/`.
- **Overlay** rebuilt as a draggable MULTI-BUTTON floating cluster (`lib/features/dev/overlay/harness_fab_cluster.dart`) — tools on top of the screen, not a single button to a page.
- **Durable local persistence** — chat/reports/queue/dogfood state survive restart (SharedPreferences write-through behind the repo seam).
- **Honest mode banner** — declares local-only vs connected; never implies a reading operator when there isn't one.
- **Report/logs** — filed reports carry a device-log tail + build/platform + current-screen context, retrievable on reload.
- **Mic ported EXACTLY to the reference standard** — a generic `packages/harness_voice/` (dual-engine native voice: platform SpeechRecognizer default + optional offline streaming engine; continuous re-arming lifecycle; populates a frozen-screen report draft). Mic is a floating-cluster button wired into the report flow. `lib/features/dev/voice/**` + native bridges.
- **Orchestrator loop scripts** `scripts/stocktrack_chat.js` + `scripts/stocktrack_workflow_status.js` (ADC, no key).
- Anti-leak scan PASS (0 reference literals); generic-harness-first, app-specifics isolated to config/wiring.
- Latest origin/main HEAD at snapshot time: `dcc1410`.

## Live-loop connectivity (owner's test cloud)
- Owner created a throwaway test Firebase project (owner-owned) with Firestore + Anonymous Auth. The app CLIENT config points there for the wired build only.
- **Orchestrator access is PROVEN** — signed in via ADC (permission-only, no key/token), verified a Firestore write→read→delete round-trip, deployed the security rules.
- **A WIRED+mic APK was delivered to the owner** (built with the test-cloud config + the live bridge on + arm64; all build-time swaps reverted, the committed default remains the second developer's project + bridge 'off'). It is a local one-off artifact (regenerable), not committed.

## What's NEXT (pending owner action)
1. **Owner dogfoods the wired build** — opens the app (banner reads connected), sends an in-app chat message → orchestrator reads it from the test cloud and replies → reply appears in-app = **live loop proven end-to-end** (then poke / reports-logs-retrievable / separation-clean checks).
2. **Owner dogfoods the ported mic** — cluster mic button → continuous dictation → report draft + log tail.
3. Only after the owner confirms the loop + mic on-device → consider the second-developer path.

## Not in this repo (by design)
- The orchestrator's ADC credential is machine-local (regenerable via the owner's sign-in), never committed.
- Cross-project coordination + owner decisions live in the orchestrator's own registers, outside this repo.
