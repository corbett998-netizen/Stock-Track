# Brandon's App — Owner Decisions Register

> The durable owner-decision ledger for Brandon's App (mirrors the Blueprint Fitness `AWAITING_PETE.md` pattern). Separate from Blueprint Fitness. Every directed item, owner decision, and blocker tracked here so nothing is dropped and context survives session death.

## DIRECTED (owner greenlit; track until a lane is executing)
- **Repo wiring -> corbett998-netizen/Stock-Track** - Pete 18:37/18:55. ✅ DONE: pushed to origin/main `7ad81f2` (remote initial README + history preserved, all starter docs merged, README product-fixed to HVAC, branch->main). Write access works via Windows credential mgr.
- **MVP / product-architecture SPEC** - DIRECTED Pete 18:55 (coordinated gated plan, NOT rush-to-code). EXECUTING via lane ac512471 -> `docs/working/JUN30_stocktrack_MVP_architecture_SPEC.md` (data model + 5 screens + Firebase-as-Brandon's-own + phone-cam scan + first slice = Inventory+Dashboard+Scan + open owner-calls). SPEC ONLY no code. NEXT: orch review -> Pete approves spec -> Flutter shell (gated).
- **Set up the separate Brandon's App project space** — DIRECTED by Pete 2026-06-30 17:19. ✅ DONE: repo `/mnt/c/dev/Brandons_App` created (separate git repo, adjacent to Blueprint Fitness) with README + this register + OWNER_VISION starter + working/ + handoff + ORCHESTRATION_NOTES. No coding. Awaiting owner's first product direction.

- **First product direction received** — Pete 2026-06-30 17:53. ✅ CAPTURED: product CORRECTED to **HVAC/electrical equipment inventory + tracking app** (NOT stock-trading), cloud-based, Flutter iOS + Android. 3 reference screenshots (Dashboard / Inventory / Installation-History, "StockTrack Warehouse" style) inspected + saved durably to `references/`. OWNER_VISION updated. Visual references, not final requirements.

## AWAITING-OWNER-DECISION (asked; needs the owner's call)
- 8 open questions to move from references → buildable spec — see `OWNER_VISION.md` "Open questions for the owner" (backend/cloud choice, scanning method, multi-user/roles, recall tracking, truck-as-location, customer records, greenfield-or-existing, first slice + timeline).

## BLOCKED
- (none.)

## RESOLVED (history)
- 2026-06-30 17:19 — project SETUP directed + completed (separate space established, harness pattern reused, separation boundary documented).
