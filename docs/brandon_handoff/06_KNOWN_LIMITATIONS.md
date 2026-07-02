# Stock-Track — Known Limitations (the honest list)

> No sugarcoating. This is what is **not** finished, **not** signed, deferred, or still
> **owed on your device** once you're on your own Firebase. Read it so nothing surprises you
> during `05_DOGFOOD_FLOW.md`. Items are tagged so you can tell a *temporary setup gap* from a
> *deliberate later-slice* from a *pending owner decision*.

---

## 1. The build is a DEBUG APK, not a signed release  · [temporary]

- What you're installing is a **debug-signed** Android build. It is fine for you and a small
  set of trusted testers, but it is **not** a proper release build and is **not** suitable for
  the public / a store listing.
- A real release needs a **Stock-Track signing key (keystore)** — **yours**, generated
  deliberately, backed up off-machine, and **never committed to the repo or shared**. That is
  a separate, deliberate step (it's long-lead and permanent, so it's not rushed here).
- **iOS is not built at all yet.** Building for iPhone requires a Mac; only Android exists
  today. *(Owed later.)*
- *Never share:* when the signing key is created, it and its password stay with you and are
  never sent to anyone or checked into git.

## 2. Firebase App Distribution isn't on for your project yet → delivery is by file/link  · [temporary — you can fix]

- The proper "tester pipeline" (builds land on your phone as an App Distribution invite) needs
  **you** to turn on **App Distribution** in your Firebase console and create the tester group
  — see `02_FIREBASE_SETUP.md` **(Part H — App Distribution)**.
- **Until you do that, builds reach you as a plain file / download link.** That works for
  dogfooding; it's just not the polished pipeline.
- *Requires Brandon (you) personally:* enabling App Distribution and granting your ops contact
  the App-Distribution role (a permission, **never a key**) is what flips delivery from
  file-link to proper pipeline.

## 3. Push notifications — FIXED and PROVEN on the builder's device  · [re-confirm on yours]

- Earlier, a reply appeared inside the chat but **no push banner showed**. Diagnosis: the
  *sending* side was always fine (a real push was accepted by Google's messaging service),
  but a **foregrounded** Android app does not automatically show an incoming push as an
  on-screen banner.
- The fix (a foreground heads-up notification via `flutter_local_notifications`, plus the
  Android-13 permission, a high-importance channel, and the tap deep-link) is now **proven on
  the builder's device: the foreground banner pops, the background notification pops, and
  tapping it opens the chat — all three confirmed on-device.**
- **What this means for you:** this is expected to work, but you re-confirm it on **your own
  device + your own Firebase** via `05_DOGFOOD_FLOW.md` **steps 9–11** (foreground banner,
  background banner, tap-to-open). *If this fails:* the most common cause is notifications not
  being enabled for the app — check Android **Settings → Apps → (this app) → Notifications** and
  turn them on, then retry.

## 4. Copy-message confirm (fade-to-gray + copied ✓) — DONE  · [implemented]

- Copying a chat message now **dims the bubble to gray and shows a small green "copied ✓" badge**
  (tappable to undo; auto-reverts after ~1.8s) — matching the reference harness, so you can see
  exactly what you copied before pasting it into ChatGPT.
- The old single-bubble "Copied" snackbar was removed (the bubble itself is the confirm now);
  bulk / multi-select copy keeps its snackbar.
- Ships in the fresh build — confirm on-device (copy a bubble → it grays + shows "copied ✓").

## 5. Floating tool cluster + workflow tagging — PENDING OWNER REVIEW  · [owner decision]

Two harness-surface items are deliberately **not** auto-applied because they're your call:

- **Floating-cluster layout / colours.** Your cluster currently has 7 buttons all one accent
  colour, with the **mic at the top** and two extra buttons (**Poke** and **Command center**)
  the source design doesn't carry in the cluster. The recommendation is to (a) restore a small
  per-role colour palette so tools are recognisable by colour, (b) move the mic off the top
  slot, and (c) demote the redundant Poke + leftover Command-center. All are one-line config
  edits — **held for your OK** because it's a muscle-memory surface (you should pick the final
  order).
- **Workflow tagging** (tagging chat messages to route them to different work "lanes"). The
  full version is a **large** feature and only earns its keep if you run a multi-lane
  orchestrator. Options on the table: (a) full two-dimension tagging, (b) a lighter free-form
  conversation-label only, or (c) leave it deferred. **Your decision** — it's currently
  deferred. The related chat-header actions (stream-colour palette, copy-a-work-area) ride on
  this same decision.

