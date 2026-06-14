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
    required this.lastUpdate,
    this.messages = const [],
    this.driverStatus = '',
    this.driverTaxiType = '',
    this.unread = false,
  });

  final MessageThreadKind kind;
  final String id;
  final String title;
  final String subtitle;
  final DateTime lastUpdate;
  final List<NewsItem> messages;
  final String driverStatus;
  final String driverTaxiType;
  final bool unread;

  NewsItem? get latestNews =>
      messages.isEmpty ? null : messages.last;

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
        return '🛒 Сотиш таклифи';
      case 'identity_request':
        return '🪪 Шахсий маълумот';
      case 'ad_moderation':
      case 'ad_published':
        return '📢 Эълон модерацияси';
      default:
        return '📩 Хабар';
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
      'approved' => '✅ Ҳайдовчи аризаси — тасдиқ',
      'rejected' => '❌ Ҳайдовчи аризаси — рад',
      'revoked' => '⚠️ Ҳайдовчи рухсати бекор',
      _ => '🚕 Ҳайдовчи аризаси',
    };
    final reason = (data['rejectedReason'] ?? data['revokedReason'] ?? '')
        as String;
    final subtitle = reason.trim().isNotEmpty
        ? reason.trim()
        : 'Статус: $status · $taxiType';
    return MessageThreadGroup(
      kind: MessageThreadKind.driverRequest,
      id: 'driver:$uid',
      title: title,
      subtitle: subtitle,
      lastUpdate: updated,
      driverStatus: status,
      driverTaxiType: taxiType,
    );
  }
}
