# 01 — Environment Checklist (run this FIRST, before Firebase / dogfood)

> **Who runs this:** the orchestrator, on the machine that will actually do the work
> (build the app, run agents, ship builds). **Assume nothing is set up.** Brandon's
> machine may be fresh. This checklist proves — command by command — that the
> environment can build, source-control, and ship the app before any real work starts.
>
> **Reusable:** the checks are written against `<PLACEHOLDERS>` (see the variables table).
> Fill the table once and the same checklist works for this project or for the next app
> (Appharness). Nothing here is app-specific except the values you fill in.

---

## 0. The honest-blocker principle (read before you tick anything)

This checklist exists to catch a **half-set-up machine**, not to make us feel good.

- **Never write "looks good" when a check did not actually pass.** If a command errored,
  hung, printed nothing, or you didn't run it — the item is **NOT green**. Mark it
  `NOT READY` and name exactly what is missing.
- **No false green.** A skipped check is a failure, not a pass. "Probably fine" is a
  failure. "I'll do it later" is a failure for the gate.
- **Name the missing thing AND the fix.** Every failure gets: what is missing, the exact
  command / action that fixes it, and **who** must do it (some fixes are owner-only and the
  orchestrator physically cannot do them — say so).
- **Report facts, not hopes.** Paste the real command output into the result table at the
  bottom. A claim with no command output behind it does not count.
- **The gate is binary.** Either every REQUIRED item is proven green, or the environment is
  **NOT READY** and we do not proceed to Firebase / dogfood. There is no "mostly ready".

---

## 1. Variables — fill these in ONCE

Fill these for the project you're validating. Everything below uses them, so the checklist
is reusable across apps. (These are the app's OWN identifiers — safe to write here. Do NOT
paste any other/reference app's project id, package, UID, tokens, or keys into this repo.)

| Variable | Meaning | Value (fill in) |
|---|---|---|
| `<REPO_DIR>` | Absolute path to the working clone | `/mnt/c/dev/Brandons_App` |
| `<REPO_SLUG>` | GitHub `owner/repo` for THIS app's repo | `______/______` (verify in step 3.3) |
| `<FIREBASE_PROJECT>` | The app's own Firebase project id | `______` |
| `<ANDROID_PACKAGE>` | The app's Android package / applicationId | `______` |
| `<APP_DIST_APP_ID>` | Firebase App Distribution app id (for shipping) | `______` (in the ship runbook) |
| `<TESTER_GROUP>` | App Distribution tester group name | `______` |
| `<OPS_EMAIL>` | Google account the ops/cloud tooling authenticates as | `______` |

**Who-fixes legend** (used in every item):

- **[ORCH]** — the orchestrator/agent can fix this itself on the machine (install a CLI, run
  a clone, etc.). No admin, no owner-only account.
- **[BRANDON]** — owner-only. Needs Windows admin rights, an interactive account login
  (Google / GitHub) that only Brandon can complete, a Firebase-console or IAM change, GitHub
  repo ownership / write grant, a physical Android device, or a signing keystore. The agent
  **cannot** do these; it must ask Brandon.
- **[EITHER]** — whoever is at the machine can do it.

---

## 2. Shell & terminal

### 2.1 WSL2 is installed and this shell is really running under WSL2  — REQUIRED
- **Check:** `uname -r`
- **Expected:** the kernel string contains `microsoft-standard-WSL2` (e.g.
  `6.6.x-microsoft-standard-WSL2`). Optional cross-check from a Windows terminal:
  `wsl.exe -l -v` shows the distro with **VERSION 2**.
- **If this fails:** if `uname -r` has no `WSL2`, you are on WSL1 or not in WSL. In an
  **admin** Windows PowerShell: `wsl --install` (fresh), or `wsl --set-version <distro> 2`
  to upgrade an existing WSL1 distro, then reopen the WSL terminal.
- **Who fixes:** **[BRANDON]** — needs Windows admin; the agent can't elevate.

### 2.2 Zellij is installed and runnable  — REQUIRED (fleet / multi-agent terminals)
- **Check:** `zellij --version`
- **Expected:** prints `zellij 0.x.y` (a version line), exit 0.
- **If this fails:** `command not found` → install to the user profile (no admin needed):
  `bash <(curl -L https://zellij.dev/launch)` **or** download the release binary from
  `github.com/zellij-org/zellij/releases` into a dir on `PATH` **or** `cargo install zellij`
  if Rust is present. Re-open the shell and re-run the check.
- **Who fixes:** **[ORCH]** (user-local install), escalate to **[BRANDON]** only if PATH /
  profile changes need his machine setup.

---

## 3. Source control

### 3.1 Git is installed  — REQUIRED
- **Check:** `git --version`
- **Expected:** `git version 2.x.y`.
- **If this fails:** `sudo apt-get update && sudo apt-get install -y git` (Debian/Ubuntu WSL).
- **Who fixes:** **[ORCH]** if it can `sudo`; else **[BRANDON]**.

### 3.2 GitHub authentication works  — REQUIRED
- **Check (preferred, GitHub CLI):** `gh auth status`
- **Expected:** `Logged in to github.com as <user>` with a token that has `repo` scope.
- **Fallback check (no gh):** `git ls-remote https://github.com/<REPO_SLUG>.git HEAD` —
  expected: prints a commit SHA + `HEAD` (proves read auth to the remote), no
  `Authentication failed` / `could not read Username`.
- **If this fails:** install gh (`sudo apt-get install -y gh`) then `gh auth login` (choose
  HTTPS, authenticate in browser) — **interactive, Brandon's GitHub account**. Or configure a
  credential helper / PAT with `repo` scope. Never commit the PAT.
- **Who fixes:** **[BRANDON]** — interactive login on his GitHub account. [ORCH] can install
  the CLI but cannot complete Brandon's browser login.

### 3.3 The CORRECT repo is cloned at `<REPO_DIR>`  — REQUIRED
- **Check:**
  `git -C <REPO_DIR> rev-parse --show-toplevel` and
  `git -C <REPO_DIR> remote get-url origin`
- **Expected:** the toplevel equals `<REPO_DIR>`, and the origin URL points at
  **`<REPO_SLUG>`** (this app's own repo) — **not** any other/reference app's repo. Record
  the exact origin URL in the results table so the slug is proven, not assumed.
- **If this fails:** wrong/no clone → `git clone https://github.com/<REPO_SLUG>.git <REPO_DIR>`.
  If origin points at the wrong repo, stop and confirm with Brandon before touching it — do
  not silently re-point a repo.
- **Who fixes:** **[ORCH]** (clone), but **[BRANDON]** must confirm the correct slug if there
  is any doubt.

### 3.4 Brandon (and the ops account) have WRITE access to the repo  — REQUIRED
- **Check (non-destructive, preferred):**
  `gh api repos/<REPO_SLUG> --jq .permissions` — or —
  `gh repo view <REPO_SLUG> --json viewerPermission -q .viewerPermission`
- **Expected:** permissions include `"push": true` (or `viewerPermission` is `WRITE`,
  `MAINTAIN`, or `ADMIN`). Read-only (`"push": false` / `READ`) is **NOT** enough — we must
  be able to land commits.
- **Fallback check (no gh, still non-destructive):** `git -C <REPO_DIR> push --dry-run origin HEAD`
  — expected: it reports what *would* update (or "up to date") with **no** `permission denied`
  / `403`. `--dry-run` does not actually write.
- **If this fails:** the account has read-only access. **Brandon** (repo owner) must grant the
  working account (his own login, or `<OPS_EMAIL>` if the ops side pushes) **Write** on the
  repo: GitHub → repo → *Settings → Collaborators (and teams) → Add* with the **Write** role.
- **Who fixes:** **[BRANDON]** — only the repo owner can grant write access.

---

## 4. Flutter & Android toolchain

### 4.1 Flutter is installed and healthy  — REQUIRED
- **Check:** `flutter doctor`  (and `flutter doctor -v` for detail)
- **Expected:** a `[✓] Flutter (Channel ...)` line and **no `[✗]`** on the categories we
  need (Flutter, Android toolchain). `[!]` warnings are acceptable only if they are for
  things we don't use (e.g. Chrome/web, Visual Studio for Windows desktop) — call each one
  out honestly rather than glossing over it.
- **If this fails:** `flutter: command not found` → install Flutter and add `flutter/bin` to
  `PATH` (git clone the stable SDK, or the official tarball), then re-run `flutter doctor`.
- **Who fixes:** **[ORCH]** (SDK install + PATH), escalate to **[BRANDON]** for machine-level
  PATH/profile if needed.

### 4.2 Android toolchain: SDK + adb present and licenses accepted  — REQUIRED
- **Check:**
  `flutter doctor -v` (read the **Android toolchain** section) and `adb --version`
- **Expected:** Android toolchain `[✓]` with an Android SDK path and **"All Android licenses
  accepted."**; `adb --version` prints an "Android Debug Bridge version ...".
- **If this fails:**
  - Android toolchain `[✗]`/`[!]` → install the Android SDK command-line tools (or Android
    Studio), set `ANDROID_HOME`/`ANDROID_SDK_ROOT`, and run `flutter doctor --android-licenses`
    and accept all.
  - `adb: command not found` → add `<sdk>/platform-tools` to `PATH` (installs with the SDK).
- **Who fixes:** **[ORCH]** for SDK/CLI install + license accept; **[BRANDON]** if it needs
  Android Studio GUI on his machine or admin.

### 4.3 A build target exists: device / emulator / install path  — REQUIRED
- **Check:** `flutter devices` and `adb devices`
- **Expected:** at least ONE usable target — a connected physical Android phone (USB
  debugging on) **or** a running emulator — appears (not just "web"/"linux"). `adb devices`
  lists it as `device` (not `unauthorized` / `offline`).
- **If this fails:**
  - No devices → start an emulator (`flutter emulators --launch <id>`, needs an AVD created in
    Android Studio) **or** plug in a phone with **USB debugging enabled** and accept the
    on-phone RSA prompt (turns `unauthorized` → `device`).
  - `unauthorized` → accept the "Allow USB debugging" dialog on the phone.
- **Who fixes:** **[BRANDON]** for a physical phone (USB debugging, cable, on-device prompt);
  **[EITHER]** for an emulator if an AVD already exists.

### 4.4 Can actually get a build onto a phone (install path)  — REQUIRED to reach dogfood
- **Check (local install path):** confirm the command exists — `flutter install --help` /
  `adb install --help` (do not run a full build in this gate).
- **Check (tester pipeline path):** the ship runbook + ship script are present:
  `ls scripts/stocktrack_ship.sh` (or the project's ship script). Actual shipping is gated by
  the Firebase checklist (section 5) — this item only proves an install route EXISTS.
- **Expected:** either `adb install -r <apk>` to a connected device works, **or** the App
  Distribution ship pipeline is present and ready to configure. At least one route must exist.
- **If this fails:** no local device AND no ship pipeline configured → you cannot dogfood.
  Establish the emulator/device (4.3) or complete the Firebase App Distribution setup
  (section 5 + the ship runbook).
- **Who fixes:** **[EITHER]** to prove the local path; App Distribution requires **[BRANDON]**
  console setup (section 5).

---

## 5. Cloud access (Firebase / Google Cloud)

> Only REQUIRED once the app talks to live cloud data / ships via App Distribution. If the
> current slice is fully mocked/local, mark these **N/A for this slice** — but say so
> explicitly (that is an honest state, not a silent skip).

### 5.1 Firebase CLI is usable  — REQUIRED for shipping / rules deploy
- **Check:** `firebase --version`
  **Note:** on some WSL setups the **WSL** `firebase` binary hangs (no output, exit 124). If
  so, use the **Windows** CLI: `powershell.exe -Command "firebase --version"`.
- **Expected:** a version number prints promptly (WSL or the Windows CLI).
- **If this fails / hangs:** install via `npm install -g firebase-tools` (Windows side if the
  WSL binary hangs). Then `firebase login` (interactive, the account that owns/can access the
  project).
- **Who fixes:** **[ORCH]** to install; **[BRANDON]** for the interactive `firebase login` on
  his Google account (or granting the ops account access — see 5.3).

### 5.2 Google Cloud SDK + Application Default Credentials (ADC)  — REQUIRED for server-side ops
- **Check:**
  `gcloud --version` and
  `ls -l ~/.config/gcloud/application_default_credentials.json` and
  `gcloud config get-value project`
- **Expected:** `gcloud` prints versions; the ADC file **exists** (do **not** print the token
  — its presence is the proof); the active project is `<FIREBASE_PROJECT>` (or set it with
  `gcloud config set project <FIREBASE_PROJECT>`).
- **If this fails:**
  - `gcloud: command not found` → install the Google Cloud CLI.
  - No ADC file → `gcloud auth application-default login` (interactive, `<OPS_EMAIL>`), then
    `gcloud config set project <FIREBASE_PROJECT>`.
- **Who fixes:** **[ORCH]** to install; **[BRANDON]/[ORCH]** for the interactive ADC login
  depending on whose account (`<OPS_EMAIL>`) is used.
- **⚠ Secret hygiene:** ADC/token/service-account files are secrets — **never** print them
  into this doc, a log, or a commit. Presence-check only.

### 5.3 The ops account actually has permission on the project (no missing IAM)  — REQUIRED
- **Check (non-destructive read against the real project):** run the project's own read-only
  ops command (e.g. the in-repo chat reader in read mode, or a single-doc Firestore read)
  pinned to `<FIREBASE_PROJECT>` and confirm it connects and returns **without** a
  `PERMISSION_DENIED` / `403`. Example shape: `node scripts/<read-only ops script> --read`.
- **Expected:** it connects to `<FIREBASE_PROJECT>` and reads (even "no messages" is a pass —
  that is a successful, authorized empty read). A `PERMISSION_DENIED` is a **FAIL**.
- **If this fails (`PERMISSION_DENIED`/`403`):** the ops account lacks a role on the project.
  **Brandon** must grant `<OPS_EMAIL>` the minimum role in the Firebase/Cloud console
  (typically **Cloud Datastore User** = `roles/datastore.user` for Firestore read/write).
  This is a **permission grant, not a secret** — no key file changes hands.
- **Who fixes:** **[BRANDON]** — only the project owner can grant IAM. [ORCH] can only run the
  check and report the exact denied resource.

---

## 6. Agent runtime (Claude Code)

### 6.1 Claude Code is installed  — REQUIRED
- **Check:** `claude --version`
- **Expected:** prints a version line, exit 0.
- **If this fails:** `command not found` → install (official native installer):
  `curl -fsSL https://claude.ai/install.sh | bash` — **or** Homebrew:
  `brew install --cask claude-code` — **or** a Linux package manager (see
  `code.claude.com/docs/en/setup`). Re-open the shell, re-run the check.
  Update an existing install with `claude update` (native installs also auto-update).
- **Who fixes:** **[ORCH]** (user-local install), escalate to **[BRANDON]** only for
  machine-level PATH.

### 6.2 Claude Code is authenticated and can reach the model  — REQUIRED
- **Check (auth, non-interactive):** `claude auth status --text`
  — expected: prints the login method / account / email; **exit 0** if logged in, **exit 1**
  if not.
- **Check (real smoke test, proves it can reach the model):**
  `claude -p "reply with the single word READY"` — expected: it prints `READY`. A prompt to
  log in, or an auth/credit error, is a **FAIL**.
- **If this fails:** run `claude` once interactively to complete login (Brandon's Claude
  account / subscription), or provide the API key the CLI expects. Credentials live at
  `~/.claude/.credentials.json`; config under `~/.claude/`.
- **Who fixes:** **[BRANDON]** — interactive login / account & subscription is his; [ORCH]
  can install but cannot complete Brandon's login.

### 6.3 Permission mode is set for autonomous fleet runs  — REQUIRED for orchestration
- **Why:** looping/fleet agents must run tools without a human approving every action. Confirm
  the launch uses a non-interactive permission posture on purpose (either a scoped allowlist
  in `settings.json`, or the skip-prompts flag for a trusted, isolated machine).
- **Check:** confirm how agents are launched — either a `permissions` allowlist / default mode
  is set in the project or user `settings.json`, **or** the fleet launch command passes the
  permission flag explicitly. Valid permission modes: `default` (prompts for all writes),
  `acceptEdits` (auto-approves edits + common fs commands), `plan` (read-only, propose first),
  `auto` (fewer prompts, research preview), `dontAsk` (only pre-approved tools — CI mode), and
  `bypassPermissions` (no prompts, isolated envs only). Launch flag: `--permission-mode <mode>`;
  the settings.json key is `permissions.defaultMode`. The "run without any prompts" flag is
  `--dangerously-skip-permissions` (equivalent to `bypassPermissions`).
- **Expected:** fleet/agent launches are configured so tool calls do not block on interactive
  prompts (a scoped allowlist / `dontAsk`, or the skip flag on a trusted machine), and this is
  a deliberate, documented choice — not left as an accidental default.
- **If this fails / unclear:** decide the posture with Brandon. Preferred for autonomy with a
  guardrail: a reviewed `permissions` allowlist in `settings.json` (or `dontAsk`).
  `--dangerously-skip-permissions` / `bypassPermissions` is acceptable ONLY on a trusted,
  isolated dev machine (never where it could touch other credentials).
- **Who fixes:** **[EITHER]** to set `settings.json` / launch flags; **[BRANDON]** decides the
  risk posture for his machine.

---

## 7. Separation / safety gate (shared repo)  — REQUIRED before any commit

Because this is a shared, owner-visible repo, prove no other/reference app's identity leaked
into the tooling before committing.

- **Check:** `bash harness/harness_antileak_scan.sh` (the in-repo separation scan)
- **Expected:** `ANTILEAK RESULT: PASS` (0 foreign literals), exit 0.
- **If this fails:** the scan lists `file:line: [pattern]` for each leaked identifier —
  replace each with this app's own value (from `harness/project.config.json`) and re-run.
- **Who fixes:** **[ORCH]**.

---

## 8. THE GATE — ENVIRONMENT READY / NOT READY

Fill this in from the ACTUAL command outputs above. Paste real output into the notes column —
a tick with no output behind it does not count.

| # | Item | REQUIRED? | Result (PASS / FAIL / N-A) | Command output / note |
|---|---|---|---|---|
| 2.1 | WSL2 running | yes | | |
| 2.2 | Zellij runnable | yes | | |
| 3.1 | Git installed | yes | | |
| 3.2 | GitHub auth | yes | | |
| 3.3 | Correct repo cloned | yes | | |
| 3.4 | Repo WRITE access | yes | | |
| 4.1 | Flutter healthy | yes | | |
| 4.2 | Android SDK + adb | yes | | |
| 4.3 | Device / emulator | yes | | |
| 4.4 | Install path exists | yes | | |
| 5.1 | Firebase CLI | if cloud | | |
| 5.2 | gcloud + ADC | if cloud | | |
| 5.3 | Ops IAM permission | if cloud | | |
| 6.1 | Claude Code installed | yes | | |
| 6.2 | Claude Code auth (smoke) | yes | | |
| 6.3 | Permission mode set | yes | | |
| 7 | Anti-leak PASS | yes | | |

### Verdict (pick ONE, honestly)

- ✅ **ENVIRONMENT READY** — every REQUIRED item above is **PASS** (cloud items either PASS
  or a deliberate, stated **N/A for this slice**), each backed by real command output.
  → Proceed to Firebase / dogfood.

- ⛔ **ENVIRONMENT NOT READY** — one or more REQUIRED items failed or were not run.
  → **Do NOT proceed to Firebase / dogfood.** List the blockers:
  - `Item __ FAILED: <what is missing>` → fix: `<exact command/action>` → owner: `[ORCH/BRANDON]`
  - (repeat for each blocker)

> Reminder: "mostly ready" = **NOT READY**. State the blockers plainly, route each to
> [ORCH] or [BRANDON], and only flip the verdict when they are actually green.

---

### Appendix — checks that need a value before they can run

These checks are fully specified above but need a Variables-table value (§1) filled in first,
or a project-specific artifact confirmed, before the command is runnable:

- **3.3 / 3.4** need `<REPO_SLUG>` (the exact GitHub `owner/repo`) — verify it from
  `git remote get-url origin`; do not assume it.
- **4.4 / 5.1** reference the project's **ship script** name — confirm the actual filename in
  `scripts/` for this app.
- **5.3** references the project's **read-only ops script** (e.g. the chat reader) — confirm
  its actual filename + read flag for this app; the command shape is given, the exact name is
  per-project.
- **5.1 / 5.2 / 5.3 / App Distribution** values (`<FIREBASE_PROJECT>`, `<APP_DIST_APP_ID>`,
  `<TESTER_GROUP>`, `<OPS_EMAIL>`) come from the project's Firebase setup + ship runbook.