## 6. Data is still MOCK — the app doesn't save real inventory yet  · [later slice, by design]

- Firebase **Core** is wired and the app connects to **your** project, but the **inventory /
  installation data is still in-memory placeholder data** that resets when you close the app.
- Switching to real saved cloud data is a **separate future slice**: it's a small, well-defined
  swap at one place in the code (the app already talks to data through an interface, so the
  screens don't change). It just hasn't been done yet.
- **What this means for you:** don't expect stock changes to persist between app opens yet.
  That's expected, not a bug.

## 7. Screenshots need Storage turned ON (off by default)  · [temporary — you enable]

- The shipped default has cloud **Storage switched off** so the very first proof can be pure
  text (text chat + text reports need only Firestore). Reports still capture the note, device
  logs, screen, build, and platform without Storage.
- **Screenshot attach + retrieval (dogfood steps 13 & 16) will not work until you turn Storage
  on** in your Firebase console and your orchestrator deploys the storage rules (`storage.rules`
  is already in the repo).
- *Requires Brandon (you) personally:* enabling Storage. Everything else (rules deploy) your
  orchestrator handles.

## 8. Mic — on-device recognizer parity + a homophone caveat  · [confirm on your device]

- The mic uses the phone's **on-device** recognizer with byte-identical config to the reference
  (dual-engine: on-device SpeechRecognizer by default + an optional offline engine on long-press;
  continuous re-arm across a pause; fills the report draft). The earlier **online cloud**
  recognizer (which name-predicts homophones, e.g. "mic" → "Mike") was already removed — that was
  the real cause of the "Mike" spelling, and it is gone.
- **Homophone caveat (not app-fixable):** "mic" and "Mike" are exact homophones; the on-device
  recognizer chooses between them from its language model + surrounding context, so an occasional
  flip can still happen — identically to the reference app. There is no per-word forcing in the
  platform API. This is best-achievable parity, not a per-utterance guarantee.
- Confirm on-device (`05_DOGFOOD_FLOW.md` step 12). Quick parity sanity-check: say "mic" a few
  times on both this app and the reference on the same phone — expect similar behavior.
- Minor open item: the offline model's distribution/licensing (bundled vs downloaded) is a
  pre-public-release cleanup, not a dogfood blocker.

## 9. Chat image / file attachments are not in the chat composer yet  · [deferred, Storage-gated]

- You can attach a **screenshot to a report**, but **sending an image or file directly in the
  chat** (and rendering it inline) is not built yet. It's a Storage-gated fast-follow, not part
  of the first proof.

## 10. The independent readiness AUDIT has not been run  · [gate not yet passed]

- There is a written GO/NO-GO audit plan (8 gates: clean separation, no secrets, real no-key
  access, live chat loop, reports-with-evidence, dogfood loop, on-device reachability,
  stand-up-from-docs), but the **audit itself hasn't been executed** by an independent reviewer.
- **What this means:** the harness is handed to you as *built and de-risked*, and your dogfood
  (`05_…`) is your own proof — but a formal, independent "ready" sign-off is still pending. Some
  gates (push on-device, mic on-device, the docs cold-read) will only turn green once you're on
  your own setup.

---

## Quick summary — what's owed vs what you switch on vs what's a decision

| Item | Type | Who acts |
|------|------|----------|
| Signed release build + keystore; iOS build | owed later | you (deliberate, later) |
| App Distribution pipeline | temporary setup | **you** (console) |
| Push (foreground + background + tap) | proven on builder's device; re-confirm on yours | you (dogfood steps 9–11) |
| Copy fade-to-gray badge | deferred, low risk | orchestrator (queued) |
| Cluster layout/colours + workflow tagging | owner decision | **you decide** |
| Real (saved) inventory data | later slice | orchestrator (future) |
| Screenshots (Storage) | temporary setup | **you** enable + orch deploys rules |
| Mic re-arm confirmation | owed on your device | you (dogfood step 12) |
| In-chat image/file send | deferred | orchestrator (fast-follow) |
| Independent readiness audit | gate pending | independent reviewer |

*Never share:* none of the above ever requires you to hand over a key, token, service-account
file, or password. Every access you grant is a revocable **permission** in your own console.
