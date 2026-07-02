# For Brandon — turn on the Stock-Track tester pipeline — SUPERSEDED

> **This document has been superseded. Do not follow the steps that used to be here.**
>
> The single, canonical Firebase setup guide is now
> **`docs/brandon_handoff/02_FIREBASE_SETUP.md` — see there.**

The tester-pipeline steps now live in that guide as **Part H — App Distribution** (it's
**optional**; without it, builds still reach you as a plain file / download link). Same
plain-English, security-first form (**permissions only — never a key, token, or password**):

- Turn on **App Distribution** in your Firebase console — **H1**.
- Create the tester group named exactly **`stocktrack-testers`** and add your testers — **H2**.
- Grant the uploader the **Firebase App Distribution Admin** role (a member + role, not a key) —
  **H3**.
- Reference: the Android **app id** the ship script (`scripts/stocktrack_ship.sh`) needs — **H4**.

This file is kept only so existing links don't break.
