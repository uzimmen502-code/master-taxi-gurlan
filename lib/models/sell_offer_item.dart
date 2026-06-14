/// Битта сотиш таклифи (форма қатори).
class SellOfferItem {
  const SellOfferItem({
    required this.productName,
    required this.quantityText,
    required this.priceOffered,
    required this.isRecurring,
  });

  final String productName;
  /// Миқдор матнда (масалан: «5 кг», «20 дона»).
  final String quantityText;
  final int priceOffered;
  /// `true` — доимий таклиф; `false` — бир марта.
  final bool isRecurring;

  String get offerTypeLabel => isRecurring ? 'Доимий' : 'Бир марта';

  Map<String, dynamic> toMap() => {
        'productName': productName,
        'quantityText': quantityText,
        'priceOffered': priceOffered,
        'isRecurring': isRecurring,
      };

  factory SellOfferItem.fromMap(Map<String, dynamic> m) {
    return SellOfferItem(
      productName: (m['productName'] ?? '') as String,
      quantityText: (m['quantityText'] ?? '') as String,
      priceOffered: (m['priceOffered'] as num?)?.toInt() ?? 0,
      isRecurring: m['isRecurring'] == true,
    );
  }
}
