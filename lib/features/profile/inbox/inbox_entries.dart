import '../../../models/message_thread_group.dart';
import '../../../models/news_item.dart';
import '../../../models/order_news_group.dart';
import '../../../repositories/chat_repository.dart' show SupportChatMeta;
import '../../deal_chat/data/deal_chat_repository.dart';
import '../inbox_hide_keys.dart';
import 'inbox_read_store.dart';

/// «Хабарлар» — битта рўйхат + тепадаги филтрлар (эга, 2026-11-02: «Барчаси ·
/// Чатлар · Буюртмалар · Янгиликлар»; аввал 3 та таб эди).
enum InboxFilter { all, chats, orders, news }

enum InboxKind { support, deal, dialog, driver, order, news }

/// Ўқилганлик бўлимлари (сервердаги `last…ReadAt` майдонлари билан бир хил маъно).
abstract final class InboxFeed {
  static const messages = 'messages';
  static const orders = 'orders';
  static const news = 'news';
  static const all = [messages, orders, news];
}

/// Барча манбалар — бир лаҳзадаги ҳолат.
class InboxData {
  const InboxData({
    this.broadcast = const [],
    this.dialog = const [],
    this.orders = const [],
    this.support = SupportChatMeta.empty,
    this.driver,
    this.deals = const [],
    this.hidden = const {},
  });

  final List<NewsItem> broadcast;
  final List<NewsItem> dialog;
  final List<NewsItem> orders;
  final SupportChatMeta support;
  final Map<String, dynamic>? driver;
  final List<DealChat> deals;

  /// `users/{uid}/dismissed_news` (ўчирилганлар) + шу сессияда ўчирилганлар.
  final Set<String> hidden;
}

/// Рўйхат қатори.
class InboxEntry {
  const InboxEntry({
    required this.key,
    required this.kind,
    required this.title,
    required this.preview,
    this.time,
    this.feed = '',
    this.unreadCount = 0,
    this.unread = false,
    this.pinned = false,
    this.photoUrl = '',
    this.category = '',
    this.orderType = '',
    this.dismissIds = const [],
    this.payload,
  });

  /// Барқарор калит (ўқилганлик, `ValueKey`).
  final String key;
  final InboxKind kind;
  final String title;
  final String preview;
  final DateTime? time;

  /// [InboxFeed] — ўқилганлик бўлими (чат/буюртма-чатлари учун бўш: улар серверда).
  final String feed;

  /// Сонли белги (чатлар). 0 бўлса ва [unread] — фақат нуқта.
  final int unreadCount;
  final bool unread;

  /// Тепага маҳкамланган («AVA ёрдам»).
  final bool pinned;
  final String photoUrl;

  /// Янгилик тури (`emergency`, `promo` …) — белги ранги.
  final String category;
  final String orderType;

  /// Суриб ўчирилганда `dismissNews`га бериладиган ID'лар. Бўш — ўчириб бўлмайди
  /// (буюртма чатлари: серверда ўчириш йўқ; «AVA ёрдам» — алоҳида «тарихни тозалаш»).
  final List<String> dismissIds;

  /// Очиш учун: [MessageThreadGroup] / [OrderNewsGroup] / [NewsItem] / [DealChat].
  final Object? payload;

  bool get isBold => unread || unreadCount > 0;

  bool get canDismiss => dismissIds.isNotEmpty || kind == InboxKind.support;

  InboxFilter get filter => switch (kind) {
        InboxKind.order => InboxFilter.orders,
        InboxKind.news => InboxFilter.news,
        _ => InboxFilter.chats,
      };
}

/// Матнлар учун (тестда калитнинг ўзи қайтади).
typedef InboxTr = String Function(String key);

