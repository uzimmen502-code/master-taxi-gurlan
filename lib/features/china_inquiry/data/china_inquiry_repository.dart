import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../demand_offer/domain/canonical_id.dart' show canonicalUserId;

/// Хитой бозори «Сўров қолдириш» — мижоз томони (`functions/china_inquiries.js`).
///
/// Ёзув ФАҚАТ callable орқали (rules'да client-write ёпиқ); ўқиш — мижоз ўз сўровини
/// ва `offers`ини (таъминотчисиз нусха). Босқич/рўйхат клиентга берилмайди: фақат
/// `getChinaInquiryAccess` → `enabled`.
class ChinaInquiryRepository {
  ChinaInquiryRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _firestore = firestore,
        _functions = functions;

  // Лазй: Firebase инициализациясиз (виджет тестларда) обуна яратилмайди.
  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;
  FirebaseFunctions get _fns => _functions ?? FirebaseFunctions.instance;

  /// Тугма кўринсинми. Хато/тармоқ йўқ → `false` (хизмат яширин қолади, UI синмайди).
  Future<bool> hasAccess() async {
    try {
      final res = await _fns.httpsCallable('getChinaInquiryAccess').call<Object?>();
      final d = res.data;
      return d is Map && d['enabled'] == true;
    } catch (e) {
      debugPrint('[ChinaInquiry] access: $e');
      return false;
    }
  }

  /// Янги сўров. [clientRequestId] ИККИ марта босишда ҳам бир хил бўлиши шарт (идемпотент).
  Future<ChinaInquiryCreated> create({
    required String text,
    required String quantity,
    required String clientRequestId,
    String? productId,
  }) async {
    final res = await _fns.httpsCallable('createChinaInquiry').call<Object?>({
      'text': text,
      'quantity': quantity,
      if (productId != null && productId.isNotEmpty) 'productId': productId,
      'consent': true,
      'clientRequestId': clientRequestId,
    });
    final d = res.data as Map;
    return ChinaInquiryCreated(
      inquiryId: '${d['inquiryId']}',
      refNo: '${d['refNo']}',
      duplicate: d['duplicate'] == true,
    );
  }

  Future<void> cancel(String inquiryId) async {
    await _fns.httpsCallable('cancelChinaInquiry').call<Object?>({'inquiryId': inquiryId});
  }

  /// Менинг сўровларим (энг янгиси биринчи). Чекланган: 50.
  Stream<List<ChinaInquiry>> watchMine(String phone) {
    final uid = canonicalUserId(phone);
    return _db
        .collection('china_inquiries')
        .where('ownerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((d) => ChinaInquiry.fromMap(d.id, d.data())).toList());
  }

  Stream<List<ChinaOffer>> watchOffers(String inquiryId) {
    return _db
        .collection('china_inquiries')
        .doc(inquiryId)
        .collection('offers')
        .orderBy('createdAt')
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((d) => ChinaOffer.fromMap(d.id, d.data())).toList());
  }
}

class ChinaInquiryCreated {
  const ChinaInquiryCreated({
    required this.inquiryId,
    required this.refNo,
    required this.duplicate,
  });

  final String inquiryId;
  final String refNo;
  final bool duplicate;
}

class ChinaInquiry {
  const ChinaInquiry({
    required this.id,
    required this.refNo,
    required this.status,
    required this.text,
    required this.quantity,
    required this.quoteCount,
    this.createdAt,
  });

  factory ChinaInquiry.fromMap(String id, Map<String, dynamic> m) => ChinaInquiry(
        id: id,
        refNo: '${m['refNo'] ?? ''}',
        status: '${m['status'] ?? 'new'}',
        text: '${m['text'] ?? ''}',
        quantity: '${m['quantity'] ?? ''}',
        quoteCount: (m['quoteCount'] is num) ? (m['quoteCount'] as num).toInt() : 0,
        createdAt: m['createdAt'] is Timestamp ? (m['createdAt'] as Timestamp).toDate() : null,
      );

  final String id;
  final String refNo;
  final String status;
  final String text;
  final String quantity;
  final int quoteCount;
  final DateTime? createdAt;

  /// Бекор қилиш мумкин (сервер state machine'и билан бир хил: терминал эмас).
  bool get isOpen => status == 'new' || status == 'sent' || status == 'quoted';
}

class ChinaOffer {
  const ChinaOffer({
    required this.id,
    required this.priceMinor,
    required this.currency,
    required this.withdrawn,
    this.minOrderQty,
    this.leadTimeDays,
    this.customerNote = '',
  });

  factory ChinaOffer.fromMap(String id, Map<String, dynamic> m) => ChinaOffer(
        id: id,
        priceMinor: (m['priceMinor'] is num) ? (m['priceMinor'] as num).toInt() : 0,
        currency: '${m['currency'] ?? ''}',
        withdrawn: m['withdrawn'] == true,
        minOrderQty: (m['minOrderQty'] is num) ? (m['minOrderQty'] as num).toInt() : null,
        leadTimeDays: (m['leadTimeDays'] is num) ? (m['leadTimeDays'] as num).toInt() : null,
        customerNote: '${m['customerNote'] ?? ''}',
      );

  final String id;
  final int priceMinor;
  final String currency;
  final bool withdrawn;
  final int? minOrderQty;
  final int? leadTimeDays;
  final String customerNote;

  /// Пул — бутун минор бирликдан матнга (`double` йўқ, 8-банд): 3850 → «38.50».
  String get priceText {
    final whole = priceMinor ~/ 100;
    final frac = (priceMinor % 100).toString().padLeft(2, '0');
    return '$whole.$frac';
  }
}
