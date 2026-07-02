# 02 — Firebase Setup (for Brandon + Brandon's orchestrator)

> Plain-English, non-coder, step-by-step. This turns on the small cloud backend the app's
> owner tools need: the in-app chat with your dev team, the "report a problem" flow, the
> report list, screenshots (later), and push notifications. Everything here uses **your own**
> Firebase project and **permissions only** — you never hand over a key, token, or password.

---

## 🛑🛑 READ FIRST — THIS MUST BE **YOUR OWN** FIREBASE PROJECT 🛑🛑

**You (Brandon) create and own the Firebase project, under your own Google account.**

- ✅ **DO:** create the project in **your** Google account, so you are the Owner in the
  Firebase console and can see/change everything.
- ❌ **DO NOT** reuse someone else's project. In particular, do **not** use any project that
  was only used to *prove/demo the pattern* for you — a proof/test project belongs to
  whoever made it, not to you. If you did not create it and cannot open it as Owner in your
  own console, it is not yours — make your own.
- ❌ **DO NOT** point the app at the reference/original app's Firebase project (the app this
  pattern was copied from). This app must only ever talk to **your** project.

Why this matters: the project is where **your** chat, reports, and (later) real data live.
If it isn't a project you own, you can't control access, can't grant your dev team read/reply
permission safely, and your data isn't yours. **This is called out again at every step below.**

> **You will see this reminder at each relevant step.** If any step ever seems to point at a
> project you didn't create, stop and check — it should always be your own.

---

## How to read this doc — the markers

Each step is tagged so you and your orchestrator know who does what and what "good" looks like:

- **✅ Expected result** — what you should see when the step worked.
- **⚠️ If this fails** — the most common thing that goes wrong + how to recover.
- **👤 Requires Brandon (console) personally** — only you can do this, in the Firebase
  console, signed in as the project Owner. Your AI/orchestrator **cannot** click console
  buttons for you.
- **🤖 Your orchestrator can do this** — a repo/command step your AI dev team (orchestrator)
  can run once you've granted permission. You don't have to do these yourself.
- **🔒 Never share** — a hard "do not send this to anyone" reminder.

---

## 🔒 The security model in one screen — permissions, never keys (READ THIS)

**You never send anyone a secret. Ever.** The way your dev team's orchestrator connects to
your project is by a **permission you grant** (an email added as a member with a limited
role) — not by a downloaded key file.

- **How your orchestrator signs in:** it uses **Application Default Credentials (ADC)** —
  Google Cloud's permission-based login. The granted identity runs one command,
  `gcloud auth application-default login`, one time in a browser. After that, the tooling
  talks to your project using that **granted permission**, with **no key file** anywhere in
  the repo.
- **The connecting script is pinned to your project** and refuses to run against any other
  project (a built-in separation guard aborts if it detects any identifier from the
  reference/original app). So it structurally cannot touch anyone else's data.

### 🔒 Never share — the hard list

Do **not** email, message, upload, paste into a chat, or commit to the repo, any of:

- **Service-account key files** (`.json` admin keys / "service account" downloads)
- **Passwords** (your Google account password, any account password)
- **Private tokens** (CI tokens, API tokens, OAuth tokens, personal access tokens)
- **`.env` files, keystores, `key.properties`, ADC credential files**
- **Any personal credential** of any kind

If anyone ever asks you to send a key file or a token, the answer is **no** — that is not how
this works. Access is granted **only** by adding an email as a member with a limited role
(Part G), which you can see and remove any time. **Never paste any of the above into an
unsafe place** (email, public chat, screenshots, the repo).

> ✅ **One safe exception, and it is NOT a secret:** `google-services.json` (the app's
> connection config). It contains your project id, app id, and a *public* client key that is
> **meant to ship inside the app**. It is fine to place it in the repo (Part B). It is not an
> admin secret — the sensitive admin keys are a different thing you never touch.

---

## Part A — Create / confirm YOUR Firebase project 👤

