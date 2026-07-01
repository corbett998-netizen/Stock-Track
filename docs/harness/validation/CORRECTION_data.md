# CORRECTION — DATA group (durable persistence + report/logs retrieval + dogfood/queue survival)

**Scope:** Stock-Track (`/mnt/c/dev/Brandons_App`) only. No Blueprint files touched.
**Mode contract:** mock/local path now survives app restart; **Firebase-mode path unchanged**
(Firestore is already durable server-side — no store, no new awaits on that branch).

---

## What was wrong (verified against the code)

The mock/local harness path held the **entire** owner loop in memory, so every app kill reset it:

- `MockChatRepository` re-seeded 2 messages each launch; `sendMessage` only appended to a `List<ChatItem>`.
- `MockReportRepository` re-seeded `seed-report-1` + `seed-checkitem-1` each launch; every `fileReport`,
  triage transition, and dogfood **Works/Still-broken** verdict mutated an in-memory `List<Report>` only.
- Ready-to-test / dogfood state is **derived** from report fields (`awaitingVerification` etc.), so it died
  with the reports.
- `ChatItem` had no `toMap`/`fromMap`; `Report` had `fromMap` but no `toMap` — nothing was serializable.
- Screen-context ("which screen was I on") was **never captured** on a filed report in either mode, and
  never displayed on reload.

## What changed

### Durable persistence behind a generic seam
- **NEW `lib/features/dev/services/harness_local_store.dart`** — app-agnostic `HarnessLocalStore`
  interface (`loadAll` / `put` / `delete` / `clear`) mirroring the reference harness's store idiom, with
  two impls: `InMemoryHarnessLocalStore` (test/default) and `SharedPrefsHarnessLocalStore` (durable).
  `loadAll` is synchronous (cache warmed at boot) so a repo constructor can hydrate without an await.
- **`ChatItem.toMap`/`fromMap`** and **`Report.toMap`** added (round-trip is lossless; `Report.toMap`
  explicitly writes `createdAtMs` because `fromMap` does **not** read it from the map).
- **`MockChatRepository` / `MockReportRepository`** now take an optional store (defaults to in-memory so
  existing no-arg callers/tests are unchanged), **hydrate from it or seed-and-persist on an empty box**
  (re-seed gated on box-EMPTY so a cleared seed is never re-injected), and **write through** on every
  mutation. For reports the write-through sits at the two choke-points (`fileReport` and `_replace`), so
  every triage/dogfood transition — and therefore the derived ready-to-test loop — survives restart with
  no separate store.
- **`lib/main.dart`** opens a `SharedPrefsHarnessLocalStore` (namespaced from `HarnessConfig`) **only in
  mock mode** and threads it into the mock repos; the firebase branch is byte-for-byte the same trio.

### Report evidence: log-tail + build/platform + screen-context, viewable on reload
- **NEW `lib/core/utils/current_screen_tracker.dart`** — generic `CurrentScreenTracker` + a
  `HarnessRouteObserver` (named-route → tracker; unnamed routes ignored so a pushed harness tool can't
  clobber the last real screen).
- **`lib/app.dart`** wires the observer into `MaterialApp.navigatorObservers` (dev-gated).
- **`lib/core/navigation/app_shell.dart`** feeds the current tab label to the tracker (ST nav is an
  `IndexedStack` of tabs, not routes — this is the app-layer source; the harness stays generic).
- **Both `fileReport`s** now stamp the captured screen as `region` (additive field; the Firebase write is
  otherwise unchanged). A filed report keeps its log-tail + build/platform + screen-context and, on
  reload, `report_detail.dart` renders `build … · <platform> · on <screen>`.

## Gate results (this machine, 2026-07-01)

| Gate | Result |
| --- | --- |
| `bash harness/harness_antileak_scan.sh` | **PASS** — 0 Blueprint literals, 41 files |
| `flutter analyze` | **PASS** — No issues found (0) |
| `flutter test` | **PASS** — 53/53 (incl. new `test/harness_persistence_test.dart`) |
| `flutter build apk --debug` | **PASS** — built `app-debug.apk` (compiles both mock + firebase paths) |

On-device restart (mock APK) is the product-facing proof per doctrine; the unit tests simulate a restart
by hydrating a fresh repo over the same store instance (in-memory) and by a genuine re-read of the
SharedPreferences durable impl.

## Generic (reusable framework) vs Stock-Track-specific

- **Generic / app-agnostic (reusable harness framework):** `HarnessLocalStore` + both impls,
  `HarnessStoreKeys` (`harness_`-prefixed), `CurrentScreenTracker` + `HarnessRouteObserver`, the
  `toMap`/`fromMap` on the models, and the write-through/hydrate logic in the mock repos. None of these
  name a project id, collection, owner, or screen. Identity/namespacing flows in **from config**
  (`HarnessConfig.projectName` builds the store namespace in `main.dart`).
- **Stock-Track-specific (app layer, by design):** the tab→label map `['Dashboard','Inventory','Scan']`
  in `app_shell.dart` (the shell is the app-layer screen-context source), and the two demo seed records.
  These belong to the app, not the framework.

## Store-backend note (generic vs ST choice)

The reference/BP durable idiom is an untyped Hive box; the endorsed low-risk equivalent here is
`SharedPreferences` (already a dependency — no new package / no pub-get risk), storing each collection as
one JSON `{id: json}` blob. The **BP-parity value is the seam** (`HarnessLocalStore`), which is preserved
exactly; the backend is swappable behind it, so a per-record Hive box is a drop-in impl change if ever
wanted. Firebase mode never opens the store.

## Not in this slice (unchanged / deferred)
- Firebase-mode persistence architecture (Firestore stays source of truth) — untouched.
- Firebase anonymous-auth cold-start identity race, explicit Firestore offline-persistence, and the
  Still-broken "why" note capture (usability/robustness items from the dogfoodqueue study) — out of the
  DATA-survival mandate; not touched here.
