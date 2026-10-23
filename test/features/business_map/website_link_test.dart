import 'package:ava_gurlan/features/business_map/domain/website_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('websiteUri', () {
    test('схемасиз домен — https қўшилади', () {
      expect(websiteUri('kafe.uz')?.toString(), 'https://kafe.uz');
      expect(websiteUri('  www.kafe.uz/menu ')?.toString(), 'https://www.kafe.uz/menu');
    });

    test('http/https сақланади (регистрсиз)', () {
      expect(websiteUri('http://kafe.uz')?.toString(), 'http://kafe.uz');
      expect(websiteUri('HTTPS://kafe.uz')?.host, 'kafe.uz');
    });

    test('Telegram @ҳандл, бўш жой, нуқтасиз сўз, бошқа схемалар — рад', () {
      expect(websiteUri('@kafe_gurlan'), isNull);
      expect(websiteUri('kafe gurlan.uz'), isNull);
      expect(websiteUri('kafe'), isNull);
      expect(websiteUri(''), isNull);
      expect(websiteUri('javascript:alert(1)'), isNull);
      expect(websiteUri('mailto:a@b.uz'), isNull);
      expect(websiteUri('tel:+998901234567'), isNull);
      expect(websiteUri('https://'), isNull);
      expect(websiteUri('.uz'), isNull);
    });

    test('t.me ҳаволаси оддий сайт сифатида очилади (махсус ишлов йўқ)', () {
      expect(websiteUri('t.me/kafe')?.toString(), 'https://t.me/kafe');
    });
  });

  group('websiteFieldValid', () {
    test('бўш — тўғри (ихтиёрий); тўлдирилса — сайт бўлиши шарт', () {
      expect(websiteFieldValid(''), isTrue);
      expect(websiteFieldValid('   '), isTrue);
      expect(websiteFieldValid('kafe.uz'), isTrue);
      expect(websiteFieldValid('@kafe'), isFalse);
    });
  });
}
