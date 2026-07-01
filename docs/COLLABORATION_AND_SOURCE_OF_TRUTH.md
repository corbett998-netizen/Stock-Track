# Stock-Track — Collaboration & Source-of-Truth Rule

> Owner rule locked in 2026-07-01. **This GitHub repository is the durable source of truth and handoff for Stock-Track.** Everything we build, decide, document, and validate lives here, committed as we go — never kept only in private chat history or local scratch files. Brandon needs full visibility and ownership, and Brandon's future cloud/orchestrator (once it connects to GitHub) must be able to read this repo and understand the project from the committed docs alone.

## What lives in the repo (commit as we go)
- Harness parity maps
- Implementation plans + agent briefs
- Build notes + runbooks
- Firebase/backend setup notes (safe, permissions-based — see guardrails)
- Validator checklists + proof/evidence reports
- Decisions (the owner-decision register) + known gaps
- Any instructions Brandon or Brandon's future AI/orchestrator will need

Commit with clean messages. Branches/PRs are fine — choose the safest workflow for the repo state — but the source of truth is the repo itself, not chat.

## Consolidated-push model (owner rule, 2026-07-01)
Brandon's AI/orchestrator watches this repo, so a stream of rapid-fire intermediate commits/pushes is noise. **Push coherent checkpoints, not scratch updates:**
- Work locally (and on a controlled local/work branch for any multi-step build) as needed.
- Do NOT push every small mapping/agent/register/intermediate update to `main` in real time.
- Batch related work into clear consolidated commits and land it as one grouped push when a deliverable is ready (e.g. "harness parity map", "backend setup docs", "validator checklist", a completed build chunk).
- The final pushed state must be repo-readable + future-agent-readable and arrive as a coherent package, with a clean commit message naming the package.
- Goal: Brandon's AI understands stable, coherent checkpoints — not a reaction to every intermediate edit. (Not hiding work; reducing noise.)

## 🔒 Guardrails (hard — enforce before every commit)
1. **No secrets, ever.** No credentials, service-account files, tokens, passwords, `.env` files, Firebase admin keys, keystores, or private local auth artifacts get committed. The `.gitignore` blocks them; the anti-leak scan is the backstop. (Client configs like `google-services.json` are NOT secrets and are committed intentionally.)
2. **No Blueprint Fitness private internals.** Keep Blueprint's private details out of this repo. If Blueprint behavior is referenced (e.g. in a parity map), document it as a **reusable harness pattern / parity requirement**, not by dumping Blueprint's private file paths, code, IDs, or internals.
3. **Stock-Track-specific everything.** Setup/config uses **Brandon's own** project names + configs (`easy-stock-track`, `com.stocktrack.app`) — safe for Brandon and his future orchestrator to read. Never a Blueprint project id, UID, or collection carried in as a live identifier.
4. **Protect before committing backend/harness material.** Confirm `.gitignore` + the anti-leak scan (`harness/harness_antileak_scan.sh`) are in place and green before committing anything backend/harness-related.

## Future-agent-readable (the bar for every doc)
Brandon's future AI/orchestrator should be able to open this repo and understand, from the committed docs alone:
1. What the harness is supposed to do.
2. What was ported from the Blueprint pattern.
3. What is still missing.
4. What is intentionally deferred (and why).
5. How to validate it.
6. How Firebase/backend permissions work safely (permissions-only, no keys).
7. How to continue development **without depending on private chat context**.

## In short
Commit as we go. Document as we go. This repo is the durable handoff. No secrets, no Blueprint internals (patterns only), Brandon's own configs, protected by `.gitignore` + anti-leak.