> 🛑 **Reminder: this must be a project YOU create in YOUR Google account.**

**👤 Requires Brandon (console) personally.** No credit card needed — the free tier (Spark)
covers all of this for early/dev use.

1. Go to **console.firebase.google.com** and sign in with **your own Google account**.
2. Click **Create a project** (or **Add project**).
3. Give it a name (e.g. **"Stock-Track"**). Firebase will show you the **project id** it
   generates from the name (lowercase, may add a suffix) — note it down. Click **Continue**.
4. Google Analytics can be **OFF** for now → **Continue** → **Create project**. Wait ~30s →
   **Continue**.

- ✅ **Expected result:** you land on the project home screen, and the **gear → Project
  settings** page shows a **Project ID** that is yours, with **you as Owner** under
  *Users and permissions*.
- ⚠️ **If this fails:** if "Create project" is greyed out or you're dropped into a project
  you don't recognise, you may be signed into the wrong Google account. Sign out, sign back
  in with **your** account, and start again.

### The project id the repo currently expects

The repo's config file `harness/project.config.json` currently pins the Firebase project to
a specific **project id** (field `firebase.projectId`) and storage bucket (field
`firebase.storageBucket`).

- 🛑 **Confirm that pinned project id is a project YOU created and can open as Owner.**
  - If it **is** yours → great, keep it; nothing to change.
  - If it is **not** yours (a placeholder, or a project someone else made to demo the
    pattern) → create your own project (steps above) and tell your orchestrator the **new**
    project id + bucket so it can update `harness/project.config.json` and regenerate the
    in-app config (see Part B, "If the project identity changed").

---

## Part B — Register the Android app + place `google-services.json`

> 🛑 **Reminder: register the app inside YOUR project from Part A.**

### B1 — Register the Android app 👤

**👤 Requires Brandon (console) personally.**

1. On your project home, click the **Android icon** (or **Add app → Android**).
2. **Android package name** — type it **EXACTLY** as the app expects. The app's package id is
   set in the repo config (`app.androidPackageId`) and is currently **`com.stocktrack.app`**.
   It must match character-for-character.
3. App nickname (optional): "Stock-Track".
4. Leave **SHA-1 empty** for now (only needed for certain sign-in features later).
5. Click **Register app**.

- ✅ **Expected result:** the console offers a **Download google-services.json** button.
- ⚠️ **If this fails:** "package name already in use" means the app is already registered in
  this project — that's fine, open the existing Android app under **Project settings → Your
  apps** and download its `google-services.json` from there instead.

### B2 — Download `google-services.json` 👤 🔒

**👤 Requires Brandon (console) personally.**

1. Click **Download google-services.json** and save the file.
2. Hand it to your dev team / drop it into the repo (your orchestrator can place it — see B3).

- 🔒 **Never share note:** `google-services.json` is safe to share with your dev team and to
  commit — it is the app's connection config, **not** an admin secret. (Do **not**, however,
  ever share a *service-account* `.json`, which is a different, secret file.)
- ✅ **Expected result:** you have a file named exactly `google-services.json`.
- ⚠️ **If this fails / next screens:** the console then says "add the Firebase SDK" — you can
  **Skip** all of that; the app side is already wired. Click Next/Continue/Skip until it
  finishes.

### B3 — Place the file in the app 🤖

**🤖 Your orchestrator can do this** (a repo file move — no console needed).

- Put `google-services.json` at exactly: **`android/app/google-services.json`**
  (this is the path the repo config expects: `firebase.clientConfigPath`).

- ✅ **Expected result:** the file exists at `android/app/google-services.json`; the next
  app build picks up your project id automatically.
- ⚠️ **If this fails:** if a build later says "google-services.json is missing" or shows the
  wrong project id, the file is in the wrong folder or is an old one — replace it with the
  fresh download and rebuild.

### If the project identity changed 🤖

**🤖 Your orchestrator can do this.** Only needed if you created a **new/different** project
(different project id) or changed any identity names.

