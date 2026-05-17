/// Loyihada keng ishlatiladigan format/parse helperlari.
///
/// Avval har bir screen ichida takrorlanardi (`_digits`, `_fmtPrice`,
/// `_monthName`, `_phoneAliases`). Endi yagona joyda.
library;

/// "+998 (90) 123-45-67" -> "998901234567"
String phoneDigits(String v) => v.replaceAll(RegExp(r'[^\d]'), '');

/// Firestore'da telefon turli formatlarda yozilgan bo'lishi mumkin.
/// Shu sababli `whereIn` so'rovi uchun barcha ehtimoliy variantlarni qaytaramiz.
List<String> phoneAliases(String raw) {
  final t = raw.trim();
  final d = phoneDigits(raw);
  final aliases = <String>{};
  if (t.isNotEmpty) aliases.add(t);
  final compact = t.replaceAll(' ', '');
  if (compact.isNotEmpty) aliases.add(compact);
  if (d.isNotEmpty) {
    aliases.add(d);
    aliases.add('+$d');
  }
  return aliases.take(10).toList();
}

/// 1234567 -> "1 234 567"
String formatPrice(num p) {
  final s = p.toInt().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

const _monthNames = <String>[
  '', 'янв', 'фев', 'мар', 'апр', 'май', 'июн',
  'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
];

String monthNameUz(int month) =>
    (month >= 1 && month <= 12) ? _monthNames[month] : '';

/// DateTime → "DD.MM HH:MM" (нон тарихи каби қисқа форматлар учун).
String formatDateShort(DateTime? d) {
  if (d == null) return '';
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}
