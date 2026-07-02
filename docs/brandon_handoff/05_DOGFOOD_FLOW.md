# Stock-Track — Your First Dogfood (17-step checklist)

> **Goal:** re-prove the whole harness loop on **your own** phone and **your own** Firebase
> project — reach the orchestrator, converse, get a push, capture a bug with evidence, and
> confirm a fix. Earlier proofs were done on the builder's device; this is the one that
> counts *for you*.
>
> **How to use this:** work top to bottom. Every step has an **Expected result** (what "done"
> looks like) and an **If this fails** (what to do). Some steps are yours; some are your
> orchestrator's — each step says which. **Do not skip ahead** — a later step assumes the
> earlier ones passed.

---

## Before you start (preconditions)

*Requires Brandon (you) personally* — all of `02_FIREBASE_SETUP.md` is done:
- Firestore is on, Anonymous sign-in is on, the security rules are deployed.
- Your ops contact has the granted permission (a role, **not** a key) on your project.
- *(For the screenshot steps 13 & 16)* Storage is turned on **and** the storage rules are
  deployed. If Storage is still off, steps 13 and 16 will not work yet — that's expected;
  see `06_KNOWN_LIMITATIONS.md`.

*Your orchestrator can do this* — before you touch the phone:
- Pinned to **your** project (`easy-stock-track`), signed in via **ADC** (no key).
- `node scripts/stocktrack_chat.js --selftest` prints a PASS line.
- The build you're about to install was made in **connected mode** (the operator "bridge" set
  to live) so the in-app banner will read *connected*, and a **chat-monitor loop is running**
  so your messages are actually read.

> *Never share:* nothing in this flow ever asks you to send a key, token, or password. If it
> seems to, stop.

**Do not continue until:** the orchestrator confirms the two bullets above (pinned+ADC+selftest,
and connected build + monitor running). Without them, the loop cannot close and you'll chase
false failures.

---

## The 17 steps

### 1. Install the APK
*Requires Brandon (you) personally.* Open the build your orchestrator sent (a download link,
or later a Firebase App Distribution invite) and install it. On Android you may need to allow
"install from this source" once.
- **Expected result:** Stock-Track appears in your app drawer and opens.
- **If this fails:** confirm it's the **Android** build (not iOS), that it finished
  downloading, and that "install unknown apps" is allowed for the app you opened the file
  from. Ask your orchestrator to re-send if the file is truncated.

### 2. Allow notifications
*Requires Brandon (you) personally.* On first launch (Android 13+), tap **Allow** on the
notification permission prompt.
- **Expected result:** you tapped Allow; no prompt remains.
- **If this fails:** if you tapped "Don't allow," open Android **Settings → Apps → Stock-Track
  → Notifications** and turn them on. Push (steps 9–11) cannot work without this.
- **Do not continue until:** notifications are allowed — several later steps depend on it.

### 3. Open the app
*Requires Brandon (you) personally.* Let the app finish loading to its main screen.
- **Expected result:** the dashboard/inventory screens render (sample data is fine — data is
  still placeholder for now).
- **If this fails:** a blank or crashing screen usually means the build couldn't reach your
  project. Tell your orchestrator; it can check the config pin and rules.

### 4. Confirm CONNECTED mode
*Requires Brandon (you) personally.* Open the harness (the floating tool cluster / owner-tools
entry) and read the **mode banner**.
- **Expected result:** the banner says it is **connected** to your backend — **not**
  "local-only." This is the harness being honest: connected means a real operator can read
  your chat.
- **If this fails:** if it says local-only, the build wasn't cut in connected mode, or the
  operator bridge isn't live. Ask your orchestrator to rebuild with the bridge set to live and
  the monitor running, then reinstall.
- **Do not continue until:** the banner reads connected. A local-only build cannot prove the
  loop.

### 5. Send an in-app chat message
*Requires Brandon (you) personally.* Open the in-app **chat** and send a short message, e.g.
"dogfood test 1".
- **Expected result:** your message appears in the thread as sent.
- **If this fails:** if it appears to hang, check your phone has internet. The composer should
  sit clear of the keyboard and the bottom nav bar — if it's hidden behind either, note it as
  a bug for step 12–14.

### 6. Orchestrator reads it
*Your orchestrator can do this:* run `node scripts/stocktrack_chat.js --read` (it
auto-discovers your live thread).
- **Expected result:** your "dogfood test 1" message shows in the operator output, with an id.
- **If this fails:** if `--read` shows nothing, the orchestrator may be pinned to the wrong
  project or missing ADC, or the security rules aren't deployed. Re-check the preconditions.

### 7. Orchestrator replies
*Your orchestrator can do this:* run `node scripts/stocktrack_chat.js --send "got it — reply 1"`.
- **Expected result:** the command prints success; a reply doc is written to your project.
- **If this fails:** an ADC or permission error here means the granted role hasn't taken effect
  — recheck `02_…` step for the role, and that `--read` (step 6) worked first.

### 8. Reply appears in the app
*Requires Brandon (you) personally.* Look at the chat on your phone.
- **Expected result:** "got it — reply 1" appears in the thread (it may arrive with the push
  in the next steps; opening/refreshing the chat also shows it).
- **If this fails:** if the reply never appears even after reopening the chat, the write didn't
  reach your project — go back to step 7's error. Note: the *instant* appearance is powered by
  push (steps 9–11); a slightly delayed appearance on refresh is still a pass here.

### 9. Push appears with the app in the FOREGROUND
*Requires Brandon (you) personally.* Keep the app open (on any screen) and have your
orchestrator send another reply: `node scripts/stocktrack_chat.js --send "foreground push"`.
- **Expected result:** a heads-up "Stock-Track Ops" notification banner appears on-screen
  **and/or** the message drops straight into the open chat within a second or two.
