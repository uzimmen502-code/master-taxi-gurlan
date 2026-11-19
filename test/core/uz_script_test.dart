import 'package:ava_gurlan/core/utils/uz_script.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UzScript.toLatin', () {
    const cases = {
      // Янги алифбо (эга 2026-11-19): ў→ö, ғ→ğ, ш→ş, ч→ç.
      'Ичимликлар': 'Içimliklar',
      'Шашлик': 'Şaşlik',
      'Ўзбек таомлари': 'Özbek taomlari',
      'Ғалла': 'Ğalla',
      'Қуйма': 'Quyma',
      'Ҳалим': 'Halim',
      'Чойхона': 'Çoyxona',
      'Эски': 'Eski',
      'Еттинчи': 'Yettinçi',
      'Маъно': "Ma'no",
      'Ёнғоқ': 'Yonğoq',
      'Борщ': 'Borşç',
      'Нон ва хамир таомлари': 'Non va xamir taomlari',
      'Иссиқ таомлар': 'Issiq taomlar',
    };
    cases.forEach((cyr, lat) => test('$cyr → $lat', () => expect(UzScript.toLatin(cyr), lat)));

    test('ҳарф катталиги сақланади: ҲАММАСИ КАТТА → ҲАММАСИ КАТТА', () {
      expect(UzScript.toLatin('ШАШЛИК'), 'ŞAŞLIK');
      expect(UzScript.toLatin('ЧОЙ'), 'ÇOY');
      expect(UzScript.toLatin('ЎЗБЕК'), 'ÖZBEK');
      expect(UzScript.toLatin('шашлик'), 'şaşlik');
    });

    test('лотин сўз, рақам ва тиниш белгилари ўзгармайди; аралашмада фақат кирилл сўз', () {
      expect(UzScript.toLatin('Coca-Cola 0.5 л'), 'Coca-Cola 0.5 l');
      expect(UzScript.toLatin('KFC'), 'KFC');
      expect(UzScript.toLatin(''), '');
    });

    test('рус сўзи ўқилади', () {
      expect(UzScript.toLatin('Напитки'), 'Napitki');
      expect(UzScript.toLatin('Горячие блюда'), 'Goryaçiye blyuda');
    });
  });

  group('UzScript.toCyrillic', () {
    const cases = {
      'Ichimliklar': 'Ичимликлар',
      'Shashlik': 'Шашлик',
      "O'zbek taomlari": 'Ўзбек таомлари',
      "G'alla": 'Ғалла',
      'Quyma': 'Қуйма',
      'Halim': 'Ҳалим',
      'Choyxona': 'Чойхона',
      'Eski': 'Эски',
      'Yettinchi': 'Еттинчи',
      "Ma'no": 'Маъно',
      "Sho'rva": 'Шўрва',
      // Янги алифбо ҳарфлари ҳам (эга 2026-11-19).
      'Içimliklar': 'Ичимликлар',
      'Şaşlik': 'Шашлик',
      'Özbek taomlari': 'Ўзбек таомлари',
      'Ğalla': 'Ғалла',
      'Şörva': 'Шўрва',
      'Çoyxona': 'Чойхона',
      'Non va xamir taomlari': 'Нон ва хамир таомлари',
      'Issiq taomlar': 'Иссиқ таомлар',
    };
    cases.forEach((lat, cyr) => test('$lat → $cyr', () => expect(UzScript.toCyrillic(lat), cyr)));

    test('ҳарф катталиги сақланади', () {
      expect(UzScript.toCyrillic('SHASHLIK'), 'ШАШЛИК');
      expect(UzScript.toCyrillic('CHOY'), 'ЧОЙ');
      expect(UzScript.toCyrillic('shashlik'), 'шашлик');
      expect(UzScript.toCyrillic('ŞAŞLIK'), 'ШАШЛИК');
      expect(UzScript.toCyrillic('ÇOY'), 'ЧОЙ');
    });

    test("ажратувчи: Is'hoq — s ва h алоҳида (ш эмас)", () {
      expect(UzScript.toCyrillic("Is'hoq"), 'Исъҳоқ');
    });

    test('бренд (c/w ҳарфли) ва кирилл сўзлар ўзгармайди', () {
      expect(UzScript.toCyrillic('Coca-Cola'), 'Coca-Cola');
      expect(UzScript.toCyrillic('KFC'), 'KFC');
      expect(UzScript.toCyrillic('Wok'), 'Wok');
      expect(UzScript.toCyrillic('Ичимликлар'), 'Ичимликлар');
    });

    test('ʻ ʼ ‘ ’ белгилари бир хил қабул қилинади', () {
      expect(UzScript.toCyrillic('Oʻzbek'), 'Ўзбек');
      expect(UzScript.toCyrillic('O‘zbek'), 'Ўзбек');
      expect(UzScript.toCyrillic('O’zbek'), 'Ўзбек');
    });

    test('аралаш жумлада фақат соф ўзбек лотин сўзи ўгирилади', () {
      expect(UzScript.toCyrillic('Fanta va Coca-Cola'), 'Фанта ва Coca-Cola');
    });
  });

  group('UzScript.foldLatin (қидирув/солиштириш, эга 2026-11-19)', () {
    test('янги ҳарфлар эски шаклга; эски шакл ўзгармайди', () {
      expect(UzScript.foldLatin('Özbekça şahar ğişt'), "O'zbekcha shahar g'isht");
      expect(UzScript.foldLatin('ŞÖĞÇ'), "ShO'G'Ch");
      expect(UzScript.foldLatin("O'zbekcha shahar"), "O'zbekcha shahar");
      expect(UzScript.foldLatin('Ўзбек'), 'Ўзбек');
      expect(UzScript.foldLatin(''), '');
    });
    test('toLatin натижаси fold қилинса — эски лотин шаклига тенг', () {
      expect(UzScript.foldLatin(UzScript.toLatin('Ширинликлар')), 'Shirinliklar');
      expect(UzScript.foldLatin(UzScript.toLatin('Гўшт')), "Go'sht");
    });
  });

  group('иккала йўналиш мувофиқ', () {
    test('кирилл → лотин → кирилл: ўзбек сўзларида аниқ қайтади', () {
      for (final s in ['Ичимликлар', 'Шашлик', 'Ширинликлар', 'Салатлар', 'Фастфуд', 'Иккинчи таомлар', 'Қуйма', 'Ўзбек таомлари']) {
        expect(UzScript.toCyrillic(UzScript.toLatin(s)), s, reason: s);
      }
    });
  });
}
