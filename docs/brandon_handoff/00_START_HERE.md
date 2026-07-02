# Stock-Track — START HERE (Brandon's handoff)

> **Who this is for:** you, Brandon — the owner of Stock-Track — and the Claude Code
> "orchestrator" that will run development of your app for you. It is written in plain
> English. You do not need to be a coder to follow it.
>
> **How to read it:** read this whole page first. It tells you what you're getting, what
> already works, what is only half-proven, and what you have to switch on yourself. Then
> follow the numbered docs in the table at the bottom, in order.

---

## 1. What Stock-Track is

Stock-Track is your **HVAC / electrical equipment inventory + install-tracking app** — a
mobile app (Android now, iOS later) that follows equipment from **warehouse → installer's
truck → customer site**, with stock counts, low-stock alerts, and install history.

Right now the app's **screens are real** (dashboard, inventory, scan flow, dark theme,
navigation) but the **inventory data is still sample/placeholder data** that resets when you
close the app. Turning that placeholder data into real saved cloud data is a *later* step —
see `06_KNOWN_LIMITATIONS.md`. This handoff is **not** about the inventory features. It is
about the second thing you're receiving alongside the app: **the harness.**

---

## 2. What "THE HARNESS" is (read this carefully — it is bigger than it looks)

The harness is **not** "the floating buttons and the chat window." Those are just the tip
you can see on the phone. The harness is a **complete operating system for running app
development from your phone** — the same way the app you're building was itself built. It is
made of many parts working together:

- **An orchestrator** — a Claude Code AI session that acts as your lead. You talk to it; it
  triages your requests, plans the work, and reports back.
- **Sub-agents / lanes** — the orchestrator can spin up extra AI workers for separate jobs
  so several things move at once, then it consolidates their results for you.
- **Zellij** — the terminal workspace where the orchestrator and its agents run and stay
  alive (think of it as the "control room" on the computer). Covered in `03_…`.
- **Startup + shutdown routine** — how the whole control room is brought up in the morning
  and put to sleep, repeatably, without losing context.
- **Build + deploy** — turning the code into an installable app (an APK) and getting it onto
  your phone.
- **The dogfood loop** — you try a build on your phone, and each thing to check shows up as a
  **"Ready to test"** item you tap **Works** or **Still broken** on. That verdict flows back
  to the orchestrator. This is how a fix is *confirmed*, not just claimed.
- **Reporting with real evidence** — when something's wrong you file a report from inside the
  app. It automatically attaches the **device logs**, a **screenshot**, and **which screen /
  build / phone** you were on — so the problem can be diagnosed without guessing.
- **Voice (mic) capture** — you can dictate a bug report by talking to your phone.
- **Push notifications** — the orchestrator's replies ping your phone; you tap the ping and it
  opens straight to the chat.
- **The two-way chat** — the in-app channel where you and the orchestrator talk.
- **Anti-leak protection** — a mechanical check that guarantees none of the *original* app's
  private identity ever leaked into your copy (your app is 100% your own identity). Covered in
  `07_…`.
- **Environment checks** — pre-flight checks that confirm the computer is set up correctly
  before anything runs. Covered in `01_…`.
- **No-key / permission-only access ("ADC")** — the orchestrator reaches your cloud using a
  **granted Google permission**, never a downloaded secret key. This is a core safety rule.
  Covered in `02_…` and `07_…`.
- **Validation + audit gates** — independent checks (does it work? is it healthy? is anything
  private leaking?) that must pass *before* something is called done or handed onward.
- **Role boundaries** — a clear split of who does what: what only **you** can do, what the
  **orchestrator** can do, and what should **never** be done by hand.

**The short version:** the harness is the whole owner→AI→build→phone→verify→report machine.
The chat and floating buttons are how you *touch* it; everything above is what makes it work.

---

## 3. What you are receiving

- The **Stock-Track app** (Android debug build) with the **full harness built in** — chat,
  reports, report queue, mic, floating tool cluster, push wiring, dogfood loop.
- The **orchestrator tooling** (the scripts your AI uses to read your chat, reply, ship
  builds, and pull your reports) — already written and wired to *your* project's settings.
- **This handoff pack** (`docs/brandon_handoff/`) plus the deeper setup docs it links to.
- A **security model** where you never hand over a secret — only grant a revocable permission.

You are **not** receiving: anyone else's data, keys, or cloud project. Your app points only at
**your own** Firebase project (`easy-stock-track`) and nothing else.

---

## 4. What is already built and PROVEN (and on whose device)

Everything in the harness has been built and hand-tested by **the team that built it for you
(your ops contact)**, on **their** device against **their own private throwaway test cloud**.
That testing was done *before* handing it to you specifically to de-risk it. What was proven
there:

- **The two-way chat loop** — a message sent from the phone reached the operator, a reply was
  sent back, and the reply appeared in the app. **Proven on the builder's device.**
- **Reports carry real evidence** — a filed report produced a real cloud record with the
  device-log tail, the build, the platform, and the current screen attached, and it was
  retrievable from the operator side. **Proven.**
- **Screenshot capture + upload + retrieval** — a screenshot attached to a report was uploaded
  and downloaded back by the operator. **Proven.**
- **Mic dictation** — the voice-to-report capability was ported to the exact reference
  standard (continuous dictation that re-arms across a pause and fills the report draft).
  **Built and validated; final on-device confirmation is part of your first dogfood.**
