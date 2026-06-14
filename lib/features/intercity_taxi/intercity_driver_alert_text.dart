import '../../core/utils/formatters.dart';

/// Ҳайдовчига янги брон push/диалог матни.
String formatPhoneForCallHint(String raw) {
  final d = phoneDigits(raw);
  if (d.length < 9) return raw.trim();
  if (d.length == 12 && d.startsWith('998')) {
    return '+${d.substring(0, 3)} '
        '${d.substring(3, 5)} '
        '${d.substring(5, 8)} '
        '${d.substring(8, 10)} '
        '${d.substring(10)}';
  }
  if (d.length == 9) {
    return '+998 ${d.substring(0, 2)} ${d.substring(2, 5)} ${d.substring(5, 7)} ${d.substring(7)}';
  }
  return '+$d';
}

String intercityDriverBookingAlertBody({
  required String userName,
  required String routeLabel,
  required int passengers,
  required String userPhone,
  String? pricePart,
}) {
  final phone = formatPhoneForCallHint(userPhone);
  final price = pricePart ?? '';
  return '$userName · $routeLabel · $passengers ўрин$price\n'
      '📞 Аввал йўловчига қўнғироқ қилинг: $phone';
}
