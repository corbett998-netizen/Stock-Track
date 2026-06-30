# Brandon's App — HANDOVER_NEXT_AI

> Session-to-session handoff so context survives. Mirrors the Blueprint Fitness handover schema (Status / What's Next / Open Questions / Don't-Revert Invariants / Recent Session Log). SEPARATE project — keep its context out of Blueprint Fitness.

## Status
Project space SET UP 2026-06-30 (separate repo at `/mnt/c/dev/Brandons_App`, adjacent to Blueprint Fitness). First product direction RECEIVED 2026-06-30: it's an **HVAC/electrical equipment inventory + tracking app** (cloud, Flutter iOS+Android) — NOT stock-trading. 3 visual reference screenshots saved to `references/`. OWNER_VISION + DECISIONS updated. Still no product code; next = resolve the 8 open questions → first buildable slice. A dedicated sub-orchestrator should now be stood up to own it.

## What's Next
- Owner (Pete, relaying for Brandon) brings the first product direction → fill `OWNER_VISION.md`.
- Once there's real direction, the main orchestrator spins up a dedicated **sub-orchestrator / lane lead** to own Brandon's App end-to-end (see `ORCHESTRATION_NOTES.md`).
- Then: requirement → spec → plan → build, on this project's own source-of-truth.

## Open Questions
- See `OWNER_VISION.md` "Open questions for the owner" (what the app does, platform, data sources, regulatory scope, existing assets, timeline).

## Don't-Revert Invariants
1. **SEPARATION:** never mix Brandon's App files/docs/decisions/agents/build-artifacts with Blueprint Fitness. Separate repo, separate source-of-truth.
2. **Harness PATTERN reused, CONTENT separate.**
3. **Owner-decision register (`DECISIONS.md`) is the durable ledger** — every directed item + decision recorded there.
4. Trading/financial software carries real correctness + potential regulatory weight — capture those constraints in `OWNER_VISION.md` before building.

## Recent Session Log
- 2026-06-30 17:19 — main orchestrator created the separate project space at the owner's request (README + OWNER_VISION + DECISIONS + working/ + handoff + ORCHESTRATION_NOTES, git-initialized). Reported back to owner; standing by for the first product direction.
