# Stock-Track — HVAC Warehouse Inventory & Install Tracking

> GitHub repo: `corbett998-netizen/Stock-Track` · "HVAC warehouse manager". Internal working name during setup: "Brandon's App".

An **HVAC / electrical equipment INVENTORY + TRACKING app** — cloud-based, mobile-first, **Flutter (iOS + Android)**. Tracks equipment stock across **warehouse → installer truck → customer install site**, with real-time cloud sync, low-stock alerts, install history, and recall tracking. **Separate project** — its own repo, own source-of-truth, own decisions, own agents. **NOT a Blueprint Fitness feature.**

> Product direction received 2026-06-30 (see `docs/OWNER_VISION.md` + the reference screenshots in `docs/references/`). **No product code yet** — documentation structure only so far.

## ⛔ Separation boundary (hard rule)
- This project lives at `/mnt/c/dev/Brandons_App` — **adjacent to**, and **fully independent from**, Blueprint Fitness (`/mnt/c/dev/blueprint-fitness-app`).
- Do **NOT** mix this project's files, docs, decisions, agents, or build artifacts into Blueprint Fitness (or vice-versa). Separate git repo, separate source-of-truth, separate context.
- It **reuses the Blueprint Fitness harness/orchestration PATTERN** (sub-orchestrator/lane-lead model, an owner-decisions register, a handoff schema, working-notes discipline) where useful — but the *content* and *context* stay separate.

## Orchestration model
- **Main orchestrator** (the Blueprint Fitness main orch) **coordinates** across projects but does NOT own this project's internals.
- A dedicated **sub-orchestrator / lane lead** OWNS Brandon's App end-to-end (vision → spec → build → ship) once the owner brings direction. See `docs/ORCHESTRATION_NOTES.md`.

## Structure
- `README.md` — this orientation doc.
- `docs/OWNER_VISION.md` — owner-intent / product-vision (to be filled with the owner's direction).
- `docs/DECISIONS.md` — the owner-decisions register (what's directed / awaiting-owner / blocked).
- `docs/working/` — working notes / in-progress analysis (date-prefixed).
- `docs/handoff/HANDOVER_NEXT_AI.md` — session-to-session handoff (so context survives).
- `docs/ORCHESTRATION_NOTES.md` — the sub-orchestrator/lane-lead model + agent notes for this project.

## Status
**Set up 2026-06-30** by the main orchestrator at the owner's request. Awaiting the owner's first product direction. No coding has begun.
