import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';

/// Админ томонидан юбориладиган хабар/янгилик.
/// `admin_news` collection ҳужжати.
class NewsItem {
  const NewsItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.category = 'info',
    this.audience = 'all',
    this.imageUrl = '',
    this.ctaLabel = '',
    this.ctaUrl = '',
    this.priority = 0,
    this.targetUserId = '',
    this.source = '',
    this.orderId = '',
    this.orderStatus = '',
    this.orderType = '',
    this.pushSentCount,
    this.pushBroadcastAt,
    this.submissionId = '',
    this.requestId = '',
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  /// `info` | `update` | `promo` | `warning` | `emergency`
  final String category;

  /// Маqсадли аудитория: `all` (барча) | `user` | `driver` | `courier`.
  /// `NewsScreen._audiences()` — `[all, <role>]` — мана шу қиймaт билан мос.
  final String audience;

  final String imageUrl;
  final String ctaLabel;
  final String ctaUrl;

  /// 0 — оддий, 10 — энг муҳим (рўйхатда юқорида).
  final int priority;

  /// Мижозга шахсий хабар (телефон рақами, фақат рақамлар).
  final String targetUserId;

  /// `order_status` — буюртма статуси; бўш — админ қўлда юборган.
  final String source;

  final String orderId;
  final String orderStatus;

  /// `bread` | `food`
  final String orderType;

  /// FCM broadcast — nechta qurilmaga push yuborilgan (CF yozadi).
  final int? pushSentCount;

  /// Push yuborilgan vaqt (CF yozadi).
  final DateTime? pushBroadcastAt;

  /// `sell_submissions` / мурожаат идентификатори.
  final String submissionId;

  /// `driver_requests` ва бошқа сўровлар.
  final String requestId;

  /// Буюртма хабари (фақат «Буюртма» бўлимида).
  bool get isOrderNews =>
      source == 'order_status' ||
      source == 'order_placed' ||
      category == 'order';

  /// Ҳамён хабари (Хабарлар → Wallet таб).
  bool get isWalletNews =>
      category == 'wallet' || source.startsWith('wallet_');

  static const _broadcastSources = {'', 'admin_compose', 'broadcast'};

  /// Админ broadcast — «Янгилик» (қаттиқ фильтр).
  bool get isBroadcastNews {
    if (isOrderNews || isPersonal) return false;
    final s = source.trim();
    return _broadcastSources.contains(s);
  }

  /// Мурожаат / жавобли хабар — «Хабарлар» таби.
  bool get isDialogNews => !isOrderNews && !isBroadcastNews;

  /// Гуруҳлаш калити (Хабарлар рўйхати).
  String get threadKey {
    if (submissionId.trim().isNotEmpty) {
      return 'sub:${submissionId.trim()}';
    }
    if (requestId.trim().isNotEmpty) {
      return 'req:${requestId.trim()}';
    }
    return '$source:$id';
  }

  factory NewsItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return NewsItem(
      id: doc.id,
      title: (d['title'] ?? '') as String,
      body: (d['body'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      category: (d['category'] ?? 'info') as String,
      audience: (d['audience'] ?? 'all') as String,
      imageUrl: (d['imageUrl'] ?? '') as String,
      ctaLabel: (d['ctaLabel'] ?? '') as String,
      ctaUrl: (d['ctaUrl'] ?? '') as String,
      priority: (d['priority'] as num?)?.toInt() ?? 0,
      targetUserId: (d['targetUserId'] ?? '') as String,
      source: (d['source'] ?? '') as String,
      orderId: (d['orderId'] ?? '') as String,
      orderStatus: (d['orderStatus'] ?? '') as String,
      orderType: (d['orderType'] ?? '') as String,
      pushSentCount: (d['pushSentCount'] as num?)?.toInt(),
      pushBroadcastAt: (d['pushBroadcastAt'] as Timestamp?)?.toDate(),
      submissionId: (d['submissionId'] ?? '') as String,
      requestId: (d['requestId'] ?? '') as String,
    );
  }

  bool get isPersonal => targetUserId.replaceAll(RegExp(r'\D'), '').length >= 9;

  /// `onAdminNewsCreate` push yuboradigan хабарлар (автоматик system хабарлар эмас).
  bool get expectsPushFromAdmin =>
      !const {
        'order_status',
        'order_placed',
        'ad_moderation',
        'sell_offer',
        'identity_request',
        'system',
      }.contains(source);

  bool get hasPushStats =>
      pushBroadcastAt != null || pushSentCount != null;

  bool get pushPending {
    if (hasPushStats || !expectsPushFromAdmin) return false;
    return DateTime.now().difference(createdAt).inMinutes < 15;
  }

  bool isVisibleTo({
    required String userId,
    required List<String> audiences,
  }) {
    final uid = phoneMatchKey(userId);
    if (isPersonal) {
      return uid.length >= 9 && phonesMatch(targetUserId, userId);
    }
    return audiences.contains('all') || audiences.contains(audience);
  }

  Map<String, dynamic> toCreateMap() => {
        'title': title,
        'body': body,
        'category': category,
        'audience': audience,
        if (imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        if (ctaLabel.isNotEmpty) 'ctaLabel': ctaLabel,
        if (ctaUrl.isNotEmpty) 'ctaUrl': ctaUrl,
        'priority': priority,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
