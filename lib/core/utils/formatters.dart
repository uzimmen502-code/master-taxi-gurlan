/// Loyihada keng ishlatiladigan format/parse helperlari.
///
/// Avval har bir screen ichida takrorlanardi (`_digits`, `_fmtPrice`,
/// `_monthName`, `_phoneAliases`). Endi yagona joyda.
library;

/// "+998 (90) 123-45-67" -> "998901234567"
String phoneDigits(String v) => v.replaceAll(RegExp(r'[^\d]'), '');

/// `notifications.targetPhone` ва FCM listener учун каноник формат (фақат рақамлар).
String notificationTargetPhone(String raw) {
  final d = phoneDigits(raw);
  return d.length >= 9 ? d : raw.trim();
}

/// Икки телефон бир хилми (форматдан қатъи назар).
bool phonesMatch(String a, String b) {
  final ka = phoneMatchKey(a);
  final kb = phoneMatchKey(b);
  if (ka.length >= 9 && kb.length >= 9) return ka == kb;
  return a.trim() == b.trim();
}

/// Сўроқ / ўқилмаган ҳисоб учун барқарор калит (охирги 9 рақам).
String phoneMatchKey(String raw) {
  final d = phoneDigits(raw);
  if (d.length >= 9) return d.substring(d.length - 9);
  return d;
}

/// Firestore `targetUserId` / `users` doc id — бир xil формат.
String canonicalPhoneId(String raw) {
  final d = phoneDigits(raw);
  if (d.length == 9) return '998$d';
  if (d.length >= 12 && d.startsWith('998')) return d;
  return d;
}

/// Phone number for tel: URI, SMS, WhatsApp
/// Always returns +998XXXXXXXXX format
String phoneForCall(String raw) {
  final digits = phoneDigits(raw);
  if (digits.length == 9) return '+998$digits';
  if (digits.length == 12 && digits.startsWith('998')) {
    return '+$digits';
  }
  return '+$digits';
}

/// `tel:` qo'ng'iroq URI учун E.164'га яқин формат (`+998...`).
/// Noto'g'ri/yetarli bo'lmagan raqam bo'lsa bo'sh satr qaytaradi.
String phoneForTelUri(String raw) {
  final canonical = canonicalPhoneId(raw);
  final d = phoneDigits(canonical);
  if (d.length < 12) return '';
  return '+$d';
}

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
    if (d.length >= 12 && d.startsWith('998')) {
      aliases.add(d.substring(3));
    }
    if (d.length == 9) {
      aliases.add('998$d');
    }
  }
  return aliases.take(10).toList();
}

/// `users/{docId}` — телефон турли форматда сақланган бўлиши мумкин.
List<String> userDocIdCandidates(String raw) {
  final d = phoneDigits(raw);
  final canon = canonicalPhoneId(raw);
  final ids = <String>{canon, d};
  if (d.length >= 12 && d.startsWith('998')) {
    ids.add(d.substring(3));
  }
  if (d.length == 9) {
    ids.add('998$d');
  }
  return ids.where((id) => phoneDigits(id).length >= 9).toList(growable: false);
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

/// Kun tanlash kartasi: `10.06.2026 y`
String formatPickDateLabel(DateTime d, {String yearSuffix = ' y'}) {
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}$yearSuffix';
}

/// DateTime → "DD.MM HH:MM" (нон тарихи каби қисқа форматлар учун).
String formatDateShort(DateTime? d) {
  if (d == null) return '';
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

/// `1990-05-15` yoki `15.05.1990` → [DateTime]. Noto'g'ri bo'lsa `null`.
DateTime? parseBirthDate(String birthDate) {
  final trimmed = birthDate.trim();
  if (trimmed.isEmpty) return null;

  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(trimmed);
  if (iso != null) {
    final y = int.tryParse(iso.group(1)!);
    final mo = int.tryParse(iso.group(2)!);
    final d = int.tryParse(iso.group(3)!);
    if (y != null && mo != null && d != null) {
      try {
        final parsed = DateTime(y, mo, d);
        if (parsed.year == y && parsed.month == mo && parsed.day == d) {
          return parsed;
        }
      } catch (_) {}
    }
  }

  final dot = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(trimmed);
  if (dot != null) {
    final d = int.tryParse(dot.group(1)!);
    final mo = int.tryParse(dot.group(2)!);
    final y = int.tryParse(dot.group(3)!);
    if (y != null && mo != null && d != null) {
      try {
        final parsed = DateTime(y, mo, d);
        if (parsed.year == y && parsed.month == mo && parsed.day == d) {
          return parsed;
        }
      } catch (_) {}
    }
  }

  return null;
}

/// Tug'ilgan sana → yosh (butun son). Noto'g'ri bo'lsa `null`.
int? ageFromBirthDate(String birthDate) {
  final born = parseBirthDate(birthDate);
  if (born == null) return null;
  final now = DateTime.now();
  var age = now.year - born.year;
  if (now.month < born.month ||
      (now.month == born.month && now.day < born.day)) {
    age--;
  }
  if (age < 0 || age > 120) return null;
  return age;
}
