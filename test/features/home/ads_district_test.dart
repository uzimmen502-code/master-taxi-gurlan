import 'package:ava_gurlan/features/ads/models/ad_model.dart';
import 'package:ava_gurlan/models/job_ad.dart';
import 'package:flutter_test/flutter_test.dart';

AdModel _market(Map<String, dynamic> extra) => AdModel.fromMap('m1', {
      'title': 'Sut',
      'price': 12000,
      ...extra,
    });

void main() {
  group('AdModel — hudud maydoni', () {
    test('districtId / regionId hujjatdan o‘qiladi', () {
      final a = _market({'districtId': 'gurlan', 'regionId': 'xorazm'});
      expect(a.districtId, 'gurlan');
      expect(a.regionId, 'xorazm');
    });

    test('eski yozuvda maydon yo‘q — bo‘sh', () {
      expect(_market({}).districtId, '');
      expect(_market({}).regionId, '');
    });

    test('bo‘shliqlar trim qilinadi', () {
      expect(_market({'districtId': ' gurlan '}).districtId, 'gurlan');
    });
  });

  group('JobAd — muddat va tur', () {
    test('muddati o‘tgan e’lon isExpired', () {
      final past = JobAd(
        id: 'j1',
        type: 'ad',
        text: 't',
        authorName: 'a',
        authorPhone: '998901234567',
        address: '',
        isUrgent: false,
        status: 'active',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(past.isExpired, isTrue);
    });

    test('muddati kelmagani chiqib turadi', () {
      final future = JobAd(
        id: 'j2',
        type: 'service',
        text: 't',
        authorName: 'a',
        authorPhone: '998901234567',
        address: '',
        isUrgent: false,
        status: 'active',
        expiresAt: DateTime.now().add(const Duration(days: 3)),
      );
      expect(future.isExpired, isFalse);
    });

    test('muddatsiz e’lon ham chiqadi', () {
      const noExp = JobAd(
        id: 'j3',
        type: 'ad',
        text: 't',
        authorName: 'a',
        authorPhone: '998901234567',
        address: '',
        isUrgent: false,
        status: 'active',
      );
      expect(noExp.isExpired, isFalse);
    });

    test('2/3-bo‘lim va 6-bo‘lim turlari kesishmaydi', () {
      // 2/3-bo'lim: ad / service (jobs board). 6-bo'lim: cheap_product.
      // Bitta hujjat ikkala ro'yxatga tusha olmaydi.
      expect(JobAd.isJobsBoardType('ad'), isTrue);
      expect(JobAd.isJobsBoardType('service'), isTrue);
      expect(JobAd.isJobsBoardType(AdModel.typeKey), isFalse);
    });
  });
}