- The Firebase **project id and app id reach the app through `google-services.json`** — so
  swapping to a new project = swap in the **new** `google-services.json` **and** update
  `harness/project.config.json` (`firebase.projectId`, `firebase.storageBucket`) so the
  orchestrator's scripts target the right project.
- If any **identity names** in the config change (project/app name, collection names, push
  title/channel/route, owner role), regenerate the in-app config:
  - `node harness/gen_app_config.js`
- ✅ **Expected result:** `node harness/gen_app_config.js --check` prints
  `GEN-APP-CONFIG RESULT: PASS` (the generated file is up to date).
- ℹ️ Note: the generated in-app config holds **names/labels**, not the project id itself — the
  project id lives in `google-services.json`. So a pure project swap = new
  `google-services.json` + updated `project.config.json`; regenerate only if names changed.

---

## Part C — Enable Anonymous sign-in 👤

> 🛑 **Reminder: do this in YOUR project.**

**👤 Requires Brandon (console) personally.** This quietly gives each phone a private ID so
its chat and reports are its own — **with no login screen** for anyone.

1. Left menu → **Build → Authentication** → **Get started** (first time only).
2. Open the **Sign-in method** tab.
3. Find **Anonymous** → **Enable** → **Save**.

- ✅ **Expected result:** *Anonymous* shows **Enabled** in the Sign-in method list.
- ⚠️ **If this fails:** if you accidentally enable a paid identity product (GCIP) or it asks
  for billing, back out — you only want the **free** built-in *Anonymous* provider. If a
  billing prompt appears you took a wrong turn; cancel and re-open just the *Anonymous* row.

---

## Part D — Turn on the database (Firestore) 👤

> 🛑 **Reminder: do this in YOUR project.**

**👤 Requires Brandon (console) personally.**

1. Left menu → **Build → Firestore Database**.
2. Click **Create database**.
3. Choose **Production mode** (the security rules in Part F lock it down properly).
4. Pick the **region closest to you** and finish.

- ✅ **Expected result:** you see an empty Firestore **Data** tab. (It populates the first
  time the app or orchestrator writes.)
- ⚠️ **If this fails:** only create the true default database. If you see a prompt that spawns
  a *named* database requiring billing, that's the wrong one — cancel and create the standard
  default (free-tier, Native mode). Region can't be changed later, so pick the closest one.

---

## Part E — Storage (later) + Push / FCM expectations

### E1 — Storage (screenshots + chat images) — OFF for the first proof 👤

**👤 Requires Brandon (console) personally — but not yet.** Text chat and text reports work
**without** Storage. Screenshots/chat-images are a small **later** step.

- When you're ready: left menu → **Build → Storage → Get started**. The app keeps uploads
  gated off until then, and the Storage rules (Part F) are already committed and ready so
  nothing breaks the moment you turn it on.
- ✅ **Expected result (later):** Storage shows an empty bucket
  (`<your-project-id>.firebasestorage.app`).
- ⚠️ **If this fails:** if enabling Storage prompts for billing, the free tier is still fine
  for early dev — but confirm you're on the free (Spark) plan before adding a card.

### E2 — Push notifications (FCM) — nothing to enable 👤(one tap on phone)

- **Cloud Messaging (FCM) is auto-enabled with every Firebase project.** There is **no
  console toggle** and **no billing upgrade** needed. Push works as soon as your
  `google-services.json` is in place (Part B) and the token-write security rule is deployed
  (Part F).
- **No Apple/APNs key needed** for Android dogfood. (iOS push later would need an APNs key —
  out of scope here.)
- 👤 **On-device (you, once):** the first time you open a dev build, tap **Allow** on the
  notification permission prompt (Android 13+).
- ✅ **Expected result:** after tapping Allow, your phone can receive "Stock-Track Ops" push
  notifications; tapping one deep-links straight into the in-app chat.
- ⚠️ **If this fails:** if you tapped "Don't allow", turn notifications back on for the app in
  your phone's system Settings → Apps → (the app) → Notifications.

