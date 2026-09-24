import 'package:flutter_test/flutter_test.dart';
import 'package:ava_gurlan/core/app_share.dart';
import 'package:ava_gurlan/features/tv_market/services/tv_clip_share.dart';

/// Улашиш матни — эга айнан шу таҳрирни талаб қилган (2026-09-24), шунинг
/// учун матн ва ҳавола тасодифан ўзгариб кетмаслиги тестда қулфланади.
void main() {
  test('улашиш матни — CTA ва ундан кейин Play ҳаволаси', () {
    final lines = kAvaShareMessage.split('\n');
    expect(lines.length, 2, reason: 'фақат CTA + ҳавола бўлиши керак');
    expect(lines.first, kAvaShareCta);
    expect(lines.last, kAvaPlayStoreUrl);
  });

  test('CTA матни эга берган таҳрирда', () {
    expect(
      kAvaShareCta,
      '👉 АВАга ўтинг! Фойдали видеолар, керакли хизматлар ва эълонлар — '
      'барчаси бир жойда. Сизга кераклиси ҳам шу ерда!',
    );
  });

  test('Play ҳаволаси — AVA Zona пакети, market:// эмас', () {
    expect(kAvaPlayStoreUrl, contains('id=uz.ava.gurlan'));
    expect(kAvaPlayStoreUrl, startsWith('https://play.google.com/'));
    expect(kAvaAndroidPackage, 'uz.ava.gurlan');
  });

  test('улашиш матнида клип саҳифаси ҳаволаси йўқ (оралиқ қадам олиб ташланди)',
      () {
    expect(kAvaShareMessage, isNot(contains('/clip/')));
  });
}
