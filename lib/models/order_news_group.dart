import 'news_item.dart';

/// Битта буюртмага тегишли барча статус хабарлари.
class OrderNewsGroup {
  const OrderNewsGroup({
    required this.orderId,
    required this.messages,
    required this.orderType,
  });

  final String orderId;
  final List<NewsItem> messages;
  final String orderType;

  DateTime get lastUpdate =>
      messages.map((m) => m.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);

  NewsItem get latestMessage {
    final sorted = [...messages]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return sorted.last;
  }

  String get moduleLabel {
    switch (orderType) {
      case 'food':
        return 'Тайёр овқат';
      case 'bread':
        return 'Нон буюртма';
      default:
        return 'Буюртма';
    }
  }

  /// `orderId`сиз буюртма хабари (масалан йиғим чеки) — ўз картаси. Аввал
  /// ташлаб юбориларди, лекин таб badge'ида саналарди: мижоз «1 та янги»
  /// кўрар, очганда ҳеч нарса топмасди.
  static const _standalonePrefix = 'news:';

  static List<OrderNewsGroup> fromItems(List<NewsItem> items) {
    final map = <String, List<NewsItem>>{};
    for (final n in items) {
      if (!n.isOrderNews) continue;
      final id = n.orderId.trim();
      final key = id.isEmpty ? '$_standalonePrefix${n.id}' : id;
      map.putIfAbsent(key, () => []).add(n);
    }
    final groups = map.entries.map((e) {
      final msgs = e.value
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      // Тур — тури ёзилган энг сўнгги хабардан: чек/курьер хабарида тур
      // йўқ, улар охирги бўлса буюртма «Нон» бўлиб қоларди.
      final typed = msgs.lastWhere(
        (m) => m.orderType.isNotEmpty,
        orElse: () => msgs.last,
      );
      final type = typed.orderType.isNotEmpty
          ? typed.orderType
          : (typed.body.contains('овқат') ? 'food' : 'bread');
      final standalone = e.key.startsWith(_standalonePrefix);
      return OrderNewsGroup(
        orderId: standalone ? '' : e.key,
        messages: msgs,
        orderType: standalone && typed.orderType.isEmpty ? '' : type,
      );
    }).toList();
    groups.sort((a, b) => b.lastUpdate.compareTo(a.lastUpdate));
    return groups;
  }
}
