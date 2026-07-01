# For Brandon — turn on the Stock-Track "owner tools" backend

This is a short, one-time setup in **your** Firebase project (**easy-stock-track**). It
switches on the small backend the in-app **owner tools** need — the built-in chat with
us, the "report a problem" button, and the report list. It's all in your own project;
nothing here touches anyone else's app or data.

Nothing to install, no code. Just a few toggles in the Firebase console, plus (optional,
for two-way chat) adding one email address as a member. **~10 minutes.**

---

## 🔒 READ THIS FIRST — security (important)

**You never send us any secret. Ever.**

- ❌ Do **NOT** email, message, or upload a **service-account file** (a `.json` key), a
  **token**, a **password**, or **any credential**.
- ✅ The only thing you do to give us access is **add an email address as a member** of
  your project with a limited role (Step 4). That's a *permission*, not a secret — you can
  see it and remove it any time in the console, and it can be scoped to only what's needed.

If anyone ever asks you to send a key file or a token, the answer is no — that's not how
this works.

**Whose email to add (Step 4):** ideally a **dedicated "ops" Google account** made just
for this (cleanest — easy to remove later). If that's not handy, Pete's Google account is
fine. Either way it's just a member with a limited role — no key changes hands.

---

## The steps (in the Firebase console)

Open the [Firebase console](https://console.firebase.google.com/) and pick the
**easy-stock-track** project.

### Step 1 — Turn on the database (Firestore)
1. Left menu → **Build → Firestore Database**.
2. Click **Create database**.
3. Choose **Production mode** (we'll lock it down in Step 3), pick the region closest to
   you, and finish.

### Step 2 — Turn on anonymous sign-in
This lets the app quietly give each phone an ID so its chat + reports are private to it —
with **no login screen** for anyone.
1. Left menu → **Build → Authentication** → **Get started** (if it's the first time).
2. Open the **Sign-in method** tab.
3. Find **Anonymous** in the list → **Enable** → **Save**.

### Step 3 — Apply the security rules (locks it to the owner)
These make sure each phone can only ever read/write **its own** chat and reports. We've
already written the exact rules and committed them in the app's code:
- Database rules: **`firestore.rules`** (in the Stock-Track repo root)
- File/screenshot rules: **`storage.rules`** (in the Stock-Track repo root)

Easiest path: **send those two files to whoever runs the Firebase CLI** (us), and after
Step 4 we deploy them for you with one command — no console editing needed. If you'd
rather do it yourself: Firestore console → **Rules** tab → paste the contents of
`firestore.rules` → **Publish**; and Storage console → **Rules** tab → paste
`storage.rules` → **Publish**.

*(If you don't plan to attach screenshots to reports, you can skip Storage for now — chat
and text reports work without it.)*

### Step 4 — Add the ops email as a member (only needed for two-way chat)
The app can already save chat + reports into your project after Steps 1–3. This last step
is only so **we can read your messages and reply back** from our side.
1. Firebase console → the **gear icon (Project settings) → Users and permissions**
   (or Google Cloud console → **IAM & Admin → IAM** for the same project).
2. Click **Add member**.
3. Enter the **ops Google account email** (dedicated account preferred, else Pete's).
4. Give it these **minimum roles** (nothing more):
   - **Cloud Datastore User** — role id `roles/datastore.user` (read/write Firestore)
   - **Storage Object Admin** — role id `roles/storage.objectAdmin` (only if you enabled
     Storage in Step 3, for report screenshots)
5. **Save.**

That's everything. No keys, no tokens, no files leave your project.

---

## What happens on our side (for reference — nothing for you to do)

Our tooling connects to your project using **your granted permission**, not a key:
the ops account runs `gcloud auth application-default login` once, and our script
(`scripts/stocktrack_chat.js`) talks to **easy-stock-track only** (it refuses to run
against any other project). So there's never a secret to hand over, and it can't touch
anything but Stock-Track.

---

## What you'll be able to do once this is on
- Open Stock-Track → tap the little **support** button (dev builds) → **owner tools**.
- **Chat** with us right inside the app.
- **Report a problem** with a note (and a screenshot) → it lands in your **report list**,
  where you can mark it, comment, or flag it.
- We can **read and reply** to your messages from our side.

Any questions, just ask — happy to hop on a call and click through it together.
