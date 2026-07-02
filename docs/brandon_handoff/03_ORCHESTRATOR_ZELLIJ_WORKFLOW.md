# 03 — Orchestrator + Zellij Workflow

**What this is.** A plain-English playbook for running a fleet of AI coding agents from a single
control seat without the coordinator getting bogged down doing everyone's work. It describes the
*pattern* — a terminal multiplexer (Zellij) hosting parallel agent lanes, one coordinating
"orchestrator" that routes rather than executes, and an event-driven "poke" model that keeps cost
near zero when nothing is happening.

**Who it's for.** Whoever sets up and runs the multi-agent workflow for this app. It's written to be
**reusable for any app** (Appharness-ready) — nothing here is app-specific. Where you see a role like
*owner*, *orchestrator*, *lane agent*, *validator*, or *customer*, those are generic seats you fill
per project.

**Design goals (why the whole thing exists):**
1. Run several workstreams **in parallel** without the coordinator hand-cranking each one.
2. Keep the coordinator **big-picture** — triage, board, sequence, consolidate — never head-down in
   one file.
3. Spend tokens/compute **only on real events**, not on idle polling loops.
4. Make every "done" carry **evidence**, checked by someone other than the builder.

---

## 1. Why a terminal multiplexer (Zellij) matters

A single chat session can only do one thing at a time, and if the coordinator personally writes the
code it stops coordinating. The fix is to give **each workstream its own live terminal** and let the
coordinator talk to them instead of doing their work.

Zellij (or any equivalent multiplexer — tmux works too; Zellij is just the reference here) gives you:

- **Parallel lanes.** Each agent runs in its own session/pane. Five lanes can make progress at once;
  the coordinator watches and steers rather than blocking on any one of them.
- **Detached, resurrectable sessions.** Sessions keep running when you close the window and can be
  re-attached later. You can walk away, reboot the terminal client, or connect from another machine,
  and the agents are still there.
- **A visible control room.** You can attach to any lane to watch it think, then detach. The
  orchestrator gets its own always-on pane; build/logs/validation get theirs.
- **Clean start/stop/restart.** Because each lane is a named session, you can bring one up, restart a
  "gone dumb" one, or shut everything down with a script — no hunting for stray processes.

**The one-line reason:** the multiplexer is what lets the orchestrator delegate to *live* parallel
workers instead of becoming the sole worker.

---

## 2. The mental model — what an "agent" actually is

> **1 agent = 1 multiplexer session + one agent process running inside it + its lean context "seed".**

An empty terminal is **not** an agent. What keeps an agent alive and self-healing is a **respawn
wrapper** — a tiny shell loop that relaunches the agent process if it exits:

```
while true; do <agent-runtime> "<contents-of-its-seed-file>"; sleep 3; done   # WRAPPER:<lane>
```

- **Kill the agent process** → the wrapper relaunches it fresh (it re-reads its seed) = **restart /
  clear the context**.
- **Kill the wrapper** → it stays down = **shutdown**.
- A **marker comment** (`WRAPPER:<lane>`) in the wrapper line lets your scripts find and kill exactly
  the right process.

**The seed = lean context, not a firehose.** Each lane's seed loads only what it always needs
(the hard rules, its identity/charter, its current-state handover, and its inbox of tasks) and
*points* to everything else on-demand (architecture docs, its code area, full governance). Over-
loading context makes agents slow and "dumb"; under-loading loses hard rules. Rule of thumb: *would
forgetting it cause a silent disaster the agent wouldn't think to look up?* Yes → put it resident in
the seed. No → make it a pointer.

- **Seeds carry the standing charter, never a dated one-off task.** Dated tasks rot; they belong in
  the inbox/handover, which update. On a respawn the newest inbox task supersedes anything the seed
  names.

**The bootstrap exception.** *Something* has to start the first process. **The owner launches (and
restarts) the ONE orchestrator; the orchestrator launches every other lane.** The owner never
hand-cranks a dozen terminals.

> **If this fails:** if an agent isn't responding, first check it actually has a live process — a
> session can exist as an empty shell with no agent inside it (the wrapper died, or the launch never
> caught). Always verify by a real process ID, never by "the window is open."

---

## 3. Roles — who's who (kill role confusion before it starts)

The most expensive failure in a multi-agent system is **role confusion** — the coordinator starts
coding, a builder starts talking to the customer, or a validator rubber-stamps its own work. Lock
these seats:

