import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/payment_products.dart';

/// `procurement_products/{code}` — харид / тўлов нархи каталоги.
class ProcurementProduct {
  const ProcurementProduct({
    required this.code,
    required this.label,
    required this.unit,
    required this.price,
    this.active = true,
    this.updatedAt,
  });

  final String code;
  final String label;
  final String unit;
  final int price;
  final bool active;
  final DateTime? updatedAt;

  static const List<String> defaultCodeOrder = [
    'rice',
    'milk',
    'yogurt',
    'egg',
    'meat',
    'other',
  ];

  static List<ProcurementProduct> fromPaymentDefaults() {
    return [
      for (final d in PaymentProducts.defaults)
        ProcurementProduct(
          code: d.code,
          label: d.labelUz,
          unit: d.unit,
          price: d.defaultUnitPrice,
        ),
    ];
  }

  factory ProcurementProduct.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return ProcurementProduct(
      code: (d['code'] ?? doc.id) as String,
      label: (d['label'] ?? '') as String,
      unit: (d['unit'] ?? '') as String,
      price: (d['price'] as num?)?.toInt() ?? 0,
      active: d['active'] != false,
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'code': code,
        'label': label,
        'unit': unit,
        'price': price,
        'active': active,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  ProcurementProduct copyWith({
    String? label,
    String? unit,
    int? price,
    bool? active,
  }) {
    return ProcurementProduct(
      code: code,
      label: label ?? this.label,
      unit: unit ?? this.unit,
      price: price ?? this.price,
      active: active ?? this.active,
      updatedAt: updatedAt,
    );
  }

  static int compareByDefaultOrder(ProcurementProduct a, ProcurementProduct b) {
    final ai = defaultCodeOrder.indexOf(a.code);
    final bi = defaultCodeOrder.indexOf(b.code);
    final aIdx = ai < 0 ? 999 : ai;
    final bIdx = bi < 0 ? 999 : bi;
    final byOrder = aIdx.compareTo(bIdx);
    if (byOrder != 0) return byOrder;
    return a.code.compareTo(b.code);
  }
}
