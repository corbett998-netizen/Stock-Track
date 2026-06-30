# Brandon's App — Owner Vision / Product Intent

> The product compass for Brandon's App. Owner-level intent, separate from task tracking. Filled from the owner's first direction (2026-06-30); refine as more direction lands. (Earlier "stock-trading" assumption was WRONG — corrected below.)

## What it is (one line)
An **HVAC / electrical equipment INVENTORY + TRACKING app** — cloud-based, mobile-first, Flutter (iOS + Android). Reference branding: "StockTrack — Warehouse." (NOT a stock-trading app.)

## Core purpose
Track HVAC/electrical/equipment stock across its lifecycle: **warehouse → installer truck → customer installation site**, with **real-time cloud updates, low-stock alerts, customer install history, and recall tracking.**

## Who it's for
Brandon (product owner/originator; HVAC/electrical trade context); Pete is coordinating the build. End users: warehouse/admin + installers in the field.

## North Star
A clean, real-time inventory + install-tracking app a trade business actually runs on — always-accurate stock from warehouse to truck to job site, with fast scanning and clear low-stock visibility.

## Core screens (from the reference visuals — see `references/JUN30_visual_direction.md`)
- **Dashboard** — metric cards (Products / Total Units / Low Stock / Installed Today) + Low Stock Alerts + Recent Installations.
- **Inventory** — list with product, barcode/SKU/serial, category, shelf/location, stock status, quantity, min-stock threshold, and edit/delete/restock actions; search + Low filter; Add.
- **Scan** — barcode scanning (stock-in / scan-out to a truck/job).
- **Installers** — people directory.
- **History** — installation history (product + installer + customer/address, grouped by date, searchable).
- Cross-cutting: low-stock alerts, recall tracking, real-time cloud sync.

## Visual direction
Dark warehouse/admin aesthetic; blue primary accent; orange = low-stock/alert; green = in-stock. Left-side nav on desktop/tablet → adapts to bottom-nav/drawer on mobile (the product is a Flutter PHONE app first; the references are a desktop admin layout conveying style + shape).

## Non-negotiable product principles (to confirm/expand with owner)
- **Stock accuracy + real-time sync** is the whole point — the data must be trustworthy and current across devices.
- Fast in-the-field scanning (installers on a truck/site).
- Clear low-stock + reorder visibility.

## Open questions for the owner (to move from references → buildable spec)
1. Backend/cloud: any preference (e.g. Firebase, matching the harness pattern) or existing infra?
2. Scanning: phone-camera barcode/QR, or dedicated scanner hardware?
3. Multi-user / roles: warehouse admin vs installer permissions? One company or multi-tenant?
4. Recall tracking — how should it work (flag a product/lot, notify, trace installs)?
5. Truck/van as a stock location (transfer warehouse→truck→site) — is that an explicit "location" in the model?
6. Customer records — how much (name/address/install history), any privacy constraints?
7. Does Brandon have any existing code/data/brand, or is this greenfield from these references?
8. Priority first slice to build (e.g. Inventory + Dashboard + Scan) and rough timeline.

## Mockups / visual references
3 reference screenshots saved in `references/screenshots/` (dashboard / inventory / installation-history), paired with context in `references/JUN30_visual_direction.md`. These are visual references, not final requirements.