| Seat | Who/what | Does | Never does |
|---|---|---|---|
| **Owner** | The human running the product | Sets direction, makes product decisions, gives the final go, dogfoods builds | Hand-crank every terminal; get pulled into internal mechanics |
| **Orchestrator** | ONE persistent, attached agent session | Triage, board, sequence, consolidate, route work, cut/ship builds, own owner-facing comms, surface decisions | Write feature code; validate its own routing; run idle loops |
| **Lane agent (sub-agent)** | One agent per workstream | Deep analysis, spec, plan, implement, prove its own work with evidence | Touch another lane's files; talk to the customer directly; ship un-validated |
| **Validator** | A *separate* agent from the builder | Independently checks a finished change against an acceptance checklist (function gate) and a health/architecture gate | Fix the code it's reviewing (that collapses the independence) |
| **Customer / end-user** | The person the product ships to | Uses the released app | — (never in the build loop; a test build can't hurt them pre-launch, so bias toward shipping to the owner to dogfood) |

**Two hard separations:**
- **Owner vs orchestrator.** The owner decides *what* and *whether*; the orchestrator moves work from
  *intent → finished*. A one-word "go"/"yes" executes the **already-agreed** task — it never starts a
  new irreversible or outward-facing action by inference. If unsure, name what you're about to do and
  confirm.
- **Builder vs validator.** The agent that wrote a change never signs off on it. Independence should
  be **mechanical** (a different agent, a checklist), not a self-claim.

**One voice to the owner.** Route owner-facing status through a single channel. When a project is big
enough to have its own lead, *that lead* owns all owner-facing comms for that project and the main
orchestrator steps back to routing — the owner should never get fragmented per-agent pings.

---

## 4. Starting the orchestrator workspace

The sequence is always: **owner starts the orchestrator → orchestrator starts the lanes.**

**Step 1 — Owner opens the multiplexer and launches the orchestrator.**
- Open (or attach to) the control multiplexer session.
- Launch the ONE orchestrator agent inside its own respawn wrapper (see §2), on your strongest model
  (coding/reasoning quality matters most here).
- **Expected result:** an orchestrator pane that reads its seed, reports the current fleet state, and
  waits for events.
- **If this fails:** if the orchestrator launches but never reads its context, the seed path is wrong
  or empty — fix the seed reference and relaunch. If the process dies immediately, run the wrapper
  command by hand once to see the real error (a wrapper hides the first crash behind its loop).

**Step 2 — Orchestrator brings up the lanes it needs.**
- The orchestrator (not the owner) runs a **fleet-up script** that, for each lane in a small
  registry, creates a detached multiplexer session, plants the respawn wrapper, and **verifies a real
  agent process ID** before calling it "up."
- Bring up only the lanes that have live work. Quiet lanes stay down (cost $0).
- **Expected result:** a truth table — one row per lane — showing session name, live process ID, and
  last heartbeat. Every intended lane shows a real PID.
- **If this fails:** a lane that shows a live *session* but *no* agent process is an empty shell —
  recycle that session and relaunch it. If a session name is stuck in an "exited" state, delete it
  and recreate. Never assume "up" without the PID check.

**Step 3 — Confirm the control surfaces are live.**
- The orchestrator confirms its own event-wake is armed (see §8, poke model) and that the status/heartbeat
  read works.
- **Expected result:** the orchestrator can answer "what's actually running right now?" from a script,
  not from memory.
- **If this fails:** if you can't get a clean status read, you're operating blind — fix the status
  read before dispatching any work.

---

## 5. Recommended windows / panes

Lay the multiplexer out so the coordinator can see the whole operation at a glance. A workable
default (adapt per app):

| Window / pane | Purpose | Who lives here |
|---|---|---|
| **Main orchestrator** | The coordinator seat — triage, routing, boarding, decisions | Orchestrator agent (always attached) |
| **Build / ship** | Run the clean-room build + release/deploy script; read its one PASS/FAIL line | A deterministic script (see §7), driven by the orchestrator |
| **Logs / runtime** | Tail device/app/runtime logs while reproducing a bug | Human or a lane agent doing logs-first diagnosis |
| **Validation** | The independent validator running the acceptance + health checklist | Validator agent (separate from the builder) |
| **Backend / database / infra** | Server, cloud functions, DB console/queries (e.g. Firebase), migrations | A lane agent or scripts; keep it isolated so a DB action never sneaks into a code lane |
| **Sub-agent lanes (N of them)** | One pane/session per active workstream (feature A, bug lane, refactor, content, …) | One lane agent each |

**Sizing:** roughly **4–6 active lanes + 1–2 floaters**, not one-per-everything. Every live lane
costs compute per wake; keep the quiet ones dormant. Add a lane when a workstream genuinely needs its
own owner; retire it when the work lands.

> **If this fails:** if lanes multiply past what the orchestrator can track, that's the signal to
> introduce a **lead per project** (§6) so coordination itself is delegated — not to keep piling
> lanes onto one coordinator.

---

## 6. How the orchestrator delegates (route, don't execute)

**The orchestrator's sole job: move every workstream from *intent → finished state.*** Everything
else (routing, status, boarding) serves that. Each cycle it asks one question: *does the next thing I
do move work toward finished? If yes, do it; if no, unblock/route/escalate.*

**It ROUTES; it does not EXECUTE.** Writing feature code bogs the coordinator down and starves
coordination. The orchestrator's small, closed set of actions on any piece of work:

1. **Tell the owner** to dogfood finished work.
2. **Route** the work to the right existing lane (default: the agent that wrote the spec also plans,
   builds, and ships it — one agent, full arc).
3. **Request a new lane** only if no existing one fits (advise the owner; don't unilaterally sprawl
   the fleet).
4. **Escalate** a real blocker the owner must decide.
5. **Ask** for clarity when something is ambiguous (ask, never guess).

**Execute-don't-ask vs escalate.** A one-file, additive, clearly-specified fix or an obvious unblock
is *execution* — the orchestrator just routes it and reports, no permission menus. Escalation is
reserved for **real decisions**: architecture, locked/irreversible surfaces, product ambiguity,
new cost/risk, anything touching real user data.

**The four coordination motions:**
- **Triage.** New work (owner message, bug report, finished-lane poke) → decide what it is and where
  it goes. No item sits untouched: attach a recommended next step and move it.
- **Board.** Keep a live board of every active workstream: what phase it's in, who owns it, what it's
  blocked on. This is the coordinator's memory — it must be a file/script, not the coordinator's head.
- **Sequence.** Order dependent work; run independent lanes in parallel. **Don't serialize lanes that
  don't collide** — only gate on genuine file-collision or a true blocker.
- **Consolidate.** Fold many lane reports into one clean picture (and one build). The owner sees a
  consolidated result, not a stream of per-agent chatter.

**Delegate coordination itself when a project gets big — the "lead per project" pattern.** When a
project grows past a single spec into multiple specs/waves, name a **lead** for it (usually the agent
who wrote its vision — deepest context). That lead becomes a *local orchestrator* for that project:
owns its plan, sequences its sub-work, tracks its status, keeps its momentum, and owns **all**
owner-facing comms for it. The main orchestrator then **routes, it does not report** for that project.
Keep a tiny **ownership register** (one row per project → its lead) and check it before any
project-level owner comm. *Distributed orchestration scales; centralized doesn't.*

> **If this fails:** if the orchestrator finds itself editing code or answering deep project questions
> itself, that's the smell of centralization — hand the project a lead and step back to routing.

---

## 7. Deterministic (scripts) vs non-deterministic (agents)

Split work by whether it's *repeatable* or *judgment*:

- **Deterministic → a script.** Anything you'd run the same way every time: fleet up/down/restart,
  build, test, deploy/ship, status/heartbeat reads, board/dashboard generation. Scripts are cheaper,
  faster, and don't drift. **Never** put repeatable build/test/deploy in an agent's "brain."
- **Non-deterministic → an agent.** Deep analysis, diagnosis, spec/plan/implement, validation
  judgment. This is where model reasoning earns its keep.

**Author every script to an agent-first output contract**, because agents and a non-coding owner both
read the output:
- **One clear RESULT line:** `PASS` / `FAIL` / `BLOCKED`.
- A **failure category** on failure (what kind, not a raw stack trace) + a next-step hint.
- **Explicit empty states** ("no results"), never silent/blank output.
- **Never a false green** — a real failure must not exit success. (A script that lies about success is
  a trust bug that poisons the whole validation model.)
- A consistent `--help`, compact by default, verbose behind a flag.

> **Expected result:** the orchestrator can drive a build/ship/status entirely by reading one line.
> **If this fails:** if a script ever exits "green" on a real failure, stop and fix the exit-code map
> first — a false green will silently ship broken work.

---

## 8. Poke-first / no idle loops (the cost model)

**The rule: everything is a POKE (an event). Nothing polls on a timer. Compute is spent only when
there's a real event to handle.** Idle = $0.

Why this is non-negotiable: a short-interval coordinator loop running for hours (especially
overnight/idle) plus a full fleet sitting live can burn a huge fraction of a compute budget with
almost no actual building. The system *spins* instead of shipping.

**The event flow:**
1. **Owner → orchestrator:** the owner pokes (a message/report). A persistent **wake watcher** on the
   orchestrator trips it awake in ~1s.
2. **Orchestrator → lane:** it triages and **wakes the one relevant lane** with the task (wake = write
   the lane's inbox + kill its agent process so the respawn wrapper relaunches it reading the inbox).
   Then the orchestrator goes idle — it does **not** poll.
3. **Lane → orchestrator (poke-back):** the lane does the work, then **pokes the orchestrator back**
   (advances a shared wake signal with "lane X done: <what>"). The orchestrator wakes instantly; the
   lane goes dormant. *A lane must poke, not merely write a file the orchestrator would have to poll
   for — a file-check is a poll.*
4. **Orchestrator decides:** cut the build / handle the result; contact the owner **only** if a real
   decision or a dogfood genuinely needs them; otherwise poke the next lane.

**The only permitted timed loop:** a **single slow heartbeat** (~1 hour) as a pure safety-net — its
only job is to catch a missed poke, a silently-dead agent, or a stalled orchestrator. It does a cheap
liveness check, not a work sweep.

**Hard rules (scrutinize any violation):**
- ⛔ **No headless/unattended agent as the orchestrator.** The orchestrator is ONE persistent,
  attached, visible session. (An unattended coordinator with no watchdog can die silently for hours.)
- ⛔ **No short/idle timed loops.** A timed loop must justify why a poke can't do the job; the default
  answer is "a poke can."
- 💤 **Lanes are poke-driven and dormant by default.** Never leave lanes looping. Don't mass-restart
  the fleet (each respawn re-reads context = cost). Wake ONE lane for ONE task; it sleeps when done.
- 🪙 **Model-tier the work.** Routine triage/status on a cheaper model; reserve the top model for real
  coding/hard reasoning.
- 🧠 **Keep context tight.** Read deltas (a chat cursor, heartbeats, only the doc a task needs); don't
  re-read big docs every wake. Restart a bloated session rather than dragging tens of hours of context.

> **If this fails:** if you notice compute draining with no shipped work, look for a rogue short loop
> or a fleet left live — kill the loop, let lanes go dormant, and confirm the poke wake still trips.

---

## 9. How sub-agents report back

Coordination is **async by files**, made *live* by pokes. Two channels:

- **A live status ledger / board** — who's working on what, one row per active lane. The orchestrator
  updates it on assignment and on completion; lanes confirm when they start.
- **Per-lane inbox queues** — one append-only file per lane. The orchestrator dispatches by appending
  to a lane's inbox; the lane reads its inbox first on every wake.

**A small fixed set of message verbs** covers every case (keep it uniform so a script can parse it):

| Verb | From | Meaning |
|---|---|---|
| `kickoff` | orchestrator | "Here's your lane: scope + invariants + how to verify" |
| `started` | lane | "Got it, working, ETA X" |
| `progress` | lane | interim milestone / scope question / surfaced finding |
| `blocker` | lane | "Can't proceed without a decision" |
| `redirect` | orchestrator | "Pivot mid-flight to X" |
| `done` | lane | "Shipped — commit + build + outcome + evidence" |
| `ack` | any | "received + understood" — explicit, before working (no silent assumptions) |
| `request` | any | "route this owner-facing / cross-lane action through the orchestrator" |

Rules that keep it clean:
- **Inboxes are append-only.** Never rewrite others' entries; on a conflict, keep both and order by
  timestamp.
- **One verb per message.** Progress *and* a blocker = two messages.
- **Read the inbox first** on startup, on wake, before every commit (last chance to catch a
  `redirect`), and before declaring `done`.
- **Evidence, not claims.** A `done` must surface a commit/build/passing-check/artifact. "Should be
  fixed" is not done. For product-facing work, a green unit test is **not** proof — the real user path
  must be run (on-device / end-to-end).

**Heartbeats (fleet visibility).** Every live lane writes a tiny per-cycle heartbeat
(`timestamp | loop | state | one-line task`) to a gitignored file — even on idle cycles. The
orchestrator reads all heartbeats in one shot to get instant truth: who's alive / idle / stale /
dead. "Stale" = heartbeat older than a couple of its loop intervals. This is how the coordinator
stops "operating in the blind" without polling each lane.

> **If this fails:** if a lane has gone silent, confirm before alarming — it may just be deep in a
> long task. Truly stalled = silent past several loop intervals **and** past a nudge **and** no fresh
> heartbeat. Only then re-engage it (or, if the coordinator can't restart terminals, ask the owner to
> relaunch that one lane — its in-flight work still waits in its inbox).

---

## 10. Restart, shutdown, and handoff

Author three deterministic fleet scripts (names are yours; behavior is what matters):

- **Fleet-up** — bring lanes up into detached sessions, on the right model, **verified by real PID**.
- **Fleet-restart** — best-effort flush the lane's handover doc → kill its agent process → the wrapper
  respawns a fresh session on the lean seed. Use this when a lane "goes dumb" from context bloat.
- **Fleet-down** — flush each lane's handover (best-effort) → stop wrapper + agent → leave sessions
  resurrectable.

**Restarting clears the dumb-zone.** A long-running agent accumulates context and degrades. Restart =
kill the agent so the wrapper relaunches it fresh on its lean seed; it rebuilds state from its
handover + inbox, so a restart never *hard*-loses work (worst case, the handover is one cycle stale).

**Waking a dormant lane with new work** = append a kickoff to its inbox **and** restart it, so the
respawn re-reads the inbox and acts on the newest task. (Writing the inbox alone isn't enough if the
lane is asleep — pair the write with the wake.)

**Orchestrator handoff / rotation.** The orchestrator itself bloats over a long session. Rotate it:
the outgoing orchestrator writes a live-state handoff (what's in flight, a restart matrix of
which lanes to restart vs leave dormant, and a fresh seed for the successor), the owner launches a
fresh orchestrator, and the outgoing one stops touching the fleet. Do a light **doc-hygiene sweep** at
each rotation (archive stale rules, prune the ledger to live lanes) so the coordination docs don't rot.

> **If this fails:** a forced restart of a lane that's asleep mid-cycle may not flush in the kill
> window (an injected keystroke doesn't reliably interrupt a sleeping loop). The kickoff/flush still
> lands in the inbox and the respawned lane rebuilds from files — so you never hard-lose context, but
> don't *rely* on an instant flush from a sleeping agent.

---

## 11. Quick failure-mode table

| Symptom | Likely cause | Fix |
|---|---|---|
| Lane "up" but unresponsive | Empty session — wrapper died / launch missed | Verify by PID; recycle the session and relaunch |
| Session stuck "exited" | Dead session name held by the multiplexer | Delete the session, recreate |
| Compute draining, nothing shipping | A rogue short/idle loop, or fleet left live | Kill the loop; let lanes go dormant; confirm poke-wake |
| Lane redid already-done work | It read a stale seed task instead of the newest inbox item | Seeds carry no dated task; newest inbox kickoff wins; restart to re-read |
| Owner getting fragmented pings | Multiple agents talking to the owner | One voice: route through the orchestrator / project lead |
| Validator "passed" but it's broken | Builder validated its own work | Independent validator (different agent) + evidence, not self-claim |
| Coordinator stuck in the weeds | Orchestrator executing instead of routing | Hand the project a lead; return to triage/board/sequence/consolidate |
| Script shipped broken as "green" | False-green exit code | Fix the exit-code map so a real failure never exits success |

---

## 12. One-screen checklist

- [ ] Owner launches the **one** orchestrator (attached, top model, respawn wrapper).
- [ ] Orchestrator brings up only the **active** lanes via a fleet-up script; **verify each by PID**.
- [ ] Panes laid out: main orchestrator, build/ship, logs, validation, backend/DB, N lane panes.
- [ ] Poke-wake armed; the only timed loop is a single ~1h safety-net heartbeat.
- [ ] Every lane heartbeats each cycle; the orchestrator reads fleet truth from a script.
- [ ] Delegation is route-not-execute; big projects get a lead + an ownership register.
- [ ] Repeatable work is a script (agent-first output, no false green); judgment work is an agent.
- [ ] Every `done` carries evidence; an independent validator (not the builder) signs off.
- [ ] Lanes are dormant by default; wake one lane for one task; restart to clear the dumb-zone.
- [ ] Rotate the orchestrator when it bloats; sweep docs at each handoff.

---

*Generic by design — swap in this app's model names, script names, and lane set, and the same shape
runs any project (Appharness-ready). Nothing here is app-specific.*
