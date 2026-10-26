import 'package:cloud_firestore/cloud_firestore.dart';

import '../features/ads/utils/ad_search_text.dart';
import 'home_ticker_animation_style.dart';

/// Bosh ekran — duo ostidagi begushchaya reklama qatori.
class HomeTickerAd {
  const HomeTickerAd({
    required this.id,
    required this.text,
    required this.audience,
    required this.durationSec,
    required this.scrollSpeed,
    required this.animationStyle,
    required this.fontSize,
    required this.priority,
    required this.active,
    this.module = 'home_search',
    this.textLatn = '',
    this.textRu = '',
    this.activeFrom,
    this.activeTo,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// Кирилл (uz_Cyrl) матн — асосий, мажбурий; эски иловалар фақат шуни ўқийди.
  final String text;

  /// Лотин (uz_Latn) ва рус матни — ихтиёрий (2026-10-26, эга: «фақат (2) тузат»). Бўш бўлса [textFor]
  /// ўрнини тўлдиради: лотинга кирилл матн автоматик ўгирилади, русчада кирилл матн кўрсатилади.
  final String textLatn;
  final String textRu;
  /// `all` | `user` | `driver` | `courier` | `admin`
  final String audience;
  /// Qaysi ekranda ko'rsatiladi: `home_search` (bosh ekran ma'lumot maydoni).
  final String module;
  /// Bir matn necha soniya ekranda qoladi (keyingisiga o'tish).
  final int durationSec;
  /// Marquee: px/sek; boshqalar: harf tezligi (qiymat oshsa tezroq).
  final int scrollSpeed;
  /// [HomeTickerAnimationStyle] qiymati.
  final String animationStyle;
  final int fontSize;
  final int priority;
  final bool active;
  final DateTime? activeFrom;
  final DateTime? activeTo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const int defaultDurationSec = 12;
  static const int defaultScrollSpeed = 45;
  static const int defaultFontSize = 13;

  factory HomeTickerAd.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return HomeTickerAd(
      id: doc.id,
      text: (d['text'] ?? '').toString().trim(),
      textLatn: (d['textLatn'] ?? '').toString().trim(),
      textRu: (d['textRu'] ?? '').toString().trim(),
      audience: (d['audience'] ?? 'all').toString(),
      module: (d['module'] ?? 'home_search').toString(),
      durationSec: ((d['durationSec'] as num?)?.toInt() ?? defaultDurationSec)
          .clamp(5, 120),
      scrollSpeed: ((d['scrollSpeed'] as num?)?.toInt() ?? defaultScrollSpeed)
          .clamp(15, 120),
      animationStyle: HomeTickerAnimationStyle.normalizeManual(
        d['animationStyle'] as String?,
      ),
      fontSize: ((d['fontSize'] as num?)?.toInt() ?? defaultFontSize)
          .clamp(10, 24),
      priority: ((d['priority'] as num?)?.toInt() ?? 0),
      active: d['active'] == true,
      activeFrom: (d['activeFrom'] as Timestamp?)?.toDate(),
      activeTo: (d['activeTo'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  HomeTickerAd copyWith({
    String? id,
    String? text,
    String? textLatn,
    String? textRu,
    String? audience,
    String? module,
    int? durationSec,
    int? scrollSpeed,
    String? animationStyle,
    int? fontSize,
    int? priority,
    bool? active,
    DateTime? activeFrom,
    DateTime? activeTo,
    bool clearActiveFrom = false,
    bool clearActiveTo = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HomeTickerAd(
      id: id ?? this.id,
      text: text ?? this.text,
      textLatn: textLatn ?? this.textLatn,
      textRu: textRu ?? this.textRu,
      audience: audience ?? this.audience,
      module: module ?? this.module,
      durationSec: durationSec ?? this.durationSec,
      scrollSpeed: scrollSpeed ?? this.scrollSpeed,
      animationStyle: animationStyle ?? this.animationStyle,
      fontSize: fontSize ?? this.fontSize,
      priority: priority ?? this.priority,
      active: active ?? this.active,
      activeFrom: clearActiveFrom ? null : (activeFrom ?? this.activeFrom),
      activeTo: clearActiveTo ? null : (activeTo ?? this.activeTo),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toCreateMap() {
    return {
      'text': text,
      if (textLatn.isNotEmpty) 'textLatn': textLatn,
      if (textRu.isNotEmpty) 'textRu': textRu,
      'audience': audience,
      'module': module,
      'active': active,
      'priority': priority,
      'durationSec': durationSec,
      'scrollSpeed': scrollSpeed,
      'animationStyle':
          animationStyle.isEmpty ? HomeTickerAnimationStyle.auto : animationStyle,
      'fontSize': fontSize,
      if (activeFrom != null) 'activeFrom': Timestamp.fromDate(activeFrom!),
      if (activeTo != null) 'activeTo': Timestamp.fromDate(activeTo!),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'text': text,
      'textLatn': textLatn.isNotEmpty ? textLatn : FieldValue.delete(),
      'textRu': textRu.isNotEmpty ? textRu : FieldValue.delete(),
      'audience': audience,
      'module': module,
      'active': active,
      'priority': priority,
      'durationSec': durationSec,
      'scrollSpeed': scrollSpeed,
      'animationStyle':
          animationStyle.isEmpty ? HomeTickerAnimationStyle.auto : animationStyle,
      'fontSize': fontSize,
      if (activeFrom != null)
        'activeFrom': Timestamp.fromDate(activeFrom!)
      else
        'activeFrom': FieldValue.delete(),
      if (activeTo != null)
        'activeTo': Timestamp.fromDate(activeTo!)
      else
        'activeTo': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Илова тилидаги матн (`context.contentLang`): `uz_Latn` — [textLatn] ёки кирилл матндан автоматик ўгирилгани
  /// (баннер катта ҳарфда кўрсатади, ўгирувчининг кичик ҳарфи муҳим эмас); `ru` — [textRu] ёки кирилл; бошқаси — [text].
  String textFor(String lang) {
    switch (lang) {
      case 'uz_Latn':
        return textLatn.isNotEmpty ? textLatn : AdSearchText.toLatin(text);
      case 'ru':
        return textRu.isNotEmpty ? textRu : text;
      default:
        return text;
    }
  }

  bool isVisibleForRole(String role) {
    final aud = audience;
    if (aud == 'all') return true;
    if (aud == 'admin') {
      return role == 'admin' || role == 'superadmin';
    }
    return aud == role;
  }

  bool isVisibleNow([DateTime? now]) {
    final t = now ?? DateTime.now();
    if (activeFrom != null && t.isBefore(activeFrom!)) return false;
    if (activeTo != null && t.isAfter(activeTo!)) return false;
    return true;
  }
}
