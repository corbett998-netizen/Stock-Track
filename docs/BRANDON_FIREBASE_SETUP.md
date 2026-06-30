# Stock-Track — Brandon's Firebase Setup (plain-English, ~15 min)

> This is the ONE thing that unlocks everything next for Stock-Track: (a) sending you real test builds through a proper tester pipeline, and (b) wiring the app to live cloud data later. Do it with YOUR OWN Google account — this is your project, separate from anything else.
>
> You do NOT need a credit card. The free tier (Spark plan) covers all of this for early/dev use.

## Part 1 — Create your Firebase project (~5 min)
1. Go to **console.firebase.google.com** and sign in with **your own Google account** (the account you want to own this app).
2. Click **"Create a project"** (or "Add project").
3. Name it — e.g. **"Stock-Track"** (or "stock-track-hvac"). Click **Continue**.
4. Google Analytics: you can toggle it **OFF** for now → **Continue** → **Create project**. Wait ~30 seconds → **Continue**.

## Part 2 — Register the Android app (~3 min)
1. On the project home screen, click the **Android icon** (or "Add app" → Android).
2. **Android package name** — type it EXACTLY: `com.stocktrack.app` (this must match the app — it already does).
3. App nickname (optional): "Stock-Track".
4. Leave the SHA-1 box empty for now (optional; only needed for certain sign-in features later). Click **"Register app"**.
5. Click **"Download google-services.json"** and save that file.
6. The next screens tell you to "add the Firebase SDK" — you can **Skip** those; I handle the app side. Click Next / Continue / Skip until it finishes.

## Part 3 — Hand the config back
- Send me (or drop into the repo) the **`google-services.json`** file from Part 2.
- This file is the app's **connection config** (your project id + app id + a public client key). It is NOT an admin secret — it's meant to live inside the app. (The sensitive admin/service-account keys are a different thing you never have to touch for this.)

## Part 4 — Turn on App Distribution (~3 min — this is how I send you test builds)
1. In the Firebase console → left menu → **"Release & Monitor"** → **"App Distribution"** → **"Get started"**.
2. Open the **"Testers & Groups"** tab → create a group named **`stocktrack-testers`** → add **your email** and **Pete's email** as testers.

## Part 5 — (Later) Firestore for real data
- When we're ready to switch Stock-Track from mock data to real live data: Firebase console → **"Firestore Database"** → **"Create database"** → start in test mode (we'll add proper rules) → pick a region near you. I then wire the app to it (one small change at the data layer — the screens don't change). Free tier is plenty to start.

## Part 6 — Your owner-comms chat (automatic — nothing extra for you)
- This SAME Firebase project will also host your **owner-to-orchestrator chat** (how you'll direct your AI dev team from inside the app, like Pete does) — using its own separate collections in your project. **You don't do anything extra for this** in setup; once your project + Auth exist, the orchestrator provisions the chat side automatically. It stays entirely in YOUR project (never Blueprint Fitness's).

## What I do once you've done Parts 1–4
- Put your `google-services.json` into the app (no UI changes).
- Set up a Stock-Track ship script pinned to **your** project + app id → send a real build to the **stocktrack-testers** group (proper pipeline, not a chat file).
- Later (Part 5): swap the data layer from mock → your Firestore, documented.

## Boundaries (so nothing crosses wires)
- This is **your** Firebase project — Stock-Track will only ever point here. It never touches Pete's Blueprint Fitness Firebase, secrets, or signing.
- Debug-signed test builds are fine for now; a proper Stock-Track signing key comes later (and never gets committed to the repo).
