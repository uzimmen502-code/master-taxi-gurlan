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

/// [template] — `icx_alert_body` l10n matni (`{name}` `{route}` `{passengers}`
/// `{price}` `{phone}` o'rinbosarlari bilan); kontekstsiz joyda
/// `OfflineL10n.tr('icx_alert_body')` orqali olinadi.
String intercityDriverBookingAlertBody({
  required String template,
  required String userName,
  required String routeLabel,
  required int passengers,
  required String userPhone,
  String? pricePart,
}) {
  final phone = formatPhoneForCallHint(userPhone);
  final price = pricePart ?? '';
  return template
      .replaceAll('{name}', userName)
      .replaceAll('{route}', routeLabel)
      .replaceAll('{passengers}', '$passengers')
      .replaceAll('{price}', price)
      .replaceAll('{phone}', phone);
}
