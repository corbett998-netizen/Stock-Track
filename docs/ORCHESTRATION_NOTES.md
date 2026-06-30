# Brandon's App — Orchestration / Sub-Orchestrator Notes

> How this separate project is coordinated. Reuses the Blueprint Fitness harness PATTERN; keeps source-of-truth + context SEPARATE.

## Model
- **Main orchestrator** (the Blueprint Fitness main orch) **coordinates across projects** — it tracks that Brandon's App exists, surfaces owner decisions, and keeps the two projects from bleeding into each other. It does NOT own this project's internals or go deep into its lanes.
- **Sub-orchestrator / lane lead (TO BE NAMED)** owns Brandon's App end-to-end once the owner brings direction: vision → spec → plan → build → ship, on this project's own source-of-truth. This is the same Lead-Engineer / sub-orchestrator pattern Blueprint Fitness uses.
- **Agents/reviewers** perform investigation / implementation / validation / review within this project's lanes — using this repo's files only.

## Reused harness pattern (from Blueprint Fitness, content kept separate)
- Owner-decisions register (`DECISIONS.md`) — the durable ledger; nothing dropped.
- Handoff schema (`handoff/HANDOVER_NEXT_AI.md`) — context survives session death.
- Working-notes discipline (`working/`, date-prefixed).
- Owner-vision / product-compass (`OWNER_VISION.md`).
- Point-form-interpretation-before-spec, evidence-over-trust, lane → independent-review → merge, parallel scoped lanes.

## Separation guardrails (hard)
- Separate git repo (`/mnt/c/dev/Brandons_App`), separate Firebase/build/artifacts (none yet), separate agents.
- No Brandon's App agent touches the Blueprint Fitness repo, and no Blueprint Fitness agent touches this one.
- The main orchestrator routes/owns Blueprint Fitness directly; for Brandon's App it COORDINATES + hands to the (future) sub-orchestrator.

## Status
Set up 2026-06-30. No sub-orchestrator named yet (no work yet). When the owner brings the first direction, the main orchestrator proposes spinning up the Brandon's App sub-orchestrator/lane lead.
