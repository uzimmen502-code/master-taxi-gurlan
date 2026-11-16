import 'dart:async';

import 'package:ava_gurlan/features/business_orders/data/business_orders_repository.dart';
import 'package:ava_gurlan/features/business_orders/domain/business_order.dart';
import 'package:ava_gurlan/features/business_orders/domain/delivery_quote.dart';

/// Қатъий сохта репозиторий: фақат тест ўзи берган жавобни қайтаради, ҳар чақирув журналга ёзилади.
class FakeBusinessOrdersRepository implements BusinessOrdersRepository {
  final calls = <String>[];
  final placeKeys = <String>[];
  final placeArgs = <Map<String, Object?>>[];

  BusinessOrdersAccess accessResult = const BusinessOrdersAccess(allowed: true, stage: 'public');
  BusinessOrderQuote quoteResult = const BusinessOrderQuote(itemsTotal: 10000, deliveryFee: 8000, total: 18000);
  Object? quoteError;

  /// Навбатдаги `place` натижалари: [Object] — ташланади, [BusinessPlaceResult] — қайтади.
  final placeQueue = <Object>[];
  Object? nextActionError;
  BusinessCompleteResult completeResult = const BusinessCompleteResult(delivered: true, cashCollected: 18000);
  NearbyBusinessOrders nearby = const NearbyBusinessOrders([]);

  final orders = <String, StreamController<BusinessOrder?>>{};
  final sellerOrders = StreamController<List<BusinessOrder>>.broadcast();
  final codes = <String, String?>{};

  StreamController<BusinessOrder?> orderCtrl(String id) =>
      orders.putIfAbsent(id, () => StreamController<BusinessOrder?>.broadcast());

  Future<void> _action(String log) async {
    calls.add(log);
    final e = nextActionError;
    if (e != null) {
      nextActionError = null;
      throw e;
    }
  }

  @override
  Future<BusinessOrdersAccess> access({String businessId = '', String itemId = ''}) async {
    calls.add(businessId.isNotEmpty || itemId.isEmpty ? 'access:$businessId' : 'access:item:$itemId');
    return accessResult;
  }

  @override
  Future<BusinessOrderQuote> quote({
    required String businessId,
    required List<Map<String, Object>> items,
    required double lat,
    required double lng,
  }) async {
    calls.add('quote:$businessId:${items.length}');
    final e = quoteError;
    if (e != null) throw e;
    return quoteResult;
  }

  @override
  Future<BusinessPlaceResult> place({
    required String idempotencyKey,
    required String businessId,
    required List<Map<String, Object>> items,
    required double lat,
    required double lng,
    required String deliveryPaymentMethod,
    String address = '',
    String note = '',
    String userName = '',
  }) async {
    calls.add('place');
    placeKeys.add(idempotencyKey);
    placeArgs.add({'items': items, 'pay': deliveryPaymentMethod, 'note': note, 'lat': lat});
    final next = placeQueue.isEmpty ? const BusinessPlaceResult(orderId: 'o1') : placeQueue.removeAt(0);
    if (next is BusinessPlaceResult) return next;
    throw next;
  }

  @override
  Future<void> cancel(String orderId, {String reason = ''}) => _action('cancel:$orderId');

  @override
  Future<void> accept(String orderId) => _action('accept:$orderId');

  @override
  Future<void> reject(String orderId, {String reason = ''}) => _action('reject:$orderId:$reason');

  @override
  Future<void> markReady(String orderId) => _action('ready:$orderId');

  @override
  Future<NearbyBusinessOrders> listNearby({double? lat, double? lng, int? radiusKm}) async {
    calls.add('nearby:$radiusKm');
    return nearby;
  }

  @override
  Future<void> claim(String orderId) => _action('claim:$orderId');

  @override
  Future<void> pickup(String orderId, {required String pickupCode}) => _action('pickup:$orderId:$pickupCode');

  @override
  Future<void> arrive(String orderId) => _action('arrive:$orderId');

  @override
  Future<BusinessCompleteResult> complete(String orderId) async {
    await _action('complete:$orderId');
    return completeResult;
  }

  @override
  Stream<BusinessOrder?> watchOrder(String orderId) => orderCtrl(orderId).stream;

  @override
  Stream<List<BusinessOrder>> watchSellerOrders(String sellerPhone, {int limit = 100}) {
    calls.add('watchSeller:$sellerPhone');
    return sellerOrders.stream;
  }

  @override
  Future<List<BusinessOrder>> fetchSellerOrders(String sellerPhone, {int limit = 50}) async => const [];

  @override
  Stream<String?> watchPickupCode(String orderId) => Stream.value(codes[orderId]);

  // ── Етказиш нархи сўрови (STAGE 11) ──
  OpenDeliveryQuotes openQuotes = const OpenDeliveryQuotes([], viewer: 'courier');
  Object? openQuotesError;
  final respondArgs = <(String, int)>[];
  final quoteCtrls = <String, StreamController<DeliveryQuote?>>{};
  Object? requestQuoteError;
  final requestQuoteArgs = <Map<String, Object?>>[];

  StreamController<DeliveryQuote?> quoteCtrl(String id) =>
      quoteCtrls.putIfAbsent(id, () => StreamController<DeliveryQuote?>.broadcast());

  @override
  Future<DeliveryQuoteRequestResult> requestDeliveryQuote({
    required String itemId,
    required int qty,
    required double lat,
    required double lng,
    required String address,
    int? floor,
    String note = '',
  }) async {
    calls.add('requestQuote:$itemId:$qty');
    requestQuoteArgs.add({'itemId': itemId, 'qty': qty, 'lat': lat, 'address': address, 'floor': floor, 'note': note});
    final e = requestQuoteError;
    if (e != null) throw e;
    return const DeliveryQuoteRequestResult(quoteId: 'q1', status: 'open');
  }

  @override
  Future<DeliveryQuoteRespondResult> respondDeliveryQuote({required String quoteId, required int priceUzs}) async {
    await _action('respond:$quoteId:$priceUzs');
    respondArgs.add((quoteId, priceUzs));
    return DeliveryQuoteRespondResult(quoteId: quoteId, priceUzs: priceUzs, responderRole: openQuotes.viewer);
  }

  @override
  Future<BusinessPlaceResult> acceptDeliveryQuote({
    required String quoteId,
    required String deliveryPaymentMethod,
    String note = '',
  }) async {
    await _action('acceptQuote:$quoteId:$deliveryPaymentMethod');
    return const BusinessPlaceResult(orderId: 'o1');
  }

  @override
  Future<OpenDeliveryQuotes> listOpenDeliveryQuotes({double? lat, double? lng, int? radiusKm}) async {
    calls.add('openQuotes');
    final e = openQuotesError;
    if (e != null) throw e;
    return openQuotes;
  }

  @override
  Stream<DeliveryQuote?> watchDeliveryQuote(String quoteId) => quoteCtrl(quoteId).stream;
}
