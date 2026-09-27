import 'package:ava_gurlan/features/home/widgets/service_circle_tile.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `olxTintFor` номаълум модул учун қайтарадиган нейтрал ранг.
const _fallback = Color(0xFFD9E2EC);

void main() {
  group('olxTintFor — OLX услубидаги доира ранги', () {
    test('ҳар бир маълум модулнинг ЎЗ ранги бор', () {
      // Янги модул қўшилиб, ранги ёзилмай қолса — шу тест йиқилади.
      // Акс ҳолда у гридда бошқалардан ажралмайдиган кулранг доира
      // бўлиб чиқарди ва буни ҳеч ким сезмасди.
      final rangsiz = kKnownModuleIds
          .where((id) => olxTintFor(id) == _fallback)
          .toList();
      expect(
        rangsiz,
        isEmpty,
        reason: 'Бу модулларга `olxTintFor` да ранг қўшилмаган: $rangsiz',
      );
    });

    test('номаълум модул — нейтрал рангга тушади, йиқилмайди', () {
      expect(olxTintFor('umuman_yoq_modul'), _fallback);
      expect(olxTintFor(''), _fallback);
    });

    test('маъно бўйича танланган: такси сариқ, шаҳарлараро феруза', () {
      expect(olxTintFor('local_taxi'), const Color(0xFFFFC93D));
      expect(olxTintFor('intercity'), const Color(0xFF1BD9CE));
    });

    test('тўлов провайдерлари — оч нейтрал (бренд логотипи ўз рангида)', () {
      const pale = Color(0xFFEEF1F6);
      expect(olxTintFor('pay_click'), pale);
      expect(olxTintFor('pay_payme'), pale);
      expect(olxTintFor('pay_paynet'), pale);
    });

    test('ранглар тўлиқ шаффоф эмас — доира кўринмай қолмайди', () {
      for (final id in kKnownModuleIds) {
        expect(olxTintFor(id).a, 1.0, reason: id);
      }
    });
  });

  group('serviceGlyph — бўлим сарлавҳаси олдидаги доира расми', () {
    test('ҳар бир маълум модулнинг расми ёки иконкаси бор', () {
      // Бу жадвал `home_services_catalog.dart` ни такрорлайди (каталог
      // банди BuildContext ва action талаб қилгани учун ундан ўқиб
      // бўлмайди). Янги модул фақат каталогга қўшилса — сарлавҳада
      // доира БЎШ чиқарди; шу тест буни ушлайди.
      final glyphsiz =
          kKnownModuleIds.where((id) => !hasServiceGlyph(id)).toList();
      expect(
        glyphsiz,
        isEmpty,
        reason: '`service_circle_tile.dart` жадвалига қўшилмаган: $glyphsiz',
      );
    });

    test('расм ва иконка бир модулда такрорланмайди', () {
      for (final id in kKnownModuleIds) {
        final manbalar = [
          serviceImageFor(id),
          serviceSvgFor(id),
          serviceIconFor(id),
        ].where((e) => e != null).length;
        expect(manbalar, 1, reason: '$id — аниқ битта манба бўлиши керак');
      }
    });

    test('номаълум модул — доира чизилмайди', () {
      expect(hasServiceGlyph('umuman_yoq'), isFalse);
      expect(serviceImageFor('umuman_yoq'), isNull);
    });
  });

  group('Ўлчамлар', () {
    test('OLX манба қиймати ўзгармаган — 88px', () {
      // Бу ўлчанган қиймат (olx.uz, 2026-09-26), созлама эмас.
      expect(ServiceCircleTile.olxReferenceCircle, 88);
    });

    test('доира икки босқичда кичрайтирилган: 88 → −20% → −15%', () {
      // Эга қарорлари (иккиси ҳам 2026-09-27):
      //   1) бош саҳифадаги 2 қаторли блок жуда баланд → −20%
      //   2) «доиралар ўлчамини тахминан 15% га кичрайтир» → −15%
      final birinchi = ServiceCircleTile.olxReferenceCircle * 0.8; // 70.4
      final ikkinchi = birinchi * 0.85; // 59.84
      expect(ServiceCircleTile.circleSize, closeTo(ikkinchi, 1.0));
      expect(ServiceCircleTile.circleSize, 60);
    });

    test('ёрлиқ шрифти эски ўлчамнинг айнан ярми', () {
      // Эга қарори 2026-09-27: «шрифт ўлчамини 2 баробарга кичрайтир».
      // Эски формула: (w × 0.125).clamp(11.5, 16).
      const eskiFactor = 0.125;
      const eskiMin = 11.5;
      const eskiMax = 16.0;
      expect(ServiceCircleTile.labelSizeFactor, eskiFactor / 2);
      expect(ServiceCircleTile.labelSizeMin, eskiMin / 2);
      expect(ServiceCircleTile.labelSizeMax, eskiMax / 2);

      // Ҳақиқий устун энида (104px) — 13 эмас, 6.5.
      expect(ServiceCircleTile.labelFontSize(104), 6.5);
    });

    test('катак доира + ёзувни сиғдиради', () {
      // Ўлчам формуладан олинади — тест билан виджет айнан бир хил
      // қийматни ишлатсин (олдин бу ерда 13 қўлда ёзилган эди ва
      // шрифт ўзгарганда тест эскириб қолди).
      final yorliq = ServiceCircleTile.labelFontSize(104);
      final engKam = ServiceCircleTile.circleSize +
          ServiceCircleTile.labelGap +
          ServiceCircleTile.labelMaxLines *
              yorliq *
              ServiceCircleTile.labelLineHeight;
      expect(ServiceCircleTile.tileHeight, greaterThanOrEqualTo(engKam));
      // Ортиқча бўш жой ҳам қолмасин.
      expect(ServiceCircleTile.tileHeight - engKam, lessThan(16));
    });

    test('130% шрифтда ҳам ёзув катакка сиғади', () {
      // Ёрлиқ масштаби 1.15 билан чегараланган (виджетдаги
      // `withClampedTextScaling`) — энг ёмон ҳолат шу.
      final yorliq = ServiceCircleTile.labelFontSize(104) * 1.15;
      final engKam = ServiceCircleTile.circleSize +
          ServiceCircleTile.labelGap +
          ServiceCircleTile.labelMaxLines *
              yorliq *
              ServiceCircleTile.labelLineHeight;
      expect(
        ServiceCircleTile.tileHeight,
        greaterThanOrEqualTo(engKam),
        reason: 'катак ($engKam) га сиғмайди — ёзув кесилади',
      );
    });
  });
}
