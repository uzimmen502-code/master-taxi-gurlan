import 'package:ava_gurlan/core/app_version_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Минимал версия дарвозаси — қарор мантиғи.
///
/// Бу тестлар «дарвоза ишлайдими» дан кўра «дарвоза НОТЎҒРИ ЁПИЛИБ
/// ҚОЛМАЙДИМИ» ни текширади. Сабаби: нотўғри ёпилиш БУТУН иловани
/// ишдан чиқаради ва фойдаланувчи ҳеч нарса қила олмайди — хато
/// қиймат киритилса ҳам, Firestore узилса ҳам.
void main() {
  setUp(AppVersionGate.resetForTest);
  tearDown(AppVersionGate.resetForTest);

  group('mustUpdate — мажбурий янгилаш', () {
    test('эски версия — блокланади', () {
      AppVersionGate.setForTest(currentBuild: 67, minSupportedBuild: 70);
      expect(AppVersionGate.mustUpdate, isTrue);
    });

    test('айнан минимал версия — блокланмайди', () {
      // Чегара: `<` ишлатилади, `<=` эмас. 70 талаб қилинса, 70 ўтади.
      AppVersionGate.setForTest(currentBuild: 70, minSupportedBuild: 70);
      expect(AppVersionGate.mustUpdate, isFalse);
    });

    test('янгироқ версия — блокланмайди', () {
      AppVersionGate.setForTest(currentBuild: 73, minSupportedBuild: 70);
      expect(AppVersionGate.mustUpdate, isFalse);
    });
  });

  group('ХАТОДА ОЧИҚ ҚОЛАДИ — энг муҳим кафолат', () {
    test('ўз версияси номаълум (0) — блокламайди', () {
      // `package_info_plus` ишламаса шу ҳолат бўлади (веб, эски
      // қурилма). Иловани ишдан чиқаргандан кўра дарвозани очиқ
      // қолдириш афзал.
      AppVersionGate.setForTest(currentBuild: 0, minSupportedBuild: 999);
      expect(AppVersionGate.mustUpdate, isFalse);
    });

    test('конфиг йўқ (min = 0) — блокламайди', () {
      // `config/app_version` ҳужжати ҳали яратилмаган ҳолат.
      AppVersionGate.setForTest(currentBuild: 70, minSupportedBuild: 0);
      expect(AppVersionGate.mustUpdate, isFalse);
    });

    test('иккаласи ҳам номаълум — блокламайди', () {
      AppVersionGate.setForTest();
      expect(AppVersionGate.mustUpdate, isFalse);
    });

    test('манфий min — блокламайди', () {
      // Репозиторий манфийни 0 га айлантиради, лекин дарвоза ўзи ҳам
      // ҳимояланган бўлсин.
      AppVersionGate.setForTest(currentBuild: 70, minSupportedBuild: -5);
      expect(AppVersionGate.mustUpdate, isFalse);
    });
  });

  group('updateAvailable — юмшоқ эслатма', () {
    test('янги версия бор — эслатма кўринади', () {
      AppVersionGate.setForTest(currentBuild: 70, latestBuild: 73);
      expect(AppVersionGate.updateAvailable, isTrue);
      expect(AppVersionGate.mustUpdate, isFalse);
    });

    test('энг сўнггисида — эслатма йўқ', () {
      AppVersionGate.setForTest(currentBuild: 73, latestBuild: 73);
      expect(AppVersionGate.updateAvailable, isFalse);
    });

    test('мажбурий янгилаш устун — юмшоқ эслатма кўрсатилмайди', () {
      // Иккита хабарни бир вақтда кўрсатиш керак эмас: блок экрани
      // барибир ҳаммасини ёпади.
      AppVersionGate.setForTest(
        currentBuild: 60,
        minSupportedBuild: 70,
        latestBuild: 73,
      );
      expect(AppVersionGate.mustUpdate, isTrue);
      expect(AppVersionGate.updateAvailable, isFalse);
    });

    test('latest номаълум — эслатма йўқ', () {
      AppVersionGate.setForTest(currentBuild: 70, latestBuild: 0);
      expect(AppVersionGate.updateAvailable, isFalse);
    });
  });

  group('Ҳақиқий релиз рақамлари билан', () {
    // 2026-09-27 ҳолати: Play'да 1.0.32 (70) жонли, фойдаланувчиларнинг
    // бир қисми ҳамон 1.0.24 (62) / 1.0.26 (64) / 1.0.29 (67) да.
    const eskiBuildlar = [62, 64, 67];

    test('min=70 қўйилса — барча эски версиялар блокланади', () {
      for (final b in eskiBuildlar) {
        AppVersionGate.setForTest(currentBuild: b, minSupportedBuild: 70);
        expect(AppVersionGate.mustUpdate, isTrue, reason: 'build $b');
      }
    });

    test('70 нинг ўзи ишлайверади', () {
      AppVersionGate.setForTest(currentBuild: 70, minSupportedBuild: 70);
      expect(AppVersionGate.mustUpdate, isFalse);
    });
  });
}