---

## Part F — Deploy the security rules (what they enforce)

> 🛑 **Reminder: rules deploy to YOUR project.**

The exact rules are already written and committed in the repo:
`firestore.rules` and `storage.rules` (repo root). They make sure **each phone can only ever
read/write its own** chat, reports, and files — and nobody else's.

**What the rules enforce (plain English):**

- **Chat** (`orchestratorChat/{uid}/messages`): a signed-in phone may **read and create**
  messages **only in its own thread** (thread id = that phone's anonymous UID). Messages are
  **append-only** — the client can't edit or delete them.
- **Your chat/token doc** (`orchestratorChat/{uid}`): the owner phone may **read and write its
  own** doc — this is where the app stores its **push token** (`fcmToken`) so the orchestrator
  can notify that device. Scoped to that UID only; no cross-user access.
- **Reports** (`stockIssueReports/{report}`): a phone may **create** a report only if it
  stamps its **own UID** on it, and may **read/update** only reports it owns (so you can
  triage: change status, comment, flag). **No client deletes.**
- **Wake signal** (`system/orchestratorPoke`): any signed-in phone may **bump** it (to wake
  the orchestrator); it is **not client-readable** — only the orchestrator reads it (via the
  Admin SDK, which bypasses rules).
- **Storage** (`stockIssueReports/{uid}/...` and `orchestratorChat/{uid}/media/...`): each
  phone reads/writes **only its own** screenshots and chat images.
- **Everything else is denied by default.**

### Two ways to deploy — pick one

**🤖 Your orchestrator can do this (recommended):** after you grant access in Part G, the dev
team deploys with one command each:

- `firebase deploy --only firestore:rules --project <your-project-id>`
- `firebase deploy --only storage --project <your-project-id>` (only once you enable Storage)

> Note: CLI deploy needs the deploying account to have rules-deploy permission on your project
> (a deploy-capable role or Owner). If the `roles/datastore.user` grant in Part G isn't enough
> to deploy, either use the console-paste path below yourself, or grant the deployer a rules
> role — your call as Owner.

**👤 Requires Brandon (console) personally (fallback, no dev-team needed):**

- Firestore console → **Rules** tab → paste the contents of `firestore.rules` → **Publish**.
- (Later, after enabling Storage) Storage console → **Rules** tab → paste `storage.rules` →
  **Publish**.

- ✅ **Expected result:** the console **Rules** tab shows the published rules with a recent
  timestamp; the app can now read/write its own data and is blocked from anything else.
- ⚠️ **If this fails:** a "permission denied" in the app usually means the rules aren't
  deployed yet (still on default-deny), or Firestore/Anonymous Auth (Parts C/D) isn't on yet.

---

## Part G — Grant your orchestrator access (permissions only) 👤 + 🤖

> 🛑 **Reminder: you grant access ON YOUR project — a permission, not a key.**

This is the **only** thing you do to let your dev team's orchestrator **read your messages and
reply**. It's an email added as a member with **one limited role** — no key changes hands, and
you can remove it any time.

**👤 Requires Brandon (console) personally:**

1. Firebase console → **gear → Project settings → Users and permissions**
   (or Google Cloud console → **IAM & Admin → IAM** for the same project).
2. Click **Add member / Grant access**.
3. Enter the **ops identity email** your dev team gives you (the account that will run the
   orchestrator).
4. Give it **one** role, nothing more:
   - **Cloud Datastore User** — `roles/datastore.user` (read/write Firestore only).
   - *(Add a Storage object role **only if/when** you enable Storage for screenshots — not
     needed for the text-only first proof.)*
5. **Save.**

- 🔒 **Never share:** you are adding an **email as a member** — that's it. Do **not** create or
  send a service-account key, token, or password. If asked for one, refuse.
- ✅ **Expected result:** the email appears under *Users and permissions* with the
  **Cloud Datastore User** role.
- ⚠️ **If this fails:** if you can't add members, you're likely not the project **Owner** —
  confirm Part A created the project under your account.

**🤖 Your orchestrator can do this (its side — no key, one time):**

- The granted identity runs **`gcloud auth application-default login`** once (browser sign-in).
- After that, the orchestrator's scripts connect to your project via that **permission (ADC)** —
  no key file anywhere.

- ✅ **Expected result:** `node scripts/stocktrack_chat.js --read` connects and (before you've
  sent any message) reports **no owner thread yet** — which is correct until you open the app
  and send once.
- ⚠️ **If this fails:** `BLOCKED | no Application Default Credentials` means the one-time
  `gcloud auth application-default login` hasn't been run yet (or was run as the wrong
  account). Run it as the granted ops identity.

