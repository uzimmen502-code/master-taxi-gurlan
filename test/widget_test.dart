import 'package:flutter_test/flutter_test.dart';
import 'package:master_taxi_gurlan/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MasterTaxiApp());
  });
}