import '../models/installation.dart';
import '../models/product.dart';

/// Seed inventory for the MOCK repository — the exact items shown in the
/// reference screenshots, tuned so the Dashboard reads 10 products / 403 total
/// units / 2 low-stock / 0 installed-today (the install record below is dated
/// 2026-06-28, not "today").
///
/// This is PLACEHOLDER data: in-memory only, resets on app restart. See
/// docs/MOCKED_VS_REAL.md.
const List<Product> kSeedProducts = [
  Product(
    id: 'p_outlet',
    name: '240V Power Outlet',
    barcode: '0012345678905',
    sku: 'OUT-240V',
    category: 'Electrical',
    location: 'Shelf C1',
    quantity: 35,
    unit: 'units',
    minStock: 8,
  ),
  Product(
    id: 'p_cat6',
    name: 'Cat6 Cable 305m',
    barcode: '7591031311369',
    sku: 'CBL-CAT6',
    category: 'Cabling',
    location: 'Shelf B2',
    quantity: 12,
    unit: 'rolls',
    minStock: 3,
  ),
  Product(
    id: 'p_conduit',
    name: 'Conduit 20mm 3m',
    barcode: '6889183391393',
    sku: 'CDT-20MM',
    category: 'Cabling',
    location: 'Shelf F1',
    quantity: 68,
    unit: 'lengths',
    minStock: 10,
  ),
  Product(
    id: 'p_hdmi',
    name: 'HDMI 2.1 Cable 2m',
    barcode: '8806098020689',
    sku: 'HDMI-21',
    category: 'AV',
    location: 'Shelf D1',
    quantity: 22,
    unit: 'units',
    minStock: 5,
  ),
  Product(
    id: 'p_junction',
    name: 'Junction Box IP66',
    barcode: '5555100001007',
    sku: 'JB-IP66',
    category: 'Electrical',
    location: 'Shelf C3',
    quantity: 2, // LOW (min 5)
    unit: 'units',
    minStock: 5,
  ),
  Product(
    id: 'p_led',
    name: 'LED Downlight 10W',
    barcode: '5901234123457',
    sku: 'LED-10W',
    category: 'Lighting',
    location: 'Shelf A1',
    quantity: 47,
    unit: 'units',
    minStock: 10,
  ),
  Product(
    id: 'p_switch',
    name: 'Network Switch 8P',
    barcode: '8885378148488',
    sku: 'NSW-8P',
    category: 'Networking',
    location: 'Shelf F1',
    quantity: 4,
    unit: 'units',
    minStock: 2,
  ),
  Product(
    id: 'p_wallplate',
    name: 'Wall Plate Single',
    barcode: '4006381333931',
    sku: 'WP-1G',
    category: 'Electrical',
    location: 'Shelf D3',
    quantity: 3, // LOW (min 15)
    unit: 'units',
    minStock: 15,
  ),
  Product(
    id: 'p_rj45',
    name: 'RJ45 Connector',
    barcode: '1234567890123',
    sku: 'RJ45-CAT6',
    category: 'Networking',
    location: 'Shelf B1',
    quantity: 130,
    unit: 'units',
    minStock: 50,
  ),
  Product(
    id: 'p_smoke',
    name: 'Smoke Detector',
    barcode: '9780201379624',
    sku: 'SMK-DET',
    category: 'Safety',
    location: 'Shelf A2',
    quantity: 80,
    unit: 'units',
    minStock: 20,
  ),
];

/// Seed install history — the single record shown in the reference Dashboard /
/// History (LED Downlight 10W, Jake Morrison, 42 Maple Drive, 2026-06-28).
final List<Installation> kSeedInstallations = [
  Installation(
    id: 'i_led_0628',
    productId: 'p_led',
    productName: 'LED Downlight 10W',
    quantity: 1,
    installerName: 'Jake Morrison',
    address: '42 Maple Drive, Ottawa, ON',
    installedAt: DateTime(2026, 6, 28, 23, 6),
  ),
];
