import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_trip_dot_icon.dart';
import 'package:ava_gurlan/features/ev_charging/widgets/ev_trip_map_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// Xarita: rejaga kirmagan "boshqa" stansiyalar - kichik xira nuqta (yorqin
// yashil igna emas); tavsiya/tanlangan/zaxira belgilari o'zgarmagan.

void main() {
  group('EvTripMapGeometry.markerStyle', () {
    test('tanlangan - raqamli (turidan qat\'i nazar)', () {
      for (final k in EvTripMarkerKind.values) {
        expect(EvTripMapGeometry.markerStyle(k, 2), EvTripMarkerStyle.numbered,
            reason: '$k');
      }
    });

    test('tanlanmagan: asosiy qizil igna, zaxira to\'q sariq igna', () {
      expect(EvTripMapGeometry.markerStyle(EvTripMarkerKind.primary, null),
          EvTripMarkerStyle.primaryPin);
      expect(EvTripMapGeometry.markerStyle(EvTripMarkerKind.backup, null),
          EvTripMarkerStyle.backupPin);
    });

    test('tanlanmagan "boshqa" - xira nuqta', () {
      expect(EvTripMapGeometry.markerStyle(EvTripMarkerKind.other, null),
          EvTripMarkerStyle.mutedDot);
    });
  });

  group('EvTripDotIcon', () {
    test('rang - temadagi neytral kulrang (ink3), yashil emas', () {
      expect(EvTripDotIcon.color, AvaLight.ink3);
      final c = EvTripDotIcon.color;
      // Neytral: R, G, B deyarli teng - hech qanday rang tusi yo'q.
      expect((c.r - c.g).abs(), lessThan(0.02));
      expect((c.g - c.b).abs(), lessThan(0.02));
      // Eski yorqin yashil (0xFF388E3C) emas.
      expect(c, isNot(const Color(0xFF388E3C)));
    });

    test('nuqta kichik, bosiladigan maydon kattaroq', () {
      expect(EvTripDotIcon.visibleDiameter, lessThan(20));
      expect(EvTripDotIcon.logicalSize, greaterThanOrEqualTo(24));
      expect(EvTripDotIcon.logicalSize,
          greaterThan(EvTripDotIcon.visibleDiameter));
    });

    testWidgets('bir marta chiziladi (kesh): ikki chaqiruv - bitta Future',
        (tester) async {
      EvTripDotIcon.reset();
      final a = EvTripDotIcon.load();
      final b = EvTripDotIcon.load();
      expect(identical(a, b), isTrue);
      final icon = await tester.runAsync(() => a);
      expect(icon, isA<BitmapDescriptor>());
      // Tugagach ham o'sha Future.
      expect(identical(EvTripDotIcon.load(), a), isTrue);
    });
  });
}
