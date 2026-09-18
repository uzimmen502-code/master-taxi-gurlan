import 'package:ava_gurlan/features/tv_market/services/tv_network_quality_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// В-4 1-босқич: фиксланган 2.5s prefetch timeout ўрнига, сўнгги клиплар
/// қандай буферланганига (соғлом/timeout) қараб мослашувчи вақт.
void main() {
  setUp(TvNetworkQualityService.resetHealthHistoryForTest);
  tearDown(TvNetworkQualityService.resetHealthHistoryForTest);

  group('TvNetworkQualityService.adaptivePrefetchTimeout', () {
    test('тарих йўқ — нейтрал 2.5s', () {
      expect(
        TvNetworkQualityService.adaptivePrefetchTimeout(),
        const Duration(milliseconds: 2500),
      );
    });

    test('сўнгги клиплар кўпи соғлом (>=80%) — қисқа timeout (тезроқ prefetch)',
        () {
      for (var i = 0; i < 4; i++) {
        TvNetworkQualityService.recordBufferHealth(true);
      }
      TvNetworkQualityService.recordBufferHealth(false);
      expect(
        TvNetworkQualityService.adaptivePrefetchTimeout(),
        const Duration(milliseconds: 1500),
      );
    });

    test('сўнгги клиплар кўпи timeout (<=30%) — узун timeout (заиф тармоқ)',
        () {
      TvNetworkQualityService.recordBufferHealth(true);
      for (var i = 0; i < 4; i++) {
        TvNetworkQualityService.recordBufferHealth(false);
      }
      expect(
        TvNetworkQualityService.adaptivePrefetchTimeout(),
        const Duration(milliseconds: 4000),
      );
    });

    test('аралаш натижа (ўртача) — нейтрал 2.5s', () {
      TvNetworkQualityService.recordBufferHealth(true);
      TvNetworkQualityService.recordBufferHealth(false);
      expect(
        TvNetworkQualityService.adaptivePrefetchTimeout(),
        const Duration(milliseconds: 2500),
      );
    });

    test('ойна чегараси — фақат сўнгги 5 та ёзув ҳисобга олинади', () {
      // Аввал 5 та "timeout" (узун бўлиши керак эди), кейин 5 та "соғлом"
      // — эскилари эсдан чиқади, натижада фақат "соғлом" қолади.
      for (var i = 0; i < 5; i++) {
        TvNetworkQualityService.recordBufferHealth(false);
      }
      for (var i = 0; i < 5; i++) {
        TvNetworkQualityService.recordBufferHealth(true);
      }
      expect(
        TvNetworkQualityService.adaptivePrefetchTimeout(),
        const Duration(milliseconds: 1500),
      );
    });
  });
}