/// Манбалардан тартибланган рўйхат: «AVA ёрдам» доим тепада, қолгани вақт бўйича.
List<InboxEntry> buildInboxEntries(
  InboxData d, {
  required String uid,
  required InboxReadStore read,
  required InboxTr tr,
}) {
  final hidden = d.hidden;
  final out = <InboxEntry>[];

  // ── AVA ёрдам (support чат) ──
  final clearedAt = InboxHideKeys.supportChatClearedAt(hidden);
  final s = d.support;
  final visible = s.lastMessage.trim().isNotEmpty &&
      InboxHideKeys.visibleAfterClear(s.updatedAt, clearedAt);
  out.add(InboxEntry(
    key: 'support',
    kind: InboxKind.support,
    title: tr('inbox_support_title'),
    preview: visible
        ? (s.lastFromAdmin ? s.lastMessage.trim() : '${tr('deal_chat_you')} ${s.lastMessage.trim()}')
        : tr('inbox_support_hint'),
    time: visible ? s.updatedAt : null,
    unreadCount: s.lastFromAdmin && visible ? 1 : 0,
    pinned: true,
  ));

  // ── Буюртма чатлари (ҳар бири алоҳида қатор) ──
  for (final c in d.deals) {
    final mine = c.lastFrom == uid;
    final who = mine
        ? tr('deal_chat_you')
        : '${tr(c.isSeller(uid) ? 'deal_chat_role_buyer' : 'deal_chat_role_seller')}:';
    out.add(InboxEntry(
      key: 'deal:${c.id}',
      kind: InboxKind.deal,
      title: c.productTitle.isNotEmpty ? c.productTitle : tr('deal_chats_title'),
      preview: c.lastMessage.isEmpty ? '' : '$who ${c.lastMessage}',
      time: c.lastAt,
      unreadCount: c.unreadFor(uid),
      photoUrl: c.productPhoto,
      payload: c,
    ));
  }

  // ── Мурожаат жавоблари (admin_news диалог) ──
  final dialog = d.dialog.where((n) => !hidden.contains(n.id)).toList();
  for (final g in MessageThreadGroup.fromDialogNews(dialog)) {
    final key = 'dialog:${g.id}';
    out.add(InboxEntry(
      key: key,
      kind: InboxKind.dialog,
      feed: InboxFeed.messages,
      title: tr(g.title),
      preview: g.subtitleText(tr),
      time: g.lastUpdate,
      unread: read.isUnread(feed: InboxFeed.messages, key: key, latest: g.lastUpdate),
      dismissIds: g.messages.map((m) => m.id).toList(),
      payload: g,
    ));
  }

  // ── Ҳайдовчи аризаси ──
  final drv = d.driver;
  if (drv != null) {
    final hideKey = InboxHideKeys.driverRequest(drv);
    final g = hidden.contains(hideKey) ? null : MessageThreadGroup.fromDriverRequest(drv, uid);
    if (g != null) {
      out.add(InboxEntry(
        key: 'driver',
        kind: InboxKind.driver,
        feed: InboxFeed.messages,
        title: tr(g.title),
        preview: g.subtitleText(tr),
        time: g.lastUpdate,
        // Ҳолат ўзгарса `lastUpdate` янгиланади — қатор яна жирний.
        unread: read.isUnread(feed: InboxFeed.messages, key: 'driver', latest: g.lastUpdate),
        dismissIds: [hideKey],
        payload: g,
      ));
    }
  }

  // ── Буюртмалар ──
  final orders = d.orders.where((n) => !hidden.contains(n.id)).toList();
  for (final g in OrderNewsGroup.fromItems(orders)) {
    final latest = g.latestMessage;
    final key = 'order:${g.orderId.isEmpty ? latest.id : g.orderId}';
    final status = orderStatusKey(latest.orderStatus);
    out.add(InboxEntry(
      key: key,
      kind: InboxKind.order,
      feed: InboxFeed.orders,
      title: tr(g.moduleLabelKey),
      preview: latest.title.trim().isNotEmpty
          ? latest.title.trim()
          : (status == null ? latest.orderStatus : tr(status)),
      time: g.lastUpdate,
      unread: read.isUnread(feed: InboxFeed.orders, key: key, latest: g.lastUpdate),
      orderType: g.orderType,
      dismissIds: g.messages.map((m) => m.id).toList(),
      payload: g,
    ));
  }

  // ── Умумий янгиликлар ──
  for (final n in d.broadcast) {
    if (hidden.contains(n.id)) continue;
    final key = 'news:${n.id}';
    final body = n.body.trim().split('\n').first.trim();
    out.add(InboxEntry(
      key: key,
      kind: InboxKind.news,
      feed: InboxFeed.news,
      title: n.title.trim().isNotEmpty ? n.title.trim() : body,
      preview: n.title.trim().isNotEmpty ? body : '',
      time: n.createdAt,
      unread: read.isUnread(feed: InboxFeed.news, key: key, latest: n.createdAt),
      category: n.category,
      dismissIds: [n.id],
      payload: n,
    ));
  }

  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  out.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    return (b.time ?? epoch).compareTo(a.time ?? epoch);
  });
  return out;
}

/// Буюртма статуси → l10n калити (номаълум — `null`, хом статус кўрсатилмайди).
String? orderStatusKey(String s) => switch (s) {
      'new' => 'sent',
      'accepted' => 'news_st_accepted',
      'ready' => 'news_st_ready',
      'in_delivery' => 'order_status_in_delivery',
      'delivered' => 'news_st_delivered',
      'rejected' => 'news_st_rejected',
      'cancelled' => 'order_status_cancelled',
      _ => null,
    };

/// Филтр + қидирув.
List<InboxEntry> filterInbox(List<InboxEntry> all, InboxFilter f, String query) {
  final q = query.trim().toLowerCase();
  return all.where((e) {
    if (f != InboxFilter.all && e.filter != f) return false;
    if (q.isEmpty) return true;
    return e.title.toLowerCase().contains(q) || e.preview.toLowerCase().contains(q);
  }).toList();
}

/// Филтр чипидаги сон: чатлар — ўқилмаган ХАБАРЛАР сони (+ белгили қаторлар),
/// буюртма/янгилик — ўқилмаган ҚАТОРЛАР сони. «Барчаси» — сон йўқ.
int inboxFilterCount(List<InboxEntry> all, InboxFilter f) {
  if (f == InboxFilter.all) return 0;
  var n = 0;
  for (final e in all) {
    if (e.filter != f) continue;
    n += e.unreadCount > 0 ? e.unreadCount : (e.unread ? 1 : 0);
  }
  return n;
}
