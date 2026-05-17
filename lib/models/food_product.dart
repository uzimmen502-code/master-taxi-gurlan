import 'package:cloud_firestore/cloud_firestore.dart';

/// Овqat каталоги (`food_catalog` Firestore ёки коддаги `FoodCatalog`).
///
/// Inventory — `food_inventory/{inventoryId}`, `inventoryId` = `food_{id}`.
class FoodProduct {
  const FoodProduct({
    required this.id,
    required this.name,
    required this.emoji,
    required this.price,
    required this.unit,
    required this.minQty,
    required this.step,
    required this.category,
    required this.desc,
    this.imageUrl = '',
  });

  final int id;
  final String name;
  final String emoji;
  final int price;
  final String unit;
  final double minQty;
  final double step;
  final String category;
  final String desc;
  final String imageUrl;

  String get inventoryId => 'food_$id';

  factory FoodProduct.fromFirestore(Map<String, dynamic> d, String docId) {
    var idVal = (d['id'] as num?)?.toInt() ?? 0;
    if (idVal == 0 && docId.startsWith('food_')) {
      idVal = int.tryParse(docId.substring(5)) ?? 0;
    }
    return FoodProduct(
      id: idVal,
      name: (d['name'] ?? '') as String,
      emoji: (d['emoji'] ?? '🍽') as String,
      price: (d['price'] as num?)?.toInt() ?? 0,
      unit: (d['unit'] ?? 'кг') as String,
      minQty: (d['minQty'] as num?)?.toDouble() ?? 1.0,
      step: (d['step'] as num?)?.toDouble() ?? 0.5,
      category: (d['category'] ?? '') as String,
      desc: (d['desc'] ?? '') as String,
      imageUrl: (d['imageUrl'] ?? '') as String,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'price': price,
        'unit': unit,
        'minQty': minQty,
        'step': step,
        'category': category,
        'desc': desc,
        'imageUrl': imageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
