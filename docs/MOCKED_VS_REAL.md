# Stock-Track — What's MOCK vs REAL (Slice 1 + Firebase-core wiring)

> Read this to know exactly what is real product, what is placeholder data, and
> what is faked — and how the Firebase "real cloud" version plugs in later.
>
> **Slice 1 was FRONTEND-FIRST: no Firebase.** As of the Firebase-core wiring
> step, **Firebase Core is now wired + connected to Brandon's own project
> (`easy-stock-track`)** — the app initializes Firebase on launch. **DATA is
> still MOCK** (the repository abstraction is untouched); the mock→Firestore
> data swap is a separate future slice (§4). So: real Firebase *connection*,
> still-mock *data*.

---

## 0. Firebase Core — WIRED / REAL connection (data still mock)

- **What's real now:** `firebase_core` is a dependency; the google-services
  Gradle plugin processes **Brandon's** `android/app/google-services.json`
  (project `easy-stock-track`, app `com.stocktrack.app`) at build time;
  `Firebase.initializeApp()` runs in `main()` (`lib/main.dart`). The debug APK
  builds clean with Firebase linked (verified: the gms plugin injects
  `project_id=easy-stock-track` into app resources; `FlutterFirebaseCorePlugin`
  is registered; firebase native libs are bundled in the APK). Android `minSdk`
  was raised 21→23 (firebase_core 4.x requirement) and NDK pinned to 27.
- **What's still MOCK:** all inventory/installation DATA (§1 below). The
  `InventoryRepository` / `InstallationRepository` seam is unchanged — the app
  still runs `MockInventoryRepository` / `MockInstallationRepository`. Firebase
  being available does NOT mean the app reads/writes Firestore yet.
- **iOS:** `GoogleService-Info.plist` is placed in `ios/Runner/` for later; iOS
  needs a Mac to build (not this step's target).
- **Never Blueprint Fitness:** every Firebase identifier here is Brandon's own
  (`easy-stock-track` / `com.stocktrack.app`); BP's project is never referenced.

---

## 1. MOCK / placeholder (fake data, in-memory, resets on app restart)

All of this comes from `MockInventoryRepository` / `MockInstallationRepository`
(`lib/data/repositories/`), seeded in `lib/data/repositories/seed_data.dart`:

- **The 10 inventory items** (240V Power Outlet, Cat6 Cable 305m, Conduit 20mm,
  HDMI 2.1 Cable, Junction Box IP66, LED Downlight 10W, Network Switch 8P,
  Wall Plate Single, RJ45 Connector, Smoke Detector) — sample data, not a real
  warehouse.
- **The Dashboard metrics** (10 products / 403 total units / 2 low stock /
  0 installed today) — these are *computed live from the mock items*, so they're
  real arithmetic over fake data.
- **The two low-stock examples** (Junction Box IP66, Wall Plate Single).
- **The one recent install** (LED Downlight 10W → Jake Morrison →
  42 Maple Drive, dated 2026-06-28).

> Anything you change in the app (scan a unit out, etc.) updates the mock data
> **live in memory** — but it is **wiped when you close/reopen the app**. There
> is no saving, no server, no other device sees it.

## 2. STUBBED / simulated (a real feature, faked for now)

- **The Scan tab camera** — there is **no real camera/barcode scanner** in this
  slice (the `mobile_scanner` package is intentionally not wired, to keep the
  first build clean). Instead:
  - a **"Simulate scan"** button picks one of the seeded items at random (stands
    in for a live decode), and
  - a **manual barcode field** lets you look up any item by its barcode/SKU.
  - Everything *after* the decode is **real**: the **Stock-in / Scan-out toggle**,
    the **quantity stepper**, the **"current → resulting quantity" preview**, the
    **installer + address fields** (scan-out), and the **Confirm** that actually
    adjusts the (mock) stock and writes a (mock) install record — all live.

## 3. REAL and final (this is the actual product, not a throwaway)

- **The UI, layout, dark theme, and colour semantics** (navy background, blue
  accent, orange = low, green = in-stock) — `lib/core/theme/`.
- **The 3 screens + bottom navigation** — Dashboard, Inventory, Scan
  (`lib/features/`, `lib/core/navigation/`).
- **All screen behaviour that doesn't need the cloud:** Inventory **search** and
  **Low filter**, the Dashboard's live metric/panel computation, the Scan
  stock-in/scan-out flow with its guardrails.
- **The architecture** — Riverpod state management and the repository
  abstraction (§4). This does **not** change when Firebase is added.

> Note: a few buttons are honest "coming in the next slice" placeholders —
> Inventory **+ Add / Edit / Delete / Restock** row actions, the Scan
> **"Add new product"** on a not-found, and the Dashboard **Recent → History**
> "View all". They show a small message rather than doing nothing.

## 4. The SWAP PATH — how the real cloud version plugs in

The whole app talks to **interfaces**, never to a data source directly:

```
UI (screens/widgets)  ─reads providers→  InventoryRepository (abstract)
                                          InstallationRepository (abstract)
                                                  ▲
                        slice 1 (now):   MockInventoryRepository      (in-memory)
                        later (cloud):   FirebaseInventoryRepository  (Firestore)
```

- The interfaces live in `lib/data/repositories/inventory_repository.dart` and
  `installation_repository.dart`.
- They are chosen in **exactly one place** — the provider override list in
  **`lib/main.dart`** (the "single repository switch"):

  ```dart
  // Slice 1 (now):
  inventoryRepositoryProvider.overrideWithValue(MockInventoryRepository()),
  // Later — swap these two lines, nothing else:
  inventoryRepositoryProvider.overrideWithValue(FirebaseInventoryRepository()),
  ```

**To go live later:** `firebase_core` is already added + `Firebase.initializeApp()`
already runs against **Brandon's own** project (done in the Firebase-core step).
The remaining data-swap work: add `cloud_firestore`, write
`FirebaseInventoryRepository implements InventoryRepository` (and the
installation one) reading/writing Brandon's Firestore, and change those two
provider-override lines in `main.dart`. Never Blueprint Fitness's project.

**The screens, widgets, theme, and navigation do NOT change** when Firebase is
plugged in — they only ever see the interface. That is the entire point of the
repository abstraction: the cloud is a one-file swap, not a rewrite.
