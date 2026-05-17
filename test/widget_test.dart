import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flutter smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('Master Taxi')));
    expect(find.text('Master Taxi'), findsOneWidget);
  });
}
