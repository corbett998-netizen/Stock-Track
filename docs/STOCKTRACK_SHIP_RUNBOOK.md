# Stock-Track — Ship Runbook (Firebase App Distribution)

> How a Stock-Track APK gets to testers' phones through a PROPER pipeline (not a
> chat file-download). Pinned hard to **Brandon's own** Firebase project
> `easy-stock-track` + app `com.stocktrack.app`. It never touches Blueprint
> Fitness's project, token, or tester group. Script: `scripts/stocktrack_ship.sh`.

## One command (once the blockers below are cleared)
```bash
cd /mnt/c/dev/Brandons_App
./scripts/stocktrack_ship.sh            # debug-signed build to stocktrack-testers
./scripts/stocktrack_ship.sh --release  # later, once a Stock-Track keystore is wired
```
It prints ONE line:
- `STOCKTRACK SHIP RESULT: PASS 1.0(N) | <MB>MB | uploaded NEW` — build is live in App Distribution.
- `STOCKTRACK SHIP RESULT: BLOCKED | class=auth | …` — a Brandon prerequisite is missing (below).
- `STOCKTRACK SHIP RESULT: FAIL | class=build | …` — the build broke (fix the code).

## Pinned identity (never Blueprint Fitness)
| Field | Value |
|---|---|
| Firebase project | `easy-stock-track` |
| Android app id (`--app`) | `1:367897871594:android:08253408e00517c6548393` |
| Tester group (`--groups`) | `stocktrack-testers` |
| firebase CLI | the **Windows** CLI via `powershell.exe` (the WSL `firebase` binary hangs here, exit 124) |

The script has a defensive guard: if any `blueprint` / `677287134512` / `io.bcd`
identifier ever appears in its pinned config it aborts with `class=separation`.

## ⛔ CURRENT STATUS: BLOCKED-on-Brandon (3 things)
The only Firebase auth on this machine is Pete's Google account
(`peter.holmes.mitra@gmail.com`). Verified read-only: it can see **only**
`blueprintfitnesssubscriptions` (BP's project) — it has **no access** to
`easy-stock-track`. So the upload cannot run yet. To unblock, **Brandon** must:

1. **Enable App Distribution** — Firebase console (project `easy-stock-track`) →
   *Release & Monitor → App Distribution → Get started*. (Setup guide Part 4.)
2. **Create the tester group** — *Testers & Groups* tab → new group named exactly
   `stocktrack-testers` → add Brandon's email **and** `peter.holmes.mitra@gmail.com`.
3. **Grant an uploader access to `easy-stock-track`**, ONE of:
   - **(a)** Brandon adds `peter.holmes.mitra@gmail.com` as a **Firebase App
     Distribution Admin** (or Editor) on the project — then the script runs as-is
     from this machine; **or**
   - **(b)** Brandon runs the ship from his own machine after `firebase login`
     with his own Google account (he owns the project); **or**
   - **(c)** Brandon provides a **CI token scoped to `easy-stock-track`**
     (`firebase login:ci` on his account) — set it and the CLI can upload
     non-interactively. **Never** use BP's token.

Once 1–3 are done, `./scripts/stocktrack_ship.sh` should print a `PASS` line and
the build appears in Brandon's App Distribution console; testers get an install
invite. This **retires the chat file-download** transport (distribution plan §4).

## Notes
- **Debug-signed is fine** for internal testers. A release-signed/external build
  needs a **Stock-Track** keystore (Brandon's own, generated deliberately, backed
  up off-machine, **never committed**) — see the distribution plan §3/§5.
- **Versioning:** the script keeps Stock-Track's OWN monotonic versionCode counter
  (`scripts/.stocktrack_versioncode`, seeded from `pubspec.yaml`), independent of
  BP's build numbers. Each successful ship bumps it +1 so a tester's phone never
  gets a downgrade.
- **Build runs in WSL** (`flutter build apk`), the upload goes through the Windows
  firebase CLI. That split is intentional (the WSL firebase binary hangs here).
