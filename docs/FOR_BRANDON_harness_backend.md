# For Brandon — turn on the Stock-Track "owner tools" backend — SUPERSEDED

> **This document has been superseded. Do not follow the steps that used to be here.**
>
> The single, canonical Firebase setup guide is now
> **`docs/brandon_handoff/02_FIREBASE_SETUP.md` — see there.**

Everything this note used to cover now lives in that guide, in the same plain-English,
security-first form (**you never send anyone a key, token, or password — access is a revocable
permission only**):

- Turn on the database — **Firestore in Production mode** (the committed security rules lock it
  down) — **Part D**.
- Enable **Anonymous sign-in** — **Part C**.
- Apply / deploy the committed **security rules** — **Part F**.
- **Add the ops identity email as a member** with `roles/datastore.user` (read/write Firestore
  only) so your dev team's orchestrator can read your chat and reply — **Part G**.

The one-time orchestrator side (`gcloud auth application-default login`, no key) is also in
**Part G**. This file is kept only so existing links (including the orchestrator scripts'
`BLOCKED | no Application Default Credentials` message) still resolve.
