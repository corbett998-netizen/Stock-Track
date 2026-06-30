import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stock_track/app.dart';
import 'package:stock_track/core/utils/stock_status.dart';
import 'package:stock_track/data/providers/repository_providers.dart';
import 'package:stock_track/data/repositories/installation_repository.dart';
import 'package:stock_track/data/repositories/inventory_repository.dart';

void main() {
  group('stockStatusFor (single source of truth)', () {
    test('quantity above minStock is in-stock', () {
      expect(stockStatusFor(quantity: 35, minStock: 8), StockStatus.inStock);
    });

    test('quantity at or below minStock (but > 0) is low', () {
      expect(stockStatusFor(quantity: 2, minStock: 5), StockStatus.low);
      expect(stockStatusFor(quantity: 5, minStock: 5), StockStatus.low);
    });

    test('zero or negative quantity is out', () {
      expect(stockStatusFor(quantity: 0, minStock: 5), StockStatus.out);
    });
  });

  testWidgets('App boots with mock repositories and shows the Dashboard',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider
              .overrideWithValue(MockInventoryRepository()),
          installationRepositoryProvider
              .overrideWithValue(MockInstallationRepository()),
        ],
        child: const StockTrackApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('StockTrack'), findsOneWidget);
    expect(find.text('Warehouse Dashboard'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
