import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/screens/business_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// «Менинг дўконим» → «Янги дўкон»: тур («чакана/улгуржи») танлови яширин; харита рўйхатидаги
/// умумий формада аввалгидек бор.
void main() {
  Future<void> open(WidgetTester tester, {required bool lock}) async {
    tester.view.physicalSize = const Size(400 * 2, 1600 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: BusinessFormScreen(
        key: UniqueKey(),
        initialCategory: BusinessCategory.retail,
        lockCategory: lock,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lockCategory: тур танлови йўқ, ном майдони бор', (tester) async {
    await open(tester, lock: true);
    expect(find.byType(DropdownButtonFormField<BusinessCategory>), findsNothing);
    expect(find.text('bizmap_f_category'), findsNothing);
    expect(find.text('bizmap_f_name'), findsOneWidget);
  });

  testWidgets('умумий форма (харита): тур танлови аввалгидек', (tester) async {
    await open(tester, lock: false);
    expect(find.byType(DropdownButtonFormField<BusinessCategory>), findsOneWidget);
  });
}