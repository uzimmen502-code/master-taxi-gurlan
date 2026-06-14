/// Курьер «Тўлов» экранида таклиф қилинадigan маҳсулотлар (сотиб олиш нархи).
class PaymentProductOption {
  const PaymentProductOption({
    required this.code,
    required this.labelUz,
    required this.unit,
    required this.defaultUnitPrice,
  });

  final String code;
  final String labelUz;
  final String unit;
  final int defaultUnitPrice;
}

class PaymentProducts {
  PaymentProducts._();

  static const List<PaymentProductOption> defaults = [
    PaymentProductOption(
      code: 'rice',
      labelUz: 'Гуруч',
      unit: 'кг',
      defaultUnitPrice: 12000,
    ),
    PaymentProductOption(
      code: 'milk',
      labelUz: 'Сут',
      unit: 'л',
      defaultUnitPrice: 8000,
    ),
    PaymentProductOption(
      code: 'yogurt',
      labelUz: 'Қатиқ',
      unit: 'кг',
      defaultUnitPrice: 10000,
    ),
    PaymentProductOption(
      code: 'egg',
      labelUz: 'Тухум',
      unit: 'дона',
      defaultUnitPrice: 1500,
    ),
    PaymentProductOption(
      code: 'meat',
      labelUz: 'Гўшт',
      unit: 'кг',
      defaultUnitPrice: 85000,
    ),
    PaymentProductOption(
      code: 'other',
      labelUz: 'Бошқа',
      unit: 'дона',
      defaultUnitPrice: 0,
    ),
  ];

  static PaymentProductOption? byCode(String code) {
    for (final p in defaults) {
      if (p.code == code) return p;
    }
    return null;
  }
}
