import 'package:cloud_firestore/cloud_firestore.dart';

/// `users/{uid}/wallet_ledger` subcollection elementi.
///
/// Cloud Function `placeOrderWithWallet`, `creditChange`, `creditSupplier`,
/// `debitForOrder` va boshqalar
/// hujjatga `module` (qaysi modul: bread/food/...), `refType`+`refId` (qaysi
/// buyurtma/sessiya) va `meta` (orderTotal, cashPaid, note ...) maydonlarini
/// yozadi. Profilda har bir yozuvni "Қайтим • Нон буюртма • 12.05 14:30"
/// ko'rinishida ko'rsatish uchun shu maydonlar UI'ga kerak.
class WalletLedgerEntry {
  final String id;

  /// `change_accrued` | `supplier_credit` | `purchase_debit` | `payout_request`
  /// | `payout_paid` | `admin_adjust`.
  final String type;

  /// Musbat yoki manfiy bo'lishi mumkin.
  final int amount;

  final DateTime? createdAt;

  /// Qaysi modul: `bread`, `food`, `taxi`, `milk`, `rice`, …
  final String module;

  /// `refType` — `order`, `supplier_day`, `milk_day`, `payout_request`, …
  final String refType;

  /// Tegishli hujjat IDsi (masalan, order ID).
  final String refId;

  /// Qo'shimcha ma'lumotlar — `orderTotal`, `cashPaid`, `note` va h.k.
  final Map<String, dynamic> meta;

  const WalletLedgerEntry({
    required this.id,
    required this.type,
    required this.amount,
    this.createdAt,
    this.module = '',
    this.refType = '',
    this.refId = '',
    this.meta = const <String, dynamic>{},
  });

  bool get isPositive => amount >= 0;

  factory WalletLedgerEntry.fromDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final rawMeta = d['meta'];
    return WalletLedgerEntry(
      id: doc.id,
      type: d['type'] ?? '',
      amount: (d['amount'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      module: (d['module'] ?? '') as String,
      refType: (d['refType'] ?? '') as String,
      refId: (d['refId'] ?? '') as String,
      meta: rawMeta is Map<String, dynamic>
          ? rawMeta
          : (rawMeta is Map
              ? Map<String, dynamic>.from(rawMeta)
              : const <String, dynamic>{}),
    );
  }
}