---

## Part H — App Distribution: the tester pipeline (optional — for pipeline delivery instead of file/link) 👤 + 🤖

> 🛑 **Reminder: enable this in YOUR project from Part A — a permission, never a key.**

**App Distribution is optional.** Everything above (chat, reports, push) works **without** it.
Its only job is **how builds reach your phone**:

- **Without App Distribution** — your dev team sends each build as a plain **file / download
  link** you tap to install. This is perfectly fine for dogfooding.
- **With App Distribution** — each new build lands on your phone as a **tester invite**, the
  same way any beta app arrives (the "proper pipeline"). This is the upgrade this Part turns on.

You can **skip this for your first proof** and turn it on whenever you want the polished
pipeline — nothing else depends on it.

### H1 — Turn on App Distribution 👤

**👤 Requires Brandon (console) personally.** Free — no billing, no card.

1. Firebase console (your project) → left menu → **Release & Monitor → App Distribution →
   Get started**.

- ✅ **Expected result:** the App Distribution dashboard opens (empty until the first build is
  uploaded).
- ⚠️ **If this fails:** if a billing prompt appears, back out — App Distribution is on the free
  tier; you took a wrong turn. Re-open just **App Distribution → Get started**.

### H2 — Create the tester group 👤

**👤 Requires Brandon (console) personally.**

1. In App Distribution, open the **Testers & Groups** tab.
2. Create a group named **EXACTLY** `stocktrack-testers`. The ship script is pinned to this
   exact group name (its `TESTER_GROUP`), so a different name means an uploaded build has
   nowhere to land.
3. Add the testers: **your own email**, plus the **ops identity email your dev team gives you**
   (the same account as Part G) so they receive builds too.

- ✅ **Expected result:** a `stocktrack-testers` group exists with your email (and the ops
  email) listed as testers.
- ⚠️ **If this fails:** if you can't create a group, confirm App Distribution finished
  "Get started" (H1) and that you're the project **Owner** (Part A).

### H3 — Grant the uploader the App-Distribution role (permissions only) 👤 🔒

**👤 Requires Brandon (console) personally.** This is the **only** thing that lets your dev
team's orchestrator **push builds into your project** — an email added as a member with **one
role**, **not** a key. *(You can skip this if the orchestrator uploads under **your own**
authenticated account — see the note below.)*

1. Firebase console → **gear → Project settings → Users and permissions** (or Google Cloud
   console → **IAM & Admin → IAM** for the same project).
2. Click **Add member / Grant access**.
3. Enter the **ops identity email your dev team gives you** (the same account as Part G).
4. Give it the role **Firebase App Distribution Admin** (search "App Distribution" in the role
   picker) → **Save.**

- 🔒 **Never share:** you are adding an **email as a member** — that's it. Do **not** create or
  send a service-account key, token, or password. If asked for one, refuse.
- ✅ **Expected result:** the ops email appears under *Users and permissions* with the
  **Firebase App Distribution Admin** role.
- ⚠️ **If this fails:** if you can't add members, you're likely not the project **Owner** —
  confirm Part A created the project under your account.
- ℹ️ **Note (you may not need this grant):** if the orchestrator uploads while signed in as
  **your own** Owner account, it can already distribute — this role grant is only needed to let
  a **separate** ops account upload on your behalf. Either way, **no key is ever shared.**

