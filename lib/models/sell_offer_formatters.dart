import '../core/utils/formatters.dart';
import 'sell_offer_item.dart';

/// Сотиш таклифини «Сотаман» эълони матнига айлантириш.
class SellOfferFormatters {
  SellOfferFormatters._();

  static String adTitle(List<SellOfferItem> items) {
    if (items.isEmpty) return 'Сотаман';
    if (items.length == 1) return 'Сотаман: ${items.first.productName}';
    return 'Сотаман: ${items.length} ta mahsulot';
  }

  static String adBody(List<SellOfferItem> items) {
    final buf = StringBuffer();
    for (final it in items) {
      buf.writeln(
        '• ${it.productName}: ${it.quantityText} — '
        '${formatPrice(it.priceOffered)} сўм',
      );
    }
    return buf.toString().trim();
  }

  static String adPriceSummary(List<SellOfferItem> items) {
    if (items.isEmpty) return '';
    if (items.length == 1) {
      return '${formatPrice(items.first.priceOffered)} сўм';
    }
    var min = items.first.priceOffered;
    var max = items.first.priceOffered;
    for (final it in items.skip(1)) {
      if (it.priceOffered < min) min = it.priceOffered;
      if (it.priceOffered > max) max = it.priceOffered;
    }
    if (min == max) return '${formatPrice(min)} сўм';
    return '${formatPrice(min)} – ${formatPrice(max)} сўм';
  }
}
