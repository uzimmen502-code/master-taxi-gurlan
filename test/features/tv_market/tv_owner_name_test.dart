import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_owner_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tvOwnerGivenName', () {
    test('@nick бўш', () {
      expect(tvOwnerGivenName('@ali'), isEmpty);
      expect(tvOwnerGivenName('@nick'), isEmpty);
    });

    test('UI fallback бўш', () {
      expect(tvOwnerGivenName('Фойдаланувчи'), isEmpty);
      expect(tvOwnerGivenName('foydalanuvchi'), isEmpty);
      expect(tvOwnerGivenName('Пользователь'), isEmpty);
    });

    test('телефон бўш', () {
      expect(tvOwnerGivenName('998901234567'), isEmpty);
    });

    test('профил исми — биринчи сўз', () {
      expect(tvOwnerGivenName('Алишер Каримов'), 'Алишер');
      expect(tvOwnerGivenName('Madina'), 'Madina');
    });
  });

  group('tvOwnerDisplayName', () {
    test('тўлиқ исм', () {
      expect(tvOwnerDisplayName('Алишер Каримов'), 'Алишер Каримов');
      expect(tvOwnerDisplayName('Madina'), 'Madina');
    });

    test('@nick ва fallback бўш', () {
      expect(tvOwnerDisplayName('@ali'), isEmpty);
      expect(tvOwnerDisplayName('Фойдаланувчи'), isEmpty);
    });
  });

  group('tvPublisherOverlayName', () {
    TvClip clip({String ownerName = '', String ownerPhone = '998901111111'}) {
      return TvClip(
        id: 'c1',
        videoUrl: '',
        posterUrl: '',
        title: 't',
        price: 0,
        districtId: '',
        districtLabel: '',
        ownerPhone: ownerPhone,
        ownerName: ownerName,
        category: 'product',
      );
    }

    test('клипдаги жойлаштирувчи исми', () {
      expect(
        tvPublisherOverlayName(
          clip: clip(ownerName: 'Дилшод Рахимов'),
          viewerPhone: '998902222222',
          viewerDisplayName: 'Томошабин',
        ),
        'Дилшод Рахимов',
      );
    });

    test('томошабин исми бошқанинг ролигига қўйилмайди', () {
      expect(
        tvPublisherOverlayName(
          clip: clip(ownerName: '@nick'),
          viewerPhone: '998902222222',
          viewerDisplayName: 'Томошабин',
        ),
        isEmpty,
      );
    });

    test('оммавий профилдан жойлаштирувчи', () {
      expect(
        tvPublisherOverlayName(
          clip: clip(ownerName: 'Фойдаланувчи', ownerPhone: '998901111111'),
          viewerPhone: '998902222222',
          viewerDisplayName: 'Томошабин',
          publicNames: {'998901111111': 'Нилуфар'},
        ),
        'Нилуфар',
      );
    });

    test('ўз ролиги — локал профил', () {
      expect(
        tvPublisherOverlayName(
          clip: clip(ownerName: '@me'),
          viewerPhone: '998901111111',
          viewerDisplayName: 'Алишер Каримов',
        ),
        'Алишер Каримов',
      );
    });
  });
}