### H4 — The app id the ship script needs 🤖

**🤖 Your orchestrator can do this (reference — no console step for you).** App Distribution
addresses a build by your **Android app id** (not the package name). It is the value the console
shows as **App ID**, and it lives in your `google-services.json` as `mobilesdk_app_id`, in the
form **`1:<your-project-number>:android:<hash>`**.

- The ship script (`scripts/stocktrack_ship.sh`) pins this app id as its **`APP_ID`**, alongside
  the pinned project id (`PROJECT_ID`) and tester group (`TESTER_GROUP`). It distributes with:
  `firebase appdistribution:distribute <apk> --app <APP_ID> --project <your-project-id>
  --groups stocktrack-testers`.
- 🛑 **If you ever swap to a different project** (new `google-services.json` → Part B), the app
  id changes too — tell your orchestrator so it updates the ship script's `APP_ID` to the new
  value read from the fresh `google-services.json`.

- ✅ **Expected result:** a shipped build uploads to your project and the `stocktrack-testers`
  group receives it as a tester invite on-device.
- ⚠️ **If this fails:** a `BLOCKED` / "cannot reach project" from the ship script usually means
  App Distribution isn't enabled yet (H1), the tester group name doesn't match `stocktrack-testers`
  exactly (H2), or the uploading account hasn't been granted access (H3).

---

## The data model, in plain English

Everything lives in **your** project. Names come from `harness/project.config.json`, so they
are config-driven (not hardcoded).

