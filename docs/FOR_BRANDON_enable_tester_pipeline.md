# For Brandon — turn on the Stock-Track tester pipeline (3 steps, ~5 min)

> This is the one thing that lets Pete's setup send you real Stock-Track test builds through a proper tester pipeline (instead of a file link). You do it in **your own** Firebase console, on **your own** Google account. All three steps are just clicks — no coding.

## 🔒 SECURITY — read this first (important)
**Do NOT share any admin keys, service-account keys, passwords, CI tokens, or private credentials — with anyone, ever.** You never need to send a key or token to enable this.

The ONLY correct way to give access is through **Firebase / Google Cloud permissions** — i.e. adding a person's Google account as a member with a role, inside the console. That's step 3 below. If anything ever asks you to copy/paste a secret key or token to share it, stop — that's not how this works.

## Step 1 — Turn on App Distribution (~1 min)
1. Open your project in the Firebase console (**console.firebase.google.com** → your **easy-stock-track** project).
2. Left menu → **Release & Monitor** → **App Distribution** → **Get started**.

## Step 2 — Create the tester group (~2 min)
1. In App Distribution, open the **Testers & Groups** tab.
2. Create a group named exactly: **`stocktrack-testers`**.
3. Add two emails to it: **your own email** and **`peter.holmes.mitra@gmail.com`**.

## Step 3 — Grant upload access the SAFE way (permissions only, ~2 min)
So Pete's setup can push builds into your project, add his Google account as a **member with a role** — this is a permission grant, **not** a key:
1. Firebase console → the **gear/settings icon** (top-left) → **Users and permissions** (this is the Google Cloud IAM permission list for your project).
2. Click **Add member** → enter **`peter.holmes.mitra@gmail.com`**.
3. Give the role **Firebase App Distribution Admin** (search "App Distribution" in the role picker). → **Save**.

That's it. This grants access through Google's permission system only — no key, token, or password is ever shared. You can remove the access anytime from the same screen.

## What happens next
- Once these three are done, Pete's setup can send Stock-Track builds straight to the **stocktrack-testers** group — you'll get them like any other tester build.
- Later (a separate step) we switch the app from placeholder data to your real live data — that needs you to create the database in the same project, and we'll walk through it then.

## Boundaries (so nothing crosses wires)
- This is **your** project (easy-stock-track). Stock-Track only ever points here — it never touches Pete's Blueprint Fitness project, keys, or data.
- Debug-signed internal test builds are fine for now; a proper Stock-Track signing key comes later (and also never gets shared or committed).
