import 'package:flutter_test/flutter_test.dart';
import 'package:ava_gurlan/features/ev_charging/controllers/ev_navigation_session_controller.dart';

void main() {
  group('EvNavigationSessionController.hasArrived', () {
    test('target koordinatasida — true', () {
      expect(
        EvNavigationSessionController.hasArrived(
          currentLat: 41.55,
          currentLng: 60.60,
          targetLat: 41.55,
          targetLng: 60.60,
          radiusMeters: 50,
        ),
        isTrue,
      );
    });

    test('radius ichida (taxminan 20m) — true', () {
      expect(
        EvNavigationSessionController.hasArrived(
          currentLat: 41.55,
          currentLng: 60.60,
          targetLat: 41.55018,
          targetLng: 60.60,
          radiusMeters: 50,
        ),
        isTrue,
      );
    });

    test('radiusdan uzoq (taxminan 500m) — false', () {
      expect(
        EvNavigationSessionController.hasArrived(
          currentLat: 41.55,
          currentLng: 60.60,
          targetLat: 41.555,
          targetLng: 60.60,
          radiusMeters: 50,
        ),
        isFalse,
      );
    });
  });
}
