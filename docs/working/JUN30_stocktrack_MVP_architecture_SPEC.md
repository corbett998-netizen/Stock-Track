# Stock-Track — MVP / Product-Architecture SPEC

> **Status: SPEC ONLY — no product code.** This document turns the owner vision + the 3 reference
> screenshots ("StockTrack — Warehouse") into a buildable MVP architecture. It is written for owner
> (Pete / Brandon) confirmation BEFORE any code. Each major technical direction is presented as a
> recommendation + the alternatives, so the owner can confirm or adjust.
>
> Source-of-truth read for this spec: `docs/OWNER_VISION.md`,
> `docs/references/JUN30_visual_direction.md`, the 3 screenshots in
> `docs/references/screenshots/` (all inspected directly), and `README.md`.
>
> **Separation guardrail:** Stock-Track is a SEPARATE project from Blueprint Fitness. Nothing here
> shares Blueprint Fitness's repo, Firebase project, secrets, or agents. Where this spec says
> "Firebase," it means **a NEW Firebase project that Brandon owns** — see §4.
>
> Date: 2026-06-30. Author lane: Stock-Track (Brandon's App) sub-orchestrator.

---

## 0. How to read this doc (point-form, for fast owner sign-off)

- **§1** = what the app does + what we build FIRST vs later (the IN/OUT line for the MVP).
- **§2** = the data model (entities + fields + how they relate).
- **§3** = the screens, adapted from the desktop references to a Flutter phone app.
- **§4** = the recommended tech stack + why (Flutter + Brandon's own Firebase + phone-camera scan).
- **§5** = the open product CALLS that need the owner's "confirm or change" — each with a recommendation.
- **§6** = the build order after approval (gated — spec sign-off before code; Brandon's Firebase before APK).

> If you only read one thing: **first build slice = Inventory + Dashboard + Scan** (the core loop),
> on **Flutter + a Firebase project Brandon creates**, with **phone-camera barcode/QR scanning**.
> Installers / History / recalls are the **next** slice. Confirm that and we can sequence the build.

---

## 1. Product summary + MVP scope

### 1.1 What Stock-Track is
A cloud-based, mobile-first (Flutter, iOS + Android) **HVAC / electrical equipment inventory +
install-tracking app** for a trade business. It keeps stock accurate in real time as equipment moves
through its lifecycle, and it records where every installed unit went.

### 1.2 The core loop (the whole point of the product)
```
   WAREHOUSE STOCK  ──scan-out──▶  INSTALLER TRUCK  ──install──▶  CUSTOMER INSTALL SITE
        ▲                                                                  │
        │                                                                  ▼
   restock / receive                                            INSTALL HISTORY RECORD
   (scan-in, +qty)                                          (product + qty + customer +
        │                                                     installer + address + time)
        │                                                                  │
   LOW-STOCK ALERT  ◀──qty drops below min threshold                       │
                                                                           ▼
                                                              RECALL SUPPORT (trace which
                                                              installs got a recalled lot/product)
```
Every movement updates a single source-of-truth quantity in the cloud, and **every device sees the
change in real time** (warehouse admin and installers in the field stay in sync). When a unit is
installed, stock decrements AND an install record is written — that same record is what makes
**low-stock alerts**, **install history**, and **recall tracing** possible.

### 1.3 Recommended FIRST build slice (the core loop)
**Slice 1 = Inventory + Dashboard + Scan.** Rationale: this is the smallest set of screens that makes
the core loop real and useful on day one —
- **Inventory** = the source of truth (you can add products and see/adjust stock).
- **Scan** = the fast field action that moves stock (stock-in / scan-out).
- **Dashboard** = the at-a-glance proof the data is live (totals + low-stock + recent activity).

With just these three, a warehouse can hold accurate, real-time stock and an installer can scan units
out. That is a shippable, dogfood-able product.

### 1.4 Next slice (after Slice 1 is proven on-device)
**Slice 2 = Installers + History + Recalls.**
- **Installers** = a people directory so install records can be attributed.
- **History** = the searchable, date-grouped install log (already partly produced by Scan-out in
  Slice 1, but gets its own browse/search screen here).
- **Recalls** = flag a product/lot and trace/notify the installs it touched.

> Note: Slice 1's "scan-out → install" already needs a *minimal* notion of installer + customer
> address to write a complete install record. Slice 1 can capture those as **free-text fields on the
> scan-out** (installer name + site address typed/picked), and Slice 2 promotes them to first-class
> **Installer** and **Customer** entities with their own screens. This keeps Slice 1 small without
> writing throwaway data (the same fields just get structured later). See §2.7.

### 1.5 IN vs OUT for the MVP (Slices 1 + 2 = the MVP)

**IN (MVP):**
- Inventory CRUD: add / edit / delete / **restock** a product; quantity, unit, min-stock threshold,
  barcode/SKU/serial, category, shelf/location, in-stock/low-stock status.
- Inventory list with search (name / barcode) + a **Low** filter + a per-item stock-level bar.
- Dashboard: 4 metric cards (Products / Total Units / Low Stock / Installed Today) + Low-Stock-Alerts
  panel + Recent-Installations panel.
- Scan: phone-camera barcode/QR → **stock-in** (receive/restock, +qty) and **scan-out** (install,
  −qty, writes an install record).
- Installers directory (Slice 2).
- Installation History: records grouped by date, searchable by product / installer / address (Slice 2).
- Recall support: flag a product (and optionally a lot/serial) + trace the installs it reached;
  surface recalled items (Slice 2).
- Real-time cloud sync across devices.
- Auth / sign-in (single company — see §5).
- Basic offline tolerance for the field (see §4.6).

**OUT (explicitly deferred — not in the MVP):**
- Multi-tenant / multiple companies (MVP = single company — §5).
- Purchase-orders / supplier management / automated reordering (low-stock *alerts* are in; *ordering*
  is out).
- Barcode label *printing* / generating new barcodes for unlabeled stock.
- Truck/van as a fully modeled stock *location* with warehouse→truck→site *transfer ledger* (MVP
  treats scan-out as the stock-leaving event; a per-truck stock balance is a post-MVP enhancement —
  §2.6 / §5).
- Customer relationship features beyond the address/name needed for an install record.
- Reporting/analytics dashboards beyond the 4 cards + 2 panels.
- Web/desktop admin build (the references are desktop-styled, but the product is phone-first; a web
  admin is a possible later target, not MVP).
- Push notifications for low-stock/recall (in-app surfacing is IN; device push is a fast-follow — §5).
- Role-based permissions beyond a basic admin-vs-installer split (and even that split is an owner
  call — §5).

---

## 2. Data model

Entities below are written as the Firestore collections we'd create. Fields marked **(rt)** are the
ones that drive **real-time sync** (a change must propagate live to all devices). IDs are
document IDs unless noted.

### 2.1 `products` (a.k.a. InventoryItem) — the source of truth
The central entity. One doc per SKU/product line.

| Field | Type | Notes |
|---|---|---|
| `id` | string (docId) | stable product id |
| `name` | string | e.g. "LED Downlight 10W" |
| `barcode` | string | scannable code (EAN/UPC/QR payload); **indexed** for scan lookup |
| `sku` | string | internal stock-keeping code (may equal barcode) |
| `serial` | string? | optional serial for serialized items (some HVAC units are serial-tracked) |
| `categoryId` | ref → `categories` | e.g. Electrical / Cabling / Lighting / AV / Networking |
| `locationId` | ref → `locations` | shelf/bin, e.g. "Shelf C1" |
| `quantity` | number **(rt)** | current on-hand units; the live stock figure |
| `unit` | string | "units" / "rolls" / "lengths" — free or small enum (see refs: rolls, lengths) |
| `minStock` | number | low-stock threshold ("min 8") |
| `stockStatus` | enum (derived) **(rt)** | `inStock` \| `low` (\| `out`) — derived from `quantity` vs `minStock`; stored denormalized for fast list/badge render + the Low filter |
| `imageUrl` | string? | optional product photo |
| `recallFlag` | bool **(rt)** | true if this product is under recall (Slice 2; see `recalls`) |
| `createdAt` / `updatedAt` | timestamp | audit |

**Stock status rule (single source):** `quantity <= 0 → out`; `0 < quantity <= minStock → low`;
else `inStock`. Computed on every write (client or a Cloud Function) so the badge, the Low filter,
and the Dashboard low-stock count all agree.

### 2.2 `categories`
| Field | Type | Notes |
|---|---|---|
| `id` | string (docId) | |
| `name` | string | Electrical, Cabling, Lighting, AV, Networking, HVAC… |
| `color` | string? | optional accent for UI grouping |

Small, mostly static lookup. (MVP could even seed a fixed list; a CRUD screen is optional/post-MVP.)

### 2.3 `locations` (Shelf / Bin)
| Field | Type | Notes |
|---|---|---|
| `id` | string (docId) | |
| `name` | string | "Shelf C1", "Shelf B2"… |
| `type` | enum | `shelf` (MVP) — reserve `truck`/`site` for the post-MVP transfer model (§2.6) |

### 2.4 `installers` (Person) — Slice 2
| Field | Type | Notes |
|---|---|---|
| `id` | string (docId) | |
| `name` | string | "Jake Morrison" |
| `initials` / `avatarUrl` | string? | the avatar bubble in the references |
| `phone` / `email` | string? | optional contact |
| `active` | bool | soft-disable instead of delete |
| `linkedUserId` | ref → `users`? | if the installer also signs in (role split — §5) |

### 2.5 `installations` (InstallRecord) — the event log **(rt)**
Written on every **scan-out / install**. This is the backbone of History, the Dashboard's
"Installed Today" + "Recent Installations," and recall tracing.

| Field | Type | Notes |
|---|---|---|
| `id` | string (docId) | |
| `productId` | ref → `products` | what was installed |
| `productName` | string | denormalized snapshot (history must survive product edits/deletes) |
| `quantity` | number | units installed ("×1") |
| `installerId` | ref → `installers`? | who installed it (free-text name in Slice 1, ref in Slice 2) |
| `installerName` | string | denormalized snapshot |
| `customerId` | ref → `customers`? | Slice 2 |
| `address` | string | install site ("42 Maple Drive, Ottawa, ON") |
| `serial` / `lot` | string? | the specific unit/lot installed — **load-bearing for recalls** |
| `installedAt` | timestamp **(rt)** | drives date-grouping + "Installed Today" |
| `createdBy` | ref → `users` | who recorded it |

> Denormalizing `productName` / `installerName` onto the record is deliberate: an install record is a
> historical fact and must stay readable even if the product or installer is later edited or removed.

### 2.6 `locations` as truck/site — POST-MVP transfer model (documented, OUT of MVP)
The vision describes warehouse → **truck** → site. The MVP keeps this simple: **scan-out decrements
warehouse stock and writes an install record** (truck is implicit — stock that's left the warehouse
but not yet install-recorded). A fuller model (per-truck stock balances + a warehouse→truck→site
transfer ledger) is a clean post-MVP extension: add `locations.type = truck`, give each product a
per-location quantity, and make scan-out a *transfer* event. Flagged here so the MVP schema doesn't
paint us into a corner — `installations` already captures the site leg.

### 2.7 `customers` — Slice 2 (Slice 1 uses free-text address)
| Field | Type | Notes |
|---|---|---|
| `id` | string (docId) | |
| `name` | string | optional in HVAC (often just a site address) |
| `address` | string | the install site |
| `phone` / `email` | string? | optional |

In Slice 1, the install record just carries `address` (+ optional installer name) as text. Slice 2
promotes repeat addresses to `customers` and links them — no Slice-1 data is wasted (the text fields
back-fill the entities).

### 2.8 `recalls` — Slice 2
| Field | Type | Notes |
|---|---|---|
| `id` | string (docId) | |
| `productId` | ref → `products` | the recalled product line |
| `lot` / `serialRange` | string? | optional narrower scope (specific lot/serials) |
| `reason` | string | why |
| `status` | enum | `open` \| `resolved` |
| `createdAt` | timestamp | |
| `notifiedInstallIds` | array<ref → `installations`>? | which installs were flagged/notified |

Recall flow: setting a recall sets `products.recallFlag = true` and **queries `installations`** for
matching `productId` (+ lot/serial if scoped) → produces the list of affected install sites to
notify. (Notification mechanism = owner call, §5.)

### 2.9 `users` — auth / role
| Field | Type | Notes |
|---|---|---|
| `id` | string (Firebase Auth UID) | |
| `displayName` | string | |
| `role` | enum | `admin` \| `installer` (role split is an owner call — §5; MVP may ship single-role) |
| `companyId` | string | single value in MVP (single-tenant — §5); present so multi-tenant is a non-breaking later add |

### 2.10 Relationship map
```
categories 1──* products *──1 locations
                  │  *
                  │  (productId, denormalized name)
                  ▼
            installations *──1 installers   (Slice 2; free-text name in Slice 1)
                  │  *
                  ├──1 customers            (Slice 2; free-text address in Slice 1)
                  │
recalls *──1 products ; recalls ──query──▶ installations (trace by productId + lot/serial)
users (auth/role) ── createdBy ──▶ installations
```

**Which entities need real-time sync:** `products.quantity` / `stockStatus` / `recallFlag` (the live
stock figure + badges), and `installations` (Dashboard "Installed Today" / "Recent Installations" +
History). `categories` / `locations` / `installers` / `customers` are slow-changing lookups — live
sync is fine but not load-bearing. Firestore listeners on `products` and `installations` are the
heart of the real-time experience (§4.5).

---

## 3. Screens (mobile-first Flutter, adapting the desktop-admin references)

> The references are a **desktop/web admin** layout with a **left sidebar** (Dashboard · Inventory ·
> Scan · Installers · History). The product is a **Flutter phone app first**, so:
> **left-sidebar on tablet/landscape → bottom-nav (Dashboard / Inventory / Scan / History) + a
> drawer or overflow for Installers/Settings on phone.** Scan is the natural center action (a phone's
> camera is the field tool) — consider a center FAB or a prominent bottom-nav Scan slot. Keep the
> dark warehouse aesthetic: blue primary accent, **orange = low/alert**, **green = in-stock**.

### 3.1 Dashboard (`ref_01_dashboard.png`)
- Header: "Warehouse Dashboard" / "Real-time stock overview."
- **4 metric cards** (on phone: 2×2 grid):
  - **PRODUCTS** — count of SKUs ("10 · SKUs in warehouse"). Source: `products` count.
  - **TOTAL UNITS** — sum of all `quantity` ("403 · across all items").
  - **LOW STOCK** — count where `stockStatus == low` ("2 · need reordering"), **orange-highlighted**.
  - **INSTALLED TODAY** — count/sum of `installations` where `installedAt` is today ("0 · scan-outs today").
- **Low Stock Alerts panel** — list of low items: name + qty badge ("2 units") + min ("min 5") + an
  **orange level bar** (qty/min fill). "View all →" routes to Inventory pre-filtered to **Low**.
- **Recent Installations panel** — recent `installations`: product + address + installer + date.
  "View all →" routes to History.
- All four metrics + both panels update **live** via Firestore listeners.

### 3.2 Inventory (`ref_02_inventory.png`)
- Header: "Inventory" / "{n} products" + a **"+ Add"** button.
- **Search field** ("Search name, barcode…") — filters by name or barcode.
- **"Low" filter toggle** — show only `stockStatus == low`.
- **Product rows**, each with:
  - Name + **status badge**: **In stock** (green) / **Low stock** (orange).
  - Secondary line: barcode/SKU · category · shelf ("Electrical · Shelf C1").
  - **Horizontal stock-level bar** (blue normally; **orange when low**) — fill = quantity vs a
    sensible max (e.g. relative to min or a reorder target).
  - **Quantity + min threshold** ("35 units / min 8"); unit label respects the item ("rolls",
    "lengths").
  - **Row actions:** **restock** (quick +qty), **edit** (full form), **delete** (with confirm).
- **Add / Edit form** (modal or pushed screen): name, barcode (with a "scan to fill" affordance →
  reuses the Scan camera), sku, serial, category (picker), location/shelf (picker), quantity, unit,
  minStock, optional photo.
- **Restock action:** lightweight "+N units" that bumps `quantity` (and may clear the low badge live).

### 3.3 Scan (camera barcode/QR)
Not shown as a screenshot, but named in the sidebar + vision; this is the field action that drives the
core loop.
- Full-screen camera view with a scan reticle; decodes barcode/QR live.
- On a successful scan, look up `products` by `barcode`:
  - **Found** → show the product + a **mode choice**: **Stock-in** (receive/restock → `quantity += n`)
    or **Scan-out / Install** (→ `quantity -= n` AND write an `installations` record with
    installer + address; in Slice 1 these are free-text/quick-pick).
  - **Not found** → offer **"Add new product"** prefilled with the scanned barcode (routes to the
    Inventory add form).
- Quantity stepper (default 1) for both modes. Confirm → write → live update everywhere.
- **Mode default & guardrails:** make stock-in vs scan-out an explicit, hard-to-mistake choice
  (wrong direction corrupts stock). Show the resulting new quantity before confirm.

### 3.4 Installers (Slice 2)
- People directory: list of installers (name + avatar/initials), search, add/edit, soft-disable.
- Tapping an installer → their recent installs (a filtered History view).

### 3.5 History (`ref_03_installation_history.png`) — Slice 2
- Header: "Installation History" / "{n} total records."
- **Search field** ("Search product, installer, address…").
- Records **grouped by date** with a date header ("SUNDAY, JUN 28 (1)").
- Each record card: product icon + name, install **address** (pin), **quantity badge** ("×1"),
  **timestamp** ("2026-06-28 · 11:06 p.m."), and **installer** (name + avatar bubble).
- Read-only log (records are created by Scan-out, not hand-edited) — possibly with a detail view.

### 3.6 Navigation summary
| Surface | Phone (primary) | Tablet/landscape |
|---|---|---|
| Primary nav | Bottom-nav: Dashboard · Inventory · **Scan** · History | Left sidebar (matches refs) |
| Secondary | Drawer/overflow: Installers · Settings · Sign-out | In sidebar |
| Scan emphasis | Center bottom-nav slot or center FAB | Sidebar item |
| Footer cue | "v1.0 · Real-time sync" (as in refs) | same |

---

## 4. Architecture / tech recommendation (for owner confirm)

### 4.1 Client — Flutter (iOS + Android) — RECOMMENDED ✅
Matches the owner vision (mobile-first, iOS + Android, one codebase). Reuses the *pattern* the team
already knows (Blueprint Fitness is Flutter) — but **separate codebase, separate repo**. Riverpod for
state management (single, modern idiom; same rationale the team adopted elsewhere). No code shared with
Blueprint Fitness.

### 4.2 Backend — Firebase, as BRANDON'S OWN project — RECOMMENDED ✅
- **Firestore** for the database: real-time listeners give the live stock sync the product is built
  around, with minimal backend code. The data model (§2) is a natural document/collection fit.
- **Firebase Auth** for sign-in (email/password or Google; single company in MVP — §5).
- **Cloud Functions (optional, later)** for server-side rules: recompute `stockStatus`, fan-out
  recall traces, send notifications. MVP can derive `stockStatus` client-side and add Functions when
  needed.
- **Firebase Storage (optional)** for product photos / installer avatars.

> **⚠️ SEPARATE FIREBASE PROJECT — load-bearing.** This is **NOT** Blueprint Fitness's Firebase
> project and must never touch it. **Brandon creates his OWN Firebase project** (his own Google
> account / billing, his own project id, his own `google-services.json` / `GoogleService-Info.plist`,
> its own Firestore, Auth, security rules). The Stock-Track app points only at Brandon's project. No
> shared keys, no shared collections, no shared service accounts. This keeps data, billing, auth, and
> blast-radius cleanly separated. (Brandon's own Firebase project is a **gate before any APK** — §6.)

### 4.3 Why Firebase over the alternatives (rationale)
- **vs Supabase/Postgres:** Supabase is a strong real-time option too, but Firestore's offline cache
  + listener model is the lowest-effort path to the exact "live stock everywhere, works on a truck"
  behavior, and the team has deep Firebase muscle memory (faster, fewer foot-guns). Supabase is the
  best *alternative* if the owner prefers SQL/relational or wants to avoid Google lock-in.
- **vs a custom Node/Postgres backend:** more control, but real-time + offline + auth would all be
  hand-built — much slower to a working MVP, more to maintain. Not worth it at this stage.
- **vs local-only (no cloud):** fails the core requirement (real-time sync across warehouse +
  installers). Non-starter.

### 4.4 Scanning — phone camera (no special hardware) — RECOMMENDED ✅
Use the device camera for barcode/QR via a Flutter scanning package (e.g. `mobile_scanner`). No
dedicated scanner gun needed — installers already carry a phone. Works for stock-in and scan-out.
A hardware scanner can be a later option if high-volume warehouse intake demands it, but it is **not**
needed for the MVP and adds cost + procurement.

### 4.5 Real-time sync model
- Inventory list + Dashboard + History subscribe to Firestore **snapshot listeners** on `products`
  and `installations`. A scan/restock/edit writes once; **all devices re-render live**.
- `stockStatus` is computed on write (client in MVP; a Cloud Function later for guaranteed
  server-side consistency) so badges, the Low filter, and the Dashboard low-stock count never drift.
- Writes are small, targeted field updates (`quantity`, plus an `installations` insert) to keep sync
  cheap and conflict-light.

### 4.6 Offline behavior (installers in the field) — consideration
Firestore's **offline persistence** is a strong fit: an installer in a basement / a job site with no
signal can still scan-out; the write is queued locally and syncs when connectivity returns, and reads
serve from the local cache. **MVP stance:** enable Firestore offline persistence and verify the
scan-out → queued-write → reconnect-sync path on-device. **Edge case to flag for the owner:** two
devices editing the same product's quantity while offline can produce a last-write-wins conflict on
reconnect — for the MVP this is acceptable (low concurrency, small team); a per-movement ledger
(append `stockMovements` deltas instead of overwriting `quantity`) is the robust post-MVP answer if
conflicts ever bite. Documented now so we don't design ourselves out of it.

### 4.7 Security / data scoping
- Firestore security rules scope all reads/writes to authenticated users of Brandon's single company
  (MVP). Rules live in Brandon's project. Multi-tenant scoping (`companyId` on every doc + rules) is a
  non-breaking later add — `companyId` is already in the schema (§2.9).

---

## 5. Open product CALLS for the owner (recommendation + options)

> Each is presented so Pete/Brandon can **confirm the recommendation or pick an alternative**. None of
> these block writing the spec; they shape the build.

| # | Decision | Recommendation | Options / notes |
|---|---|---|---|
| **C1** | **Backend / cloud** | **Firebase (Firestore + Auth), as Brandon's OWN project** ✅ | vs Supabase/Postgres (if SQL/no-lock-in preferred) vs custom Node backend (slower). Must be separate from Blueprint Fitness's Firebase. |
| **C2** | **Scanning method** | **Phone camera barcode/QR** (`mobile_scanner`) ✅ | vs dedicated scanner hardware (cost + procurement; only if high-volume intake demands it later). |
| **C3** | **First build slice** | **Inventory + Dashboard + Scan** (the core loop) ✅ | Installers + History + Recalls = Slice 2. Alt: include a minimal History in Slice 1 (scan-out already writes records). |
| **C4** | **Single-company vs multi-tenant** | **Single company for MVP** ✅ | `companyId` is in the schema so multi-tenant is a non-breaking later add. Multi-tenant now = more auth/rules complexity for no MVP value. |
| **C5** | **Installer vs admin roles** | **Start single-role (everyone can do everything), with a `role` field reserved** ✅ | If Brandon wants installers locked to scan-out only (no delete/edit), ship a basic admin-vs-installer split in Slice 2. Decide whether installers even sign in, or admin records on their behalf. |
| **C6** | **Recall mechanism** | **Flag product (+ optional lot/serial) → trace matching `installations` → in-app "affected installs" list** ✅ | Notification channel is a sub-call: in-app surfacing (MVP) vs push notification vs SMS/email to customers (needs contact data + a sending service — fast-follow). How granular is lot/serial tracking? (Depends on whether stock is serial-tracked at intake.) |
| **C7** | **Truck as a stock location** | **MVP: truck implicit (scan-out leaves the warehouse + writes an install record)** ✅ | Full warehouse→truck→site transfer ledger w/ per-truck balances = post-MVP (§2.6). Confirm the MVP simplification is acceptable. |
| **C8** | **Customer records depth** | **Slice 1: free-text address on the install record; Slice 2: promote to `customers` entity** ✅ | How much customer data does Brandon want (name/phone/email/history), and any privacy constraints? |
| **C9** | **Greenfield vs existing** | **Assume greenfield from these references** | Confirm Brandon has no existing code/data/brand to import. If he has a product list / barcodes already, we can seed `products`. |

---

## 6. Build sequencing (post-approval, gated)

> **Every step is gated. No product code is written until this spec is approved. No APK is built until
> Brandon's own Firebase project exists.** This mirrors the team's "spec → confirm → build → prove
> on-device" discipline.

**Gate 0 — Spec approval.** Owner (Pete/Brandon) confirms §1–§5 (especially the C1–C9 calls). ← we are here.

**Gate 1 — Brandon's Firebase project.** Brandon creates his OWN Firebase project (separate from
Blueprint Fitness): Firestore + Auth enabled, config files generated. Required before any cloud build
runs. (Owner/Brandon action.)

**Then, Slice 1 (gated steps):**
1. **Flutter app shell** — project scaffold, Riverpod, theme (dark + blue/orange/green), nav
   (bottom-nav on phone / sidebar on tablet), Firebase wired to *Brandon's* project. → builds/runs empty.
2. **Inventory CRUD + Firestore** — `products` / `categories` / `locations`; list + search + Low
   filter + stock bar + add/edit/delete/restock; `stockStatus` derivation. → real data, live list.
3. **Dashboard** — 4 metric cards + Low-Stock-Alerts + Recent-Installations, all on live listeners.
4. **Scan** — camera barcode/QR; lookup; stock-in / scan-out (scan-out writes an `installations`
   record with free-text installer + address); add-new-on-miss; offline-persistence enabled.
5. **APK for on-device test** — cut a dogfood build (against Brandon's Firebase) and prove the core
   loop end-to-end on a real phone: add product → scan-out → stock decrements live → low-stock alert
   fires → Dashboard updates. (Proof = on-device, not a unit test.)

**Then, Slice 2 (gated after Slice 1 is proven):**
6. **Installers** directory; promote install-record installer to a ref.
7. **History** screen (date-grouped, searchable) over `installations`.
8. **Customers** entity; promote install-record address to a ref.
9. **Recalls** — flag product/lot, trace affected installs, in-app affected-installs list (+ chosen
   notification channel per C6).
10. **APK** — on-device proof of Slice 2.

**Cross-cutting (as each slice lands):** Firestore security rules (scoped to Brandon's company),
offline-sync verification, and the real-time multi-device check (two devices, one updates → the other
sees it live).

---

## 7. Open risks / things to watch (facts vs to-confirm)

- **(to-confirm)** Whether HVAC stock is **serial-tracked at intake** materially affects recall
  granularity (per-unit vs per-product). C6 + the `serial`/`lot` fields depend on this.
- **(risk)** Offline concurrent edits → last-write-wins on `quantity` (§4.6). Acceptable for MVP; the
  `stockMovements` ledger is the robust answer if it bites.
- **(risk)** Scan-direction mistakes (stock-in vs scan-out) corrupt stock — the Scan UI must make the
  mode explicit and show the resulting quantity before confirm (§3.3).
- **(fact)** The references are a desktop admin layout; the product is phone-first — every screen here
  is specified for the phone adaptation, not a 1:1 copy of the screenshots.
- **(fact)** This spec writes NO code and touches NO Blueprint Fitness internals or Firebase project.

---

## Appendix A — Reference mapping (screenshot → spec)
| Reference | Drives |
|---|---|
| `JUN30_ref_01_dashboard.png` | §3.1 Dashboard (4 cards + Low-Stock-Alerts + Recent-Installations) |
| `JUN30_ref_02_inventory.png` | §3.2 Inventory (rows, badges, stock bar, qty/min, actions, search, Low filter, Add) |
| `JUN30_ref_03_installation_history.png` | §3.5 History (date-grouped, search, address/qty/time/installer) |
| Sidebar (all 3) | §3.6 Navigation (sidebar → bottom-nav/drawer) |
| "v1.0 · Real-time sync" footer | §4.5 real-time sync model |
