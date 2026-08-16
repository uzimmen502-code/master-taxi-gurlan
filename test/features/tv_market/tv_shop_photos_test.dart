import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TvShopItem.normalizePhotos', () {
    test('эски photoUrl', () {
      expect(
        TvShopItem.normalizePhotos(photoUrl: 'a.jpg'),
        ['a.jpg'],
      );
    });

    test('photoUrls устун, бўшлар чиқарилади', () {
      expect(
        TvShopItem.normalizePhotos(
          rawUrls: ['a.jpg', '', 'b.jpg'],
          photoUrl: 'old.jpg',
        ),
        ['a.jpg', 'b.jpg'],
      );
    });

    test('5 тадан ошмайди', () {
      expect(
        TvShopItem.normalizePhotos(
          rawUrls: ['1', '2', '3', '4', '5', '6'],
        ).length,
        TvShopItem.maxPhotos,
      );
    });

    test('дубликат йўқ', () {
      expect(
        TvShopItem.normalizePhotos(rawUrls: ['a.jpg', 'a.jpg', 'b.jpg']),
        ['a.jpg', 'b.jpg'],
      );
    });
  });

  test('displayPhotos қоплама', () {
    const item = TvShopItem(
      id: 'i1',
      ownerPhone: '998901111111',
      ownerName: 'Ali',
      title: 't',
      price: 1000,
      photoUrl: 'cover.jpg',
      photoUrls: ['cover.jpg', 'two.jpg'],
      kind: 'product',
      districtId: 'd',
      districtLabel: 'D',
    );
    expect(item.coverPhotoUrl, 'cover.jpg');
    expect(item.displayPhotos, ['cover.jpg', 'two.jpg']);
  });
}
