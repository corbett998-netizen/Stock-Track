# Stock-Track — Flutter Shell PLAN

> **Status: PLAN ONLY — NO product code.** This document specifies the Flutter app shell (project
> structure, dependencies, navigation, screen scaffolds, Firebase-wiring approach, Riverpod state
> plan, and the gated build sequence) so the build can start the moment the gates clear. It writes
> **zero Dart**, runs **no `flutter create`**, authors **no `pubspec.yaml`**, and adds **no cloud
> config**. It is the bridge between the approved MVP spec and the first line of shell code.
>
> **Source-of-truth read for this plan:** `docs/working/JUN30_stocktrack_MVP_architecture_SPEC.md`
> (owner-approved; all 9 calls C1–C9 confirmed), `docs/OWNER_VISION.md`,
> `docs/references/JUN30_visual_direction.md`, and the 3 reference screenshots in
> `docs/references/screenshots/` (all inspected directly for this plan).
>
> **Separation guardrail (load-bearing):** Stock-Track is a **SEPARATE project** from Blueprint
> Fitness. Nothing here shares Blueprint Fitness's repo, Firebase project, secrets, config files, or
> agents. Every "Firebase" reference below means **Brandon's OWN Firebase project** (his Google
> account, his project id, his config files) — see §5, the hard gate.
>
> Date: 2026-06-30. Author lane: Stock-Track (Brandon's App) sub-orchestrator.

---

## 0. Approved decisions this plan builds on (from the MVP spec, owner-confirmed)

| Call | Decision (locked) | What the shell does about it |
|---|---|---|
| C1 | Backend = **Firebase (Firestore + Auth), Brandon's OWN project** | Shell wires `firebase_core` + points only at Brandon's generated config (§5). |
| C2 | Scanning = **phone camera** (`mobile_scanner`) | Scan tab hosts a camera-view scaffold (§4). |
| C3 | First slice = **Inventory + Dashboard + Scan** | Shell ships exactly these 3 tabs; Installers/History reserved for slice 2 (§3). |
| C4 | **Single company** for MVP | `companyId` reserved in models; no tenant switcher in shell. |
| C5 | **Single-role** now, `role` reserved | No role-gating in shell nav; field exists in the `users` model. |
| C6 | Recalls = flag → trace `installations` → affected-list | Slice-2; not in the shell nav. |
| C7 | **Truck implicit** (scan-out leaves warehouse) | Scan-out scaffold is a single decrement+record action; no truck picker. |
| C8 | Customer = **free-text address first** | Scan-out confirm scaffold carries a free-text address field. |
| C9 | **Greenfield** | Plan assumes `flutter create` from scratch; nothing to import. |

This plan scopes **slice 1 only** (Dashboard / Inventory / Scan). Slice-2 surfaces (Installers,
History, Customers, Recalls) are noted where the structure must leave room for them, but are **not**
scaffolded here.

---

## 1. Project structure (`lib/` layout — feature-first)

Mirrors the Blueprint-Fitness feature-first discipline (`lib/features/**` for UI, a shared `core/`,
and a `data/` layer for models + repositories), but is its own clean greenfield tree. Folders are
created as each gated step needs them — slice-1 folders are marked **[S1]**, reserved slice-2 folders
are marked **[S2-reserved]** (created empty/with a `.gitkeep` so the structure is visible but no
slice-2 code is written yet).

```
stock_track/                      ← repo root (Flutter app; created by `flutter create` at Gate-build-1)
├── lib/
│   ├── main.dart                 [S1]  app entry: Firebase init (Brandon's project) + ProviderScope + root app
│   ├── app.dart                  [S1]  MaterialApp.router/theme wiring + the bottom-nav shell host
│   │
│   ├── core/                     [S1]  cross-feature, no business logic
│   │   ├── theme/
│   │   │   ├── app_colors.dart           dark-warehouse palette (navy / blue / orange / green) — §3
│   │   │   ├── app_theme.dart            ThemeData (dark), text styles, card + badge styles
│   │   │   └── app_spacing.dart          spacing / radius / elevation tokens
│   │   ├── navigation/
│   │   │   ├── app_shell.dart            bottom-nav Scaffold host (Dashboard · Inventory · Scan)
│   │   │   └── app_routes.dart           route names / tab index enum (room for History/Installers)
│   │   ├── widgets/                      shared dumb widgets
│   │   │   ├── metric_card.dart          dashboard stat card shell
│   │   │   ├── status_badge.dart         In-stock(green) / Low(orange) pill
│   │   │   ├── stock_level_bar.dart      horizontal qty/min bar (blue / orange-when-low)
│   │   │   ├── section_panel.dart        titled panel w/ "View all →" header (dashboard panels)
│   │   │   └── empty_state.dart          explicit empty-state widget (no blank lists)
│   │   ├── utils/
│   │   │   ├── stock_status.dart         pure fn: quantity + minStock → inStock|low|out (single source)
│   │   │   └── formatters.dart           qty/unit, date-group, "Installed Today" helpers
│   │   └── constants.dart                collection names, default unit, etc.
│   │
│   ├── data/
│   │   ├── models/               [S1 for slice-1 entities]
│   │   │   ├── product.dart              §2.1 — name/barcode/sku/serial/categoryId/locationId/
│   │   │   │                              quantity/unit/minStock/stockStatus/recallFlag/timestamps
│   │   │   ├── category.dart             §2.2
│   │   │   ├── location.dart             §2.3
│   │   │   ├── installation.dart         §2.5 — written by scan-out; drives Dashboard "today"/"recent"
│   │   │   ├── installer.dart   [S2-reserved] §2.4 (model can exist early; no screen in S1)
│   │   │   ├── customer.dart    [S2-reserved] §2.7
│   │   │   ├── recall.dart      [S2-reserved] §2.8
│   │   │   └── app_user.dart             §2.9 — uid/displayName/role/companyId (role+companyId reserved)
│   │   ├── repositories/         [S1]  the ONLY layer that talks to Firestore
│   │   │   ├── firestore_refs.dart       typed collection references (Brandon's project)
│   │   │   ├── product_repository.dart   CRUD + restock + stream(products)
│   │   │   ├── category_repository.dart  stream(categories) (+ optional seed)
│   │   │   ├── location_repository.dart  stream(locations)
│   │   │   ├── installation_repository.dart  add(record) + stream(installations) + today/recent queries
│   │   │   └── auth_repository.dart      Firebase Auth sign-in/out + current user
│   │   └── providers/            [S1]  Riverpod wiring (repos + streams) — §6
│   │       ├── repository_providers.dart    repo singletons
│   │       └── stream_providers.dart        StreamProviders per collection (§6 table)
│   │
│   └── features/                 feature-first UI (each feature owns its screen + widgets + local providers)
│       ├── dashboard/            [S1]
│       │   ├── dashboard_screen.dart          4 metric cards + Low-Stock panel + Recent-Installs panel
│       │   ├── providers/                      derived providers (counts, total units, today, low list)
│       │   └── widgets/                        metric grid, low-stock list tile, recent-install tile
│       ├── inventory/            [S1]
│       │   ├── inventory_screen.dart          list + search + Low filter
│       │   ├── product_form_screen.dart       add/edit (modal or pushed) — incl. "scan to fill barcode"
│       │   ├── providers/                      search-text + low-filter + filtered-list providers
│       │   └── widgets/                        product_row, restock_sheet, delete_confirm
│       ├── scan/                 [S1]
│       │   ├── scan_screen.dart               camera view + reticle + mode toggle
│       │   ├── scan_result_sheet.dart         found→stock-in/scan-out confirm (resulting-qty preview)
│       │   ├── providers/                      scan-mode + decoded-code + product-lookup providers
│       │   └── widgets/                        mode_toggle, qty_stepper, not_found_add_cta
│       ├── installers/   [S2-reserved]
│       ├── history/      [S2-reserved]
│       └── auth/                 [S1]  sign-in scaffold (single company) + auth-gate wrapper
│           ├── sign_in_screen.dart
│           └── auth_gate.dart                 routes signed-out → sign-in, signed-in → app shell
│
├── test/                         widget/unit test scaffolds (pure helpers like stock_status first)
├── android/ ios/                 platform folders (Brandon's google-services.json / plist land here — §5)
├── firebase_options.dart         ← GENERATED by Brandon's `flutterfire configure` (NOT committed secrets) — §5
├── pubspec.yaml                  ← authored at build time, not in this plan (deps listed in §2)
└── README.md
```

**Discipline notes (carried from Blueprint Fitness, adapted):**
- **One state idiom = Riverpod.** No raw `ChangeNotifier`, no legacy `provider` package, no `setState`
  for shared state. `setState` only for trivially-local widget state (e.g. a text-field focus).
- **Firestore access lives ONLY in `data/repositories/`.** Features read providers, never call
  Firestore directly. This keeps the cloud boundary in one place (and makes the no-cloud dev mode in
  §5 a single swap).
- **Models are dumb + immutable** with `fromFirestore` / `toMap`. Denormalized snapshot fields
  (`productName`, `installerName` on `installation`) are part of the model per spec §2.5.
- **Don't pile into large files** — extract widgets into each feature's `widgets/` early.

---

## 2. Dependencies (pubspec plan — versions confirmed at build time)

> Authored into `pubspec.yaml` at the build step, **not** in this plan. Versions are pinned at build
> time to the latest compatible stable set (Firebase/Flutter move fast — pinning now would be stale).
> This is the intended dependency set and the reason for each.

**Runtime dependencies**

| Package | Purpose | Notes |
|---|---|---|
| `flutter` (sdk) | framework | — |
| `flutter_riverpod` | state management (the single idiom) | providers + `ProviderScope` at root |
| `firebase_core` | Firebase init | `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` — §5 |
| `cloud_firestore` | Firestore DB + real-time snapshot listeners | the live-stock backbone (§6) |
| `firebase_auth` | sign-in (single company) | email/password or Google — owner pick at build |
| `mobile_scanner` | phone-camera barcode/QR (C2) | powers the Scan tab; needs camera permission |
| `intl` | date/number formatting | History date-grouping + "Installed Today" |

**Optional / slice-2-or-later (named now so the structure anticipates them, NOT added in slice 1)**

| Package | Purpose | When |
|---|---|---|
| `firebase_storage` | product photos / installer avatars | when images are added (spec §4.2) |
| `cloud_functions` | server-side `stockStatus` recompute / recall fan-out | post-MVP (spec §4.2/§4.5) |
| `go_router` | declarative routing if nav outgrows simple bottom-nav | optional — slice 1 can use a plain `IndexedStack` + `NavigationBar` |
| `uuid` | client-side doc ids if needed | optional (Firestore auto-ids by default) |

**Dev dependencies**

| Package | Purpose |
|---|---|
| `flutter_test` (sdk) | widget/unit tests |
| `flutter_lints` | lint rules (analysis_options) |
| `mockito` or `mocktail` | mock repositories for provider/unit tests |
| `build_runner` (+ `riverpod_generator`/`freezed` if adopted) | optional codegen for providers/models — decide at build (not required for slice 1) |

**Platform config the deps imply (handled at build, flagged here):**
- `mobile_scanner` → camera permission strings: `NSCameraUsageDescription` (iOS `Info.plist`) +
  `<uses-permission android:name="android.permission.CAMERA"/>` (Android manifest).
- Firebase → minimum SDK/Gradle bumps + the `google-services` Gradle plugin (Android) and the Firebase
  pods (iOS) — all generated/required by `flutterfire configure` against **Brandon's** project (§5).

---

## 3. Navigation / shell + theme

### 3.1 Shell (phone-first)
- **Primary nav = bottom `NavigationBar`** with **3 destinations for slice 1**: **Dashboard ·
  Inventory · Scan**. (The references are a desktop left-sidebar; per spec §3.6 that collapses to
  bottom-nav on phone.)
- **Scan is the emphasis action** — center slot of the bottom-nav (or a center FAB), since the camera
  is the field tool. Confirmed by spec §3.6.
- **Tablet/landscape (post-MVP nicety):** the same destinations can render as a `NavigationRail`
  (left sidebar, matching the references). Not required for slice 1 — the shell is built phone-first;
  the rail is a responsive add-on later.
- **Slice-2 destinations (History, Installers) are reserved**, not shown. The route enum and shell
  leave a clean insertion point so adding them later is additive (don't-revert: keep the 3-tab shell
  for slice 1; do not pre-wire dead tabs).
- **State preservation:** tabs hosted in an `IndexedStack` so each tab keeps its scroll/stream state
  when switching (Firestore listeners stay warm).
- **Footer cue:** "v1.0 · Real-time sync" line (as in all 3 references) shown in the shell chrome.
- **Auth gate** wraps the shell: signed-out → `sign_in_screen`; signed-in → bottom-nav shell.

### 3.2 Theme (dark warehouse-admin — grounded in the inspected screenshots)
The references are a dark navy admin dashboard. Palette (final hex tuned against the screenshots at
build; these are the inspected intents):

| Token | Role | Approx. from refs |
|---|---|---|
| `bgDark` | app background (deep navy) | very dark navy `#0A0E17`-ish |
| `surface` | card / panel background | slightly lifted navy `#111827`-ish |
| `surfaceBorder` | card hairline border | low-contrast slate |
| `primaryBlue` | **brand accent** — active nav, links ("View all →"), normal stock bar, ×qty badge | `#3B82F6`-ish |
| `lowOrange` | **low-stock / alert** — Low badge, low stock bar, LOW STOCK card highlight border | amber/orange `#F59E0B`-ish |
| `inStockGreen` | **in-stock** badge | green `#22C55E`-ish |
| `textPrimary` | headings / values | near-white |
| `textSecondary` | sub-labels ("SKUs in warehouse", min, captions) | muted slate `#94A3B8`-ish |

- **Single dark `ThemeData`** (no light theme for MVP — the product is dark by design).
- Reusable styled primitives live in `core/widgets/` (`status_badge`, `stock_level_bar`,
  `metric_card`, `section_panel`) so every screen renders the palette consistently and the
  green/orange/blue semantics are defined once.
- **Semantic colour rule (single source):** in-stock→green, low→orange, normal-bar/accent→blue. The
  `stock_status.dart` pure fn decides the status; the badge/bar widgets map status→colour. No screen
  hardcodes a colour decision.

---

## 4. Screen scaffolds (slice 1 — UI skeletons ONLY, no business logic)

> Each is a **skeleton**: layout + placeholder widgets + where live data *will* bind. No Firestore
> calls, no writes, no real computation in this phase — those land in the gated CRUD/Dashboard/Scan
> steps (§7). Empty/placeholder states are explicit (never a blank screen).

### 4.1 Dashboard (`dashboard_screen.dart`) — ref_01
- Header: **"Warehouse Dashboard"** / "Real-time stock overview."
- **4 metric cards** in a **2×2 grid on phone** (single row on tablet), each a `metric_card`:
  - **PRODUCTS** — count of SKUs (placeholder "—").
  - **TOTAL UNITS** — sum of `quantity` (placeholder "—").
  - **LOW STOCK** — count where status==low — **orange-highlighted card** (matches the orange-bordered
    card in ref_01).
  - **INSTALLED TODAY** — count of today's `installations` (placeholder "—").
- **Low Stock Alerts panel** (`section_panel` + list of `low_stock_tile`): item name + qty badge
  ("2 units") + "min N" + **orange `stock_level_bar`**. Header "View all →" (placeholder route →
  Inventory pre-filtered Low). Placeholder rows in scaffold.
- **Recent Installations panel** (`section_panel` + `recent_install_tile`): product + address +
  installer + date. "View all →" (placeholder route → History, slice 2). Placeholder rows.
- All metric values + panels show a **loading/empty placeholder** in the scaffold; live binding is the
  Dashboard gated step.

### 4.2 Inventory (`inventory_screen.dart`) — ref_02
- Header: **"Inventory"** / "{n} products" + a **"+ Add"** button (top-right, blue) → opens
  `product_form_screen` (scaffold only).
- **Search field** ("Search name, barcode…") — wired to a local search-text provider (filters in a
  later step; in scaffold it's an inert `TextField`).
- **"Low" filter chip** (top-right, with the alert glyph) — toggles a local low-filter provider.
- **Product rows** (`product_row`), each a skeleton showing:
  - Name + **`status_badge`** (green In stock / orange Low stock).
  - Secondary line: barcode/SKU · category · shelf ("Electrical · Shelf C1").
  - **`stock_level_bar`** (blue normally, orange when low).
  - **Qty + min** on the right ("35 units / min 8"), unit-aware ("rolls"/"lengths").
  - **Row actions:** restock (↻), edit (✎), delete (🗑) — icons present, wired to no-op/placeholder
    handlers in the scaffold (`restock_sheet`, `product_form_screen`, `delete_confirm` open but do
    nothing yet).
- **Add / Edit form** (`product_form_screen`, modal or pushed): fields for name, barcode (+ a **"scan
  to fill"** affordance that will reuse the Scan camera), sku, serial, category picker, location/shelf
  picker, quantity, unit, minStock, optional photo. Scaffold = the form layout with disabled/no-op
  submit.
- **Restock sheet** (`restock_sheet`): a "+N units" stepper skeleton; no write yet.

### 4.3 Scan (`scan_screen.dart`) — camera (C2)
- **Full-screen camera view** with a scan reticle (`mobile_scanner` preview). In scaffold/dev mode the
  camera may be a placeholder panel if no camera/permission (so the UI previews without a device).
- **Mode toggle (prominent, hard-to-mistake):** **Stock-in** ⇄ **Scan-out / Install** — a segmented
  control at top. This is load-bearing (wrong direction corrupts stock, spec §3.3/§7) so the toggle is
  explicit and persistent on screen.
- **On a decode (later step):** look up `products` by `barcode` →
  - **Found** → `scan_result_sheet`: shows the product, the chosen mode, a **qty stepper (default 1)**,
    the **resulting new quantity preview** ("47 → 46"), and for scan-out a **free-text installer name +
    site address** (C8). Confirm → write (CRUD step), not in scaffold.
  - **Not found** → `not_found_add_cta`: "Add new product" prefilled with the scanned barcode → routes
    to `product_form_screen`.
- Scaffold = camera/placeholder view + mode toggle + a stub result sheet with the resulting-qty
  preview layout; **no lookups, no writes**.

> **Auth sign-in (`sign_in_screen`)** is also a slice-1 scaffold: single-company email/password (or
> Google) form, no role selection (C5). The `auth_gate` decides shell-vs-sign-in.

---

## 5. Firebase wiring approach — **CRITICAL: Brandon's OWN project only**

> This is the hard gate. The shell can be **built and previewed** before Firebase exists (dev mode,
> below), but it **cannot do a real cloud build / functional APK against live data until Brandon's own
> Firebase config is in place.**

### 5.1 How it connects (the exact mechanism)
1. **Brandon creates his OWN Firebase project** in **his** Google account (his billing, his project
   id) — Firestore + Auth enabled. This is **not** Blueprint Fitness's project and never touches it.
2. **Brandon (or the build step, on Brandon's machine/account) runs `flutterfire configure`** against
   **his** project. That command generates, from **Brandon's** project:
   - `lib/firebase_options.dart` (the `DefaultFirebaseOptions` for each platform),
   - `android/app/google-services.json`,
   - `ios/Runner/GoogleService-Info.plist`.
3. **`main.dart` calls** `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` at
   startup (before `runApp`), then wraps the app in a `ProviderScope`.
4. **Firestore offline persistence is enabled** at init (spec §4.6) so field scan-outs queue offline
   and sync on reconnect.
5. **Security rules + indexes** live in **Brandon's** project (scoped to his single company, C4) —
   authored/deployed as the CRUD step lands.

### 5.2 ⚠️ The config files come from BRANDON'S project — NEVER Blueprint Fitness's
- `firebase_options.dart`, `google-services.json`, and `GoogleService-Info.plist` are **per-project
  secrets-ish config**. They MUST be generated from **Brandon's** Firebase project. Copying Blueprint
  Fitness's (or any other project's) config in would point the app at the wrong backend — a
  data/billing/blast-radius cross-contamination. **Do not** reference, copy, or adapt Blueprint
  Fitness's Firebase config in any form.
- Because the app's single Firestore boundary is `data/repositories/` (§1), there is exactly **one**
  place the project is wired — the config object — making this easy to keep clean and auditable.

### 5.3 The hard gate (state plainly)
**No real cloud build / functional APK is possible until Brandon's Firebase config files exist in the
project.** A build attempted without `firebase_options.dart` will fail at `Firebase.initializeApp`.
This gate is owned by Brandon (create project + run `flutterfire configure`) and is **Gate 1** in §7.

### 5.4 No-cloud dev mode (so the UI shell previews before Firebase exists) — recommended
To let the shell + theme + screen scaffolds be reviewed **before** Brandon's Firebase is ready:
- Provide a **dev/offline run mode** that **skips `Firebase.initializeApp`** and feeds the UI from
  **in-memory fake repositories** (the repository interfaces in `data/repositories/` have a fake impl
  returning seeded sample products/installations — e.g. the very rows shown in the references). A
  build-time flag (`--dart-define=USE_FAKE_DATA=true`) or a compile-time `bool kUseFakeData` selects
  fake-vs-Firestore repos via the repository providers (§6).
- This previews **Dashboard / Inventory / Scan layout, theme, and navigation** with realistic data and
  **zero cloud dependency** — useful for an early look-and-feel sign-off without waiting on the gate.
- It is a **preview tool only**: it proves nothing about real sync. The functional proof (real
  scan-out → live decrement) still requires Brandon's Firebase and an on-device APK (§7 final gate).

---

## 6. Riverpod state plan (providers per collection — planned, not coded)

> All providers are **planned signatures**, not code. Firestore stream providers expose live
> snapshots; the repository providers behind them are swappable for the §5.4 fake impls. Last layer of
> derived providers computes the Dashboard numbers and the filtered Inventory list.

### 6.1 Repository providers (the cloud boundary)
| Provider (planned) | Exposes | Source |
|---|---|---|
| `productRepositoryProvider` | `ProductRepository` (CRUD + restock + stream) | real Firestore impl, or fake (§5.4) |
| `categoryRepositoryProvider` | `CategoryRepository` | Firestore / fake |
| `locationRepositoryProvider` | `LocationRepository` | Firestore / fake |
| `installationRepositoryProvider` | `InstallationRepository` (add + stream + today/recent) | Firestore / fake |
| `authRepositoryProvider` | `AuthRepository` (sign-in/out, current user) | Firebase Auth / fake |

The real-vs-fake selection happens **here** (one switch), driven by the `kUseFakeData` / dart-define
from §5.4 — so the entire UI + every downstream provider is identical in dev and cloud modes.

### 6.2 Firestore stream providers (the real-time backbone — spec §2.10 / §4.5)
| Provider (planned) | Type | Streams | Drives |
|---|---|---|---|
| `productsStreamProvider` | `StreamProvider<List<Product>>` | `products` snapshots **(rt)** | Inventory list, Dashboard counts/units/low |
| `categoriesStreamProvider` | `StreamProvider<List<Category>>` | `categories` (slow lookup) | category pickers/labels |
| `locationsStreamProvider` | `StreamProvider<List<Location>>` | `locations` (slow lookup) | shelf pickers/labels |
| `installationsStreamProvider` | `StreamProvider<List<Installation>>` | `installations` snapshots **(rt)** | Dashboard "today"/"recent", History (S2) |
| `installersStreamProvider` *(S2-reserved)* | `StreamProvider<List<Installer>>` | `installers` | Installers (slice 2) |
| `authStateProvider` | `StreamProvider<AppUser?>` | Firebase Auth state | `auth_gate` shell-vs-sign-in |

`products` and `installations` are the **load-bearing real-time listeners** (spec §2.10). The lookup
collections (`categories`, `locations`) sync live too but aren't latency-critical.

### 6.3 Derived / UI-state providers (computed, no I/O)
| Provider (planned) | Type | Derives from | Purpose |
|---|---|---|---|
| `productCountProvider` | `Provider<int>` | `productsStreamProvider` | Dashboard PRODUCTS card |
| `totalUnitsProvider` | `Provider<int>` | products | Dashboard TOTAL UNITS card |
| `lowStockProductsProvider` | `Provider<List<Product>>` | products (status==low) | LOW STOCK card + Low-Stock-Alerts panel + Low filter |
| `installedTodayCountProvider` | `Provider<int>` | installations (installedAt today) | Dashboard INSTALLED TODAY card |
| `recentInstallationsProvider` | `Provider<List<Installation>>` | installations (sorted desc, take N) | Recent-Installations panel |
| `inventorySearchProvider` | `StateProvider<String>` | UI text field | Inventory search |
| `inventoryLowFilterProvider` | `StateProvider<bool>` | UI Low chip | Inventory Low filter |
| `filteredInventoryProvider` | `Provider<List<Product>>` | products + search + low-filter | the rendered Inventory list |
| `scanModeProvider` | `StateProvider<ScanMode>` | UI mode toggle | stock-in vs scan-out (guardrail, §4.3) |
| `scannedCodeProvider` | `StateProvider<String?>` | decoded barcode | drives the lookup |
| `scannedProductLookupProvider` | `Provider<AsyncValue<Product?>>` | products + scannedCode | found→sheet / not-found→add |

### 6.4 Offline + conflict notes (carried from spec §4.6 — flagged, not solved here)
- **Offline persistence ON** (§5.1): reads serve from cache, writes queue and sync on reconnect — the
  field-scan-out path the product needs.
- **Last-write-wins risk:** two devices editing the same product's `quantity` offline can clobber on
  reconnect (spec §4.6/§7). **Acceptable for MVP** (low concurrency). The robust post-MVP fix is a
  `stockMovements` append-delta ledger instead of overwriting `quantity` — the repository layer is the
  seam where that swaps in without touching the UI. **Documented now so the design doesn't preclude
  it.**
- **`stockStatus` single source:** computed via `core/utils/stock_status.dart` on every write (client
  in MVP; a Cloud Function later) so badge / Low filter / Dashboard low-count never drift (spec §4.5).

---

## 7. Gated build sequence (each step + its gate)

> Mirrors the team's "spec → confirm → build → prove on-device" discipline. **No product code until
> the spec is approved (done). No functional/cloud APK until Brandon's Firebase exists.**

| # | Step | Gate to START | Gate to mark DONE (proof) |
|---|---|---|---|
| **G0** | **Spec approved** (this plan's premise) | — | ✅ Owner confirmed all 9 calls (spec §6 Gate 0). |
| **G1** | **Brandon's Firebase project** created (Firestore + Auth on) + `flutterfire configure` → config files in repo | G0 done | Config files present from **Brandon's** project (§5.2); a trivial init build connects. **Owner/Brandon action — hard gate before any cloud APK.** |
| **S1.0** | **Flutter shell scaffold** — `flutter create`, deps (§2), theme (§3), 3-tab bottom-nav, `core/`+`data/` skeleton, screen scaffolds (§4), auth-gate. **No-cloud dev mode (§5.4) so this is previewable BEFORE G1.** | G0 done (does **not** need G1, via dev mode) | App runs; Dashboard/Inventory/Scan render with **fake data**; theme matches refs (look-and-fee​l review). Proof = a run/screenshot, dev mode. |
| **S1.1** | **Inventory CRUD + Firestore** — `products`/`categories`/`locations` repos + real stream providers; list + search + Low filter + stock bar; add/edit/delete/restock; `stockStatus` derivation; security rules v1 | **G1 done** (real Firestore) + S1.0 | Real data round-trips: add a product → it appears live; restock bumps qty live; Low filter works. Proof = on-device against Brandon's Firestore. |
| **S1.2** | **Dashboard live** — 4 metric cards + Low-Stock-Alerts + Recent-Installations on live listeners (derived providers §6.3) | S1.1 | Metrics + panels update **live** when inventory/installs change (two-surface check). Proof = on-device. |
| **S1.3** | **Scan** — `mobile_scanner` camera; barcode lookup; stock-in (+qty) / scan-out (−qty + write `installations` w/ free-text installer+address, C8); add-new-on-miss; **offline persistence verified** | S1.2 (uses products+installs) | Scan-out decrements stock live, writes an install record, Dashboard "Installed Today"/"Recent" update; offline scan-out queues then syncs on reconnect. Proof = on-device. |
| **S1.4** | **APK on Brandon's device** — dogfood build **against Brandon's Firebase** | S1.1–S1.3 done | **End-to-end on a real phone:** add product → scan-out → stock decrements live → low-stock alert fires → Dashboard updates. **Proof = on-device, NOT a unit test.** This is the slice-1 ship gate. |
| **S2.x** | **Slice 2** — Installers, History, Customers, Recalls (spec §6 steps 6–10) | S1.4 proven on-device | per spec §6; out of this plan's scope. |

**Cross-cutting per step:** Firestore security rules (scoped to Brandon's company, C4), offline-sync
verification, and the real-time multi-device check (two devices, one updates → the other sees it
live) — all against **Brandon's** project only.

---

## 8. Don't-revert invariants (for whoever builds the shell)

- **Brandon's OWN Firebase project only.** Never wire, copy, or reference Blueprint Fitness's (or any
  other) Firebase config. Config files come from **Brandon's** `flutterfire configure`. (§5.2)
- **No functional/cloud APK before G1.** The shell may preview via the no-cloud dev mode (§5.4), but
  real-data builds wait for Brandon's Firebase. (§5.3)
- **Riverpod is the single state idiom.** No `ChangeNotifier`/legacy `provider`/shared `setState`.
- **Firestore access only in `data/repositories/`.** Features consume providers, never call Firestore.
- **3-tab shell for slice 1** (Dashboard · Inventory · Scan). History/Installers are reserved, not
  pre-wired as dead tabs.
- **Scan direction is an explicit, hard-to-mistake toggle** showing the resulting quantity before
  confirm — wrong direction corrupts stock. (§4.3, spec §7)
- **`stockStatus` has one source** (`core/utils/stock_status.dart`); colour semantics
  (green/orange/blue) are defined once in the theme + shared widgets.
- **Denormalized snapshot fields** (`productName`/`installerName` on `installation`) are intentional —
  history must survive product/installer edits (spec §2.5).
- **Slice scope:** this plan is slice 1 only. Don't build Installers/History/Recalls here.

---

## Appendix A — Reference mapping (screenshot → shell artifact)
| Reference | Shell artifact |
|---|---|
| `JUN30_ref_01_dashboard.png` | `features/dashboard/` — `metric_card` ×4 (LOW STOCK orange), `section_panel` ×2, `stock_level_bar`, `recent_install_tile` |
| `JUN30_ref_02_inventory.png` | `features/inventory/` — `product_row`, `status_badge`, `stock_level_bar`, search + Low chip, "+ Add" → `product_form_screen`, `restock_sheet` |
| `JUN30_ref_03_installation_history.png` | reserved `features/history/` (slice 2); the install-record card shape informs `installation.dart` + `recent_install_tile` |
| Sidebar (all 3) | `core/navigation/app_shell.dart` — sidebar→bottom-nav (3 tabs S1) |
| "v1.0 · Real-time sync" footer | shell chrome footer cue + the real-time stream providers (§6.2) |
| Dark navy + blue/orange/green | `core/theme/app_colors.dart` + `app_theme.dart` (§3.2) |
