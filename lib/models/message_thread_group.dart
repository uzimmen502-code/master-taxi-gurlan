import 'package:cloud_firestore/cloud_firestore.dart';

import 'news_item.dart';

/// «Хабарлар» таби — битта мурожаат/чат темаси.
enum MessageThreadKind {
  supportChat,
  dialogNews,
  driverRequest,
}

class MessageThreadGroup {
  const MessageThreadGroup({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    this.subtitleKey = '',
    required this.lastUpdate,
    this.messages = const [],
    this.driverStatus = '',
    this.driverTaxiType = '',
    this.unread = false,
  });

  final MessageThreadKind kind;
  final String id;

  /// l10n KALITI (ekranda `context.tr(title)`).
  final String title;

  /// Server/foydalanuvchi matni (xabar sarlavhasi, rad sababi) — o'zgarishsiz.
  final String subtitle;

  /// Bo'sh bo'lmasa — [subtitle] o'rniga ko'rsatiladigan l10n kaliti.
  final String subtitleKey;
  final DateTime lastUpdate;
  final List<NewsItem> messages;
  final String driverStatus;
  final String driverTaxiType;
  final bool unread;

  NewsItem? get latestNews =>
      messages.isEmpty ? null : messages.last;

  /// Ekranga chiqadigan sarlavha ostidagi matn ([tr] — `context.tr`).
  String subtitleText(String Function(String key) tr) =>
      subtitleKey.isNotEmpty ? tr(subtitleKey) : subtitle;

  static List<MessageThreadGroup> fromDialogNews(List<NewsItem> items) {
    final map = <String, List<NewsItem>>{};
    for (final n in items) {
      if (!n.isDialogNews) continue;
      map.putIfAbsent(n.threadKey, () => []).add(n);
    }
    final groups = map.entries.map((e) {
      final msgs = e.value
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final latest = msgs.last;
      return MessageThreadGroup(
        kind: MessageThreadKind.dialogNews,
        id: e.key,
        title: _dialogTitle(latest),
        subtitle: latest.title.isNotEmpty ? latest.title : latest.body,
        lastUpdate: latest.createdAt,
        messages: msgs,
      );
    }).toList();
    groups.sort((a, b) => b.lastUpdate.compareTo(a.lastUpdate));
    return groups;
  }

  static String _dialogTitle(NewsItem n) {
    switch (n.source) {
      case 'sell_offer':
      case 'sell_offer_forward':
        return 'mdl_thread_sell_offer';
      case 'identity_request':
        return 'mdl_thread_identity';
      case 'ad_moderation':
      case 'ad_published':
        return 'mdl_thread_ad_moderation';
      default:
        return 'mdl_thread_generic';
    }
  }

  static MessageThreadGroup? fromDriverRequest(
    Map<String, dynamic>? data,
    String uid,
  ) {
    if (data == null) return null;
    final status = (data['status'] ?? 'pending') as String;
    final taxiType = (data['taxiType'] ?? '') as String;
    final updated = (data['updatedAt'] as Timestamp?)?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate() ??
        DateTime.now();
    final title = switch (status) {
      'approved' => 'mdl_thread_drv_approved',
      'rejected' => 'mdl_thread_drv_rejected',
      'revoked' => 'mdl_thread_drv_revoked',
      _ => 'mdl_thread_drv_default',
    };
    final reason = (data['rejectedReason'] ?? data['revokedReason'] ?? '')
        as String;
    final hasReason = reason.trim().isNotEmpty;
    final subtitleKey = switch (status) {
      'approved' => 'mdl_thread_drv_sub_approved',
      'rejected' => 'mdl_thread_drv_sub_rejected',
      'revoked' => 'mdl_thread_drv_sub_revoked',
      _ => 'mdl_thread_drv_sub_pending',
    };
    return MessageThreadGroup(
      kind: MessageThreadKind.driverRequest,
      id: 'driver:$uid',
      title: title,
      subtitle: hasReason ? reason.trim() : '',
      subtitleKey: hasReason ? '' : subtitleKey,
      lastUpdate: updated,
      driverStatus: status,
      driverTaxiType: taxiType,
    );
  }
}
