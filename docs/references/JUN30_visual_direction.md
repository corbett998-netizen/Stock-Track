# Brandon's App — Visual Direction (early references, 2026-06-30)

> Owner (Pete, for Brandon) attached 3 reference screenshots showing the intended look/layout. **These are VISUAL REFERENCES, not final requirements** — they convey style + product shape. Saved durably here (separate from Blueprint Fitness). The orchestrator inspected all 3 directly.

## Product (corrected)
**HVAC / electrical equipment INVENTORY + TRACKING app** — NOT stock-trading (the earlier working assumption was wrong; corrected by owner 2026-06-30). Reference app is branded **"StockTrack — Warehouse"**.

**Core purpose:** track HVAC/electrical/equipment stock from **warehouse → installer truck → customer installation site**, with real-time cloud updates, low-stock alerts, customer install history, and recall tracking. **Cloud-based, mobile-first, Flutter, iOS + Android.**

## The screenshots (inspected directly)
1. **`screenshots/JUN30_ref_01_dashboard.png` — Warehouse Dashboard.** "Real-time stock overview." Four metric cards across the top: **PRODUCTS** (e.g. 10, "SKUs in warehouse"), **TOTAL UNITS** (e.g. 403, "across all items"), **LOW STOCK** (e.g. 2, "need reordering" — orange-highlighted), **INSTALLED TODAY** (e.g. 0, "scan-outs today"). Below: a **Low Stock Alerts** panel (item + qty badge + min + orange level bar, "View all") and a **Recent Installations** panel (product + address + installer + date, "View all").
2. **`screenshots/JUN30_ref_02_inventory.png` — Inventory list.** "10 products," a "+ Add" button, a "Search name, barcode…" field, and a "Low" filter. Each row: product name + **In stock**(green)/**Low stock**(orange) badge; barcode/SKU + category + shelf location (e.g. "Electrical · Shelf C1"); a horizontal **stock-level bar** (blue / orange when low); **quantity + min threshold** (e.g. "35 units / min 8"); and **restock / edit / delete** action icons.
3. **`screenshots/JUN30_ref_03_installation_history.png` — Installation History.** "1 total records," a "Search product, installer, address…" field, records **grouped by date** ("SUNDAY, JUN 28"), each card: product + install **address** (pin) + **quantity** badge + timestamp + **installer** (name + avatar).

## Style cues (from the references)
- Dark warehouse/admin dashboard aesthetic; blue primary accent; **orange = low-stock/alert**; green = in-stock.
- **Left-side navigation** (desktop/tablet/admin view): **Dashboard · Inventory · Scan · Installers · History**.
- Clean metric cards; list rows with inline status + actions; persistent search/filter; "Real-time sync" footer cue.
- Note: the references are a **desktop/web admin** layout; the product is to be a **Flutter mobile app (iOS + Android)** — so this style adapts to mobile-first (the sidebar likely becomes bottom-nav/drawer on phone).

## Implied scope (from screens + owner notes — to confirm with owner)
Dashboard (metrics + low-stock + recent installs) · Inventory CRUD (add/edit/delete/restock, categories, shelf locations, min-stock thresholds, barcode/SKU/serial) · **Scan** (barcode scanning for stock-in / scan-out) · Installers (people) · Installation History (product + installer + customer/address, search/filter) · low-stock alerts · recall tracking (owner-named, not yet shown in a screenshot) · real-time cloud sync.