| What | Where (Firestore/Storage path) | Notes |
| --- | --- | --- |
| **Chat messages** | `orchestratorChat/{uid}/messages/{msgId}` | One thread per phone (`{uid}` = that phone's anonymous UID). Fields: `role` (you = `brandon`, team = `orchestrator`), `text`, `createdAt`, `via`. Append-only. |
| **Your device push token** | `orchestratorChat/{uid}` (field `fcmToken`) | The app stores its FCM token here so the orchestrator can push-notify your phone. Config: `push.tokenCollection` + `push.tokenField`. |
| **Reports** ("report a problem") | `stockIssueReports/{reportId}` | Fields: `userId` (stamped with your UID), `title`, `note`, `area`, `status`, plus (when Storage is on) `screenshots[]`, and device-log tail `logsInline`, orchestrator `comments[]`. |
| **Report screenshots** | Storage: `stockIssueReports/{uid}/{epochMillis}_{index}.{ext}` | Only when Storage is enabled (later). |
| **Chat image media** | Storage: `orchestratorChat/{uid}/media/{fileName}` | Only when Storage is enabled (later). |
| **Wake signal (poke)** | `system/orchestratorPoke` (field `pokedAt`) | The app bumps this whenever you send/file something; the orchestrator watches it to know when to read. Not client-readable. |
| **Dashboard/vision projections** | `system/workflowContext`, `system/agentStatus`, `system/vision` | Reserved for later dashboard features — not needed for the first proof. |

**How the orchestrator reads/writes SAFELY:**

- It uses the **Admin SDK over ADC** (the permission you granted), with the **project id
  pinned explicitly** from `harness/project.config.json` — so an ambient default can never
  redirect a write to the wrong project.
- A **separation guard** refuses to run if any identifier from the reference/original app is
  reachable in the resolved config — it is structurally incapable of touching another app.
- The Admin SDK **bypasses the security rules**, which is exactly why the rules only need to
  let the **owner phone** reach its own data and deny everyone else.
- Because your anonymous UID is a **runtime** value (a new one per install), the script
  **auto-discovers your active thread** (the newest one) — you never paste a UID.
- Safe-by-default tooling: `--dry-run` previews a write without touching anything, and
  `--selftest` checks the config/separation with **no credentials** needed.

**How push is sent (no Cloud Functions, no key):**

- After the orchestrator posts a reply/build message, it calls **`admin.messaging().send(...)`
  over ADC**. It reads your device token from `orchestratorChat/{uid}.fcmToken`, and the push
  **carries the message** so your phone renders it instantly on tap (Firestore stays the
  durable copy; the app de-dupes by message id).
- The push send **never throws** — a push hiccup can't break the chat write — and it is
  **inert until your phone has registered a token**, so it's safe to run before push is fully
  live on-device.

---

## Who does what — the split at a glance

| 👤 Requires Brandon (console) personally | 🤖 Your orchestrator can do this |
| --- | --- |
| Create/own the Firebase project (your Google account) — **Part A** | Place `google-services.json` at `android/app/` — **B3** |
| Register the Android app with the exact package id — **B1** | Update `project.config.json` + `node harness/gen_app_config.js` if identity changed — **Part B** |
| Download `google-services.json` — **B2** | Deploy `firestore.rules` / `storage.rules` (once granted) — **Part F** |
| Enable Anonymous Auth — **Part C** | Run `gcloud auth application-default login` (one time) — **Part G** |
| Create Firestore database — **Part D** | Read/reply to chat + triage reports via `scripts/stocktrack_chat.js` (ADC) — **data model** |
| Enable Storage (later) — **E1** | Send push via `admin.messaging()` over ADC — **data model** |
| Tap **Allow** on the notification prompt (phone) — **E2** | Preview writes with `--dry-run`, verify config with `--selftest` |
| Add the ops email as a member (`roles/datastore.user`) — **Part G** | Deploy dogfood builds pinned to your project |
| (Or) paste rules in the console yourself — **Part F fallback** | |
| *(Optional pipeline)* Enable App Distribution + create the `stocktrack-testers` group — **H1/H2** | Ship builds to `stocktrack-testers` via `scripts/stocktrack_ship.sh` — **Part H** |
| *(Optional pipeline)* Add the ops email as **Firebase App Distribution Admin** — **H3** | Update the ship script `APP_ID` if the project identity changes — **H4** |

---

## Quick on-device validation (once everything above is done)

1. Install the dev build; open the app; tap **Allow** on the notification prompt.
   - ✅ A private chat thread now exists in **your** project after you send one message.
2. Send a message from the in-app chat; the orchestrator runs `--read` and sees it.
3. Background the app; the orchestrator replies with `--send "test"`.
   - ✅ Your phone shows a **"Stock-Track Ops"** notification within a second or two.
4. Tap the notification → the app opens **straight to the chat** with the reply shown.
5. File a "report a problem"; it appears in your in-app report list and the orchestrator sees
   it with `--reports`.

**PASS =** message round-trips both ways, push arrives + deep-links to the chat, and a filed
report shows up on both sides — all in **your** project, with **no key** ever shared.

---

## Reference — the config values this doc points at

From `harness/project.config.json` (your project's identity — names/paths/ids only, never
secrets):

- App Android package id: `app.androidPackageId` (currently **`com.stocktrack.app`**)
- Firebase project id: `firebase.projectId` — **confirm this is YOUR project** (Part A)
- Storage bucket: `firebase.storageBucket` (`<your-project-id>.firebasestorage.app`)
- Client config path: `firebase.clientConfigPath` = `android/app/google-services.json`
- Chat collection: `collections.chatRoot` = `orchestratorChat`
- Reports collection: `collections.reports` = `stockIssueReports`
- Wake signal: `collections.poke` = `system/orchestratorPoke`
- Push: `push.title` / `push.androidChannelId` / `push.dataRoute` / `push.tokenCollection` /
  `push.tokenField`

**App Distribution (Part H) values are pinned in the ship script, not in `project.config.json`:**

- Tester group: `stocktrack-testers` and Android app id: `APP_ID` (form
  `1:<project-number>:android:<hash>`) — both in `scripts/stocktrack_ship.sh`. The app id also
  lives in `google-services.json` as `mobilesdk_app_id`.

> If you swap to a different project id, tell your orchestrator so it can update the config +
> `google-services.json` and regenerate the in-app config (Part B, "If the project identity
> changed").
