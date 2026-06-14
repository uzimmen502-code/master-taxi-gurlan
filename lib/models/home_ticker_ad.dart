import 'package:cloud_firestore/cloud_firestore.dart';

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
    this.activeFrom,
    this.activeTo,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String text;
  /// `all` | `user` | `driver` | `courier` | `admin`
  final String audience;
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
      audience: (d['audience'] ?? 'all').toString(),
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
    String? audience,
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
      audience: audience ?? this.audience,
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
      'audience': audience,
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
      'audience': audience,
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
