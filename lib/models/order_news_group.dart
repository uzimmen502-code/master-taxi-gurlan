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

  static List<OrderNewsGroup> fromItems(List<NewsItem> items) {
    final map = <String, List<NewsItem>>{};
    for (final n in items) {
      if (!n.isOrderNews) continue;
      final id = n.orderId.trim();
      if (id.isEmpty) continue;
      map.putIfAbsent(id, () => []).add(n);
    }
    final groups = map.entries.map((e) {
      final msgs = e.value
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final type = msgs.last.orderType.isNotEmpty
          ? msgs.last.orderType
          : (msgs.last.body.contains('овқат') ? 'food' : 'bread');
      return OrderNewsGroup(
        orderId: e.key,
        messages: msgs,
        orderType: type,
      );
    }).toList();
    groups.sort((a, b) => b.lastUpdate.compareTo(a.lastUpdate));
    return groups;
  }
}