- **Push notifications** — **proven on the builder's device**: the foreground banner pops, the
  background notification pops, and tapping it opens the chat (all three confirmed on-device).
  You re-confirm on *your* phone + *your* cloud as part of your first dogfood (see
  `06_KNOWN_LIMITATIONS.md`).

> **Important honesty note:** "proven on the builder's device against the builder's test
> cloud" is **not** the same as "proven on *your* phone against *your* cloud." That is exactly
> why `05_DOGFOOD_FLOW.md` exists — you re-prove the whole loop on **your own** setup. Until
> you do, treat these as *built and de-risked*, not *confirmed for you*.

---

## 5. What was temporary / test-only (and must be replaced with YOUR setup)

- **The builder's throwaway test cloud was theirs, not yours.** It existed only to prove the
  harness before handoff. **You will never use it.** Everything you run points at **your own**
  Firebase project. *Never share:* you should never be asked for, and never hand over, anyone
  else's project or credentials.
- **The test build that was used for that proof was a one-off** built against that test cloud.
  Your build is (or will be) built against **your** project — a different, regenerable build.
- **Screenshots (cloud Storage) start switched OFF** in the shipped default, so the very first
  proof can be pure text. To use screenshot capture on *your* project you turn Storage on and
  deploy one rules file (see `02_…` and `06_…`).

---

## 6. What YOU (Brandon) must set up yourself

*Requires Brandon (you) personally:* these are the steps only you can do because they happen
in **your** Google account / **your** Firebase console:

1. **Create / confirm your Firebase project** and register the Android app — `02_FIREBASE_SETUP.md`.
2. **Turn on the database (Firestore)** and **Anonymous sign-in** — `02_…`.
3. **Grant your ops contact a limited permission** (a role on your project — **never a key**) so
   the orchestrator can read your chat and reply — `02_…`.
4. *(For screenshots)* **Turn on Storage** and let your orchestrator deploy the storage rules.
5. *(To get builds by proper pipeline)* **Turn on App Distribution** and make the tester group —
   `02_FIREBASE_SETUP.md` **(Part H — App Distribution)**. Until then, builds arrive as a
   **file / download link** (see `06_…`).
6. **Install the APK on your phone and allow notifications** — `05_DOGFOOD_FLOW.md`.

> *Never share:* an admin key, a service-account `.json` file, a token, or a password — with
> anyone, ever. The only correct way to grant access is adding an email as a member with a role
> in the console. If anything asks you to paste or send a secret, stop — that is not how this
> works.

---

## 7. What your ORCHESTRATOR should do first

*Your orchestrator can do this* (hand it `03_ORCHESTRATOR_ZELLIJ_WORKFLOW.md` and let it work):

1. Read the harness docs and confirm the project is pinned to **your** project id
   (`easy-stock-track`) — never any other.
2. Sign in with **ADC** (`gcloud auth application-default login`) using the granted permission —
   **no key file**.
3. Run the self-tests: `node scripts/stocktrack_chat.js --selftest` and
   `node scripts/stocktrack_workflow_status.js --selftest` — both must print a PASS line.
4. Deploy the security rules to your project.
5. Discover your live chat thread and start the chat-monitor loop so your messages are read.
6. Cut and ship a build to your phone.

**Expected result:** by the end, your orchestrator is "live," your phone has a build, and
`05_DOGFOOD_FLOW.md` can be run end to end.

---

## 8. What you should NOT do by hand (unless told to)

- **Don't** edit generated or framework code (for example `lib/harness/harness_config.g.dart`
  is machine-generated — it says so at the top; change the config and regenerate instead).
- **Don't** run raw `git` commands, force-push, or build APKs by hand — let the orchestrator do
  it; it knows the safe, repeatable procedure.
- **Don't** re-point the app at any project other than your own.
- **Don't** hand-paste security rules if your orchestrator can deploy them for you.
- **Don't** share any secret (see §6). Granting a role is fine; sending a key is never fine.

If you *want* to do one of these, ask your orchestrator to do it or to confirm it's safe first.

---

## 9. The rest of this handoff (read in order)

| # | Doc | What it covers |
|---|-----|----------------|
| 01 | `01_ENVIRONMENT_CHECKLIST.md` | The computer set-up + pre-flight checks before anything runs. |
| 02 | `02_FIREBASE_SETUP.md` | Your Firebase project, Firestore, Auth, Storage, App Distribution, and the permission grant — step by step. |
| 03 | `03_ORCHESTRATOR_ZELLIJ_WORKFLOW.md` | How the orchestrator + agents run in Zellij: startup, the chat loop, shipping a build. |
| 04 | `04_HARNESS_SYSTEMS_CLASSIFICATION.md` | Every harness system and whether it's generic (reusable) or your-app-specific config/wiring. |
| 05 | `05_DOGFOOD_FLOW.md` | **Your first dogfood — the 17-step checklist to re-prove the loop on your own setup.** |
| 06 | `06_KNOWN_LIMITATIONS.md` | The honest list of what is not done / not signed / deferred / owed. |
| 07 | `07_SECURITY_ANTILEAK_AUDIT.md` | The no-key security model, the anti-leak guarantee, and the audit gate. |

> **First real milestone:** finish `02_…` (your Firebase), let your orchestrator do §7, then
> run **`05_DOGFOOD_FLOW.md`** on your phone. When all 17 steps read "done," the harness is
> proven on *your* setup — that is the goal of this handoff.
