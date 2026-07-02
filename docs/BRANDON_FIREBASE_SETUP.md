# Stock-Track — Brandon's Firebase Setup — SUPERSEDED

> **This document has been superseded. Do not follow the steps that used to be here.**
>
> The single, canonical Firebase setup guide is now
> **`docs/brandon_handoff/02_FIREBASE_SETUP.md` — see there.**

That guide is the one source of truth for the whole Firebase side of Stock-Track, in
plain-English, non-coder, step-by-step form:

- Create / confirm **your own** Firebase project and register the Android app.
- Turn on the database — **Firestore in Production mode** (the security rules lock it down;
  never "test mode").
- Enable **Anonymous sign-in**.
- **Storage** (later) + **Push / FCM** expectations.
- Deploy the **security rules**.
- **Grant your orchestrator access** — a revocable permission (a role), **never a key**.
- **App Distribution** — the optional tester pipeline (enable it, the `stocktrack-testers`
  group, the **Firebase App Distribution Admin** role, and the app id the ship script needs)
  in **Part H**.

This file is kept only so existing links don't break.