- **If this fails:** the foreground on-screen banner is the **most recently added fix** and its
  on-device confirmation is exactly what this step checks — if the banner doesn't show but the
  message still lands in the chat, record that precisely and tell your orchestrator (see
  `06_KNOWN_LIMITATIONS.md`, "push foreground banner"). This is useful data, not a dead end.

### 10. Push appears with the app in the BACKGROUND
*Requires Brandon (you) personally.* Press Home (app still running, just backgrounded). Have
the orchestrator send `node scripts/stocktrack_chat.js --send "background push"`.
- **Expected result:** within a second or two your phone shows a **"Stock-Track Ops"** system
  notification.
- **If this fails:** confirm step 2 (notifications allowed) and that the token was stored — the
  orchestrator can verify your chat doc has an `fcmToken` field. No token = no push.

### 11. Tap the push → it opens the chat
*Requires Brandon (you) personally.* Tap the "background push" notification.
- **Expected result:** the app opens **directly to the orchestrator chat**, and the
  "background push" message is already shown (or shows on the refresh). Repeat once more with
  the app **fully closed** (swiped away) to check the cold-start case.
- **If this fails:** if the tap opens the app but not the chat, note which state (background vs
  fully-closed) failed — the deep-link has three cases and the failing one is the clue.
- **Do not continue until:** at least the background case (step 10 + 11) delivers a push and
  opens the chat. Foreground (step 9) may be a known-limitation follow-up; background is the
  core acceptance.

### 12. Mic-dictate a report
*Requires Brandon (you) personally.* From the floating cluster tap the **mic** button and
speak a short bug description, including a natural pause: "The inventory count looks wrong.
[pause] The low-stock filter isn't updating."
- **Expected result:** both sentences transcribe in order, the mic stays listening across the
  pause (it re-arms itself), and the text lands in a report draft that notes "Reporting on:
  <the screen you were on>".
- **If this fails:** if it asks for microphone permission, tap Allow and retry. If permission
  was denied, you should see a clean message (not a crash) — enable it in Android Settings →
  Apps → Stock-Track → Permissions. If dictation stops after the pause, note it — continuous
  re-arm on your device is one of the things this step confirms.

### 13. Attach / capture a screenshot
*Requires Brandon (you) personally.* In the report, add a **screenshot** (capture the current
screen or attach one).
- **Expected result:** a screenshot thumbnail attaches to the report draft.
- **If this fails:** this needs **Storage turned on** in your Firebase project and the storage
  rules deployed (preconditions). If Storage is still off, screenshots won't attach yet — this
  is expected; note it and continue with a text-only report (`06_KNOWN_LIMITATIONS.md`).

### 14. File the report
*Requires Brandon (you) personally.* Submit the report.
- **Expected result:** the report submits and you get a confirmation (a report id / it appears
  in your in-app **report queue**).
- **If this fails:** a submit error usually means Firestore rules or connectivity — the note
  should still save a draft you can resend. Tell your orchestrator the error text.

### 15. Orchestrator sees the note + logs + screen + build + platform
*Your orchestrator can do this:* run `node scripts/stocktrack_chat.js --reports` to list, then
`--report <id>` and `--logs <id>` for the one you just filed.
- **Expected result:** the report shows your dictated note, a **non-empty device-log tail**
  (`logsInline`), the **screen/route** you were on, the **build/version**, and the
  **platform** — on a real cloud record.
- **If this fails:** if the note is there but logs are empty, the log-capture-at-submit path
  didn't fire on your build — capture the exact `--report` output and hand it to your
  orchestrator; this is a real finding, not user error.

### 16. Orchestrator retrieves + views the screenshot
*Your orchestrator can do this:* run `node scripts/stocktrack_chat.js --screenshots <id> <dir>`
to download the attached screenshot(s), then open the file to view it.
- **Expected result:** the screenshot downloads to the folder and opens as the image you
  captured in step 13.
- **If this fails:** if there's no screenshot, confirm step 13 attached one and that Storage +
  storage rules are live. A "permission denied" on download points at the storage rules not
  being deployed.

### 17. Mark Works / Still broken
*Requires Brandon (you) personally.* Have your orchestrator send a dogfood check-item with
`node scripts/stocktrack_chat.js --build "1.0(N) — dogfood loop"`. It appears under **"Ready to
test"** on your phone. Tap **Works** on the item, then file/flag a second item and tap **Still
broken** to see it reopen.
- **Expected result:** **Works** resolves the item (it leaves the ready list as done);
  **Still broken** reopens/flags it (it stays visible as needing more work). The orchestrator
  can confirm the verdict from its side (`--reports` / status).
- **If this fails:** if tapping does nothing, note whether the item appeared at all — a missing
  item means the `--build` write didn't reach your project (recheck pin/ADC/rules).

---

## Done = all of this is true

- Steps **4–8**: connected banner, you sent, operator read, operator replied, reply showed. ✅
- Steps **10–11**: a background push arrived and its tap opened the chat. ✅
- Steps **12–16**: a mic-dictated report filed with a real log tail + screen + build + platform,
  and (if Storage is on) the screenshot was retrieved and viewed. ✅
- Step **17**: **Works** resolved an item and **Still broken** reopened one. ✅

**Do not call the harness "proven for you" until the bullets above are all true.** Anything
that failed goes to your orchestrator with the exact error text or the precise on-device
behavior you saw — the "If this fails" note under each step tells you what that failure means.
Foreground push (step 9) and screenshots (13/16, if Storage is off) may be tracked as
known-limitation follow-ups rather than blockers — see `06_KNOWN_LIMITATIONS.md`.
