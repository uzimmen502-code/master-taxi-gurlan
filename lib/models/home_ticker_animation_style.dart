/// Bosh ekran begushchaya qator animatsiya turlari.
abstract final class HomeTickerAnimationStyle {
  static const auto = 'auto';
  static const marquee = 'marquee';
  static const typewriter = 'typewriter';
  static const cascade = 'cascade';
  static const fadeIn = 'fade_in';
  static const slideIn = 'slide_in';

  /// Matn ekran ichida qoladi (FittedBox + clip) — yangi uslublar.
  static const fitFade = 'fit_fade';
  static const fitLines = 'fit_lines';
  static const fitWords = 'fit_words';
  static const fitPulse = 'fit_pulse';
  static const fitPop = 'fit_pop';

  static const manualAll = [
    marquee,
    typewriter,
    cascade,
    fadeIn,
    slideIn,
    fitFade,
    fitLines,
    fitWords,
    fitPulse,
    fitPop,
  ];
  static const all = [auto, ...manualAll];

  static bool isAuto(String? raw) {
    final v = (raw ?? '').trim();
    return v.isEmpty || v == auto;
  }

  static bool isFitOnScreen(String? raw) {
    final v = normalizeManual(raw);
    return v == fitFade ||
        v == fitLines ||
        v == fitWords ||
        v == fitPulse ||
        v == fitPop;
  }

  static String normalizeManual(String? raw) {
    final v = (raw ?? auto).trim();
    if (isAuto(v)) return auto;
    return manualAll.contains(v) ? v : marquee;
  }

  /// Eski `normalize` — avtomatik rejimda ham fallback.
  static String normalize(String? raw) => normalizeManual(raw);

  static String label(String style) => switch (normalizeManual(style)) {
        auto => 'Автоматик (тавсия)',
        marquee => 'Югурувчи (klassik)',
        typewriter => 'Ҳарфма-ҳарф (машина ёзуви)',
        cascade => 'Ҳарфлар қатори (ўнгдан)',
        fadeIn => 'Аста пайдо бўлиш',
        slideIn => 'Матн ўнгдан кириб келиш',
        fitFade => 'Экранга sigʻish — аста пайдо',
        fitLines => 'Экранга sigʻish — қаторма-қатор',
        fitWords => 'Экранга sigʻish — сўзма-сўз',
        fitPulse => 'Экранга sigʻish — нур пульс',
        fitPop => 'Экранга sigʻish — чиқиш (pop)',
        _ => style,
      };

  static String description(String style) => switch (normalizeManual(style)) {
        auto =>
          'Qisqa matn — harf animatsiyasi; uzun — ko\'p qator yoki scroll',
        marquee => 'Matn o\'ngdan chapga uzluksiz harakatlanadi',
        typewriter => 'Birinchi harf, keyin ikkinchi… to\'liq matn shakllanadi',
        cascade => 'Har bir harf o\'ngdan kirib, oldingisidan keyin to\'xtaydi',
        fadeIn => 'Butun matn sekin ko\'rinadi',
        slideIn => 'Butun qator o\'ng tomondan markazga siljiydi',
        fitFade =>
          'Matn shrifti kichraytiriladi, ekrandan chiqmaydi; sekin paydo bo\'ladi',
        fitLines =>
          '1-qator, 2-qator… ketma-ket; uzun matn 2–5 qatorga sig\'adi',
        fitWords =>
          'So\'zlar ketma-ket chiqadi; qatorlar ekran kengligida qoladi',
        fitPulse =>
          'To\'liq matn markazda, ekranga sig\'adi; yengil yorqinlik pulsatsiyasi',
        fitPop =>
          'Matn markazda kattalashib chiqadi; chegaradan tashqariga chiqmaydi',
        _ => '',
      };

  /// `scrollSpeed` bu uslubda qanday talqin qilinadi.
  static bool usesScrollPxPerSec(String style) {
    final s = normalizeManual(style);
    return s == marquee || s == auto;
  }
}
