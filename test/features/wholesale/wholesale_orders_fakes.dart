// Улгуржи буюртма тестлари учун Firebase'сиз сохталар (ҚАТЪИЙ: номаълум
// callable чақирилса тест йиқилади — сохта жим «ok» бермайди).
import 'package:ava_gurlan/features/wholesale/models/wholesale_product.dart';
import 'package:ava_gurlan/models/geo_area.dart';
import 'package:ava_gurlan/repositories/service_config_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDb extends Fake implements FirebaseFirestore {}

class _FakeResult<T> extends Fake implements HttpsCallableResult<T> {
  _FakeResult(this._data);
  final Object? _data;
  @override
  T get data => _data as T;
}

typedef CallableHandler = Object? Function(Map<String, dynamic> payload);

class FakeFunctions extends Fake implements FirebaseFunctions {
  FakeFunctions(this.label);

  /// Қайси инстанция чақирилганини текшириш учун (`demand` / `wallet`).
  final String label;
  final calls = <(String, Map<String, dynamic>)>[];
  final handlers = <String, CallableHandler>{};

  @override
  HttpsCallable httpsCallable(String name, {HttpsCallableOptions? options}) => _FakeCallable(name, this);
}

class _FakeCallable extends Fake implements HttpsCallable {
  _FakeCallable(this.name, this.fns);
  final String name;
  final FakeFunctions fns;

  @override
  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    final payload = Map<String, dynamic>.from(parameters as Map);
    fns.calls.add((name, payload));
    final h = fns.handlers[name];
    if (h == null) throw StateError('unexpected callable ${fns.label}.$name');
    return _FakeResult<T>(h(payload));
  }
}

FirebaseFunctionsException fnError(String code, String reason, [Map<String, dynamic> extra = const {}]) =>
    FirebaseFunctionsException(message: 'x', code: code, details: {'reason': reason, ...extra});

class FakeGeo implements ServiceConfigRepository {
  @override
  Future<List<GeoRegion>> fetchRegions({bool activeOnly = true}) async =>
      const [GeoRegion(id: 'xorazm', name: 'Хоразм')];

  @override
  Future<List<GeoDistrict>> fetchDistricts(String regionId, {bool activeOnly = true}) async =>
      const [GeoDistrict(id: 'gurlan', regionId: 'xorazm', name: 'Гурлан')];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

WholesaleProduct sampleProduct({String sellerId = '998901111111'}) => WholesaleProduct.fromMap('prod1', {
      'sellerId': sellerId,
      'title': 'Гуруч',
      'priceTiers': [
        {'minQty': 1, 'price': 15000},
      ],
      'unit': 'қоп',
      'packs': [
        {
          'id': 'p2',
          'label': '25 кг',
          'unitWeightG': 25000,
          'priceTiers': [
            {'minQty': 1, 'price': 320000},
          ],
        },
      ],
    });

Map<String, dynamic> quoteReply({
  String quoteId = 'q1',
  int goods = 640000,
  int delivery = 45000,
  Map<String, dynamic>? paymentMethods,
  String? cardReason,
}) =>
    {
      'quoteId': quoteId,
      'productId': 'prod1',
      'productTitle': 'Гуруч',
      'packId': 'p2',
      'packLabel': '25 кг',
      'qty': 2,
      'unitPrice': goods ~/ 2,
      'goodsTotal': goods,
      'deliveryFee': delivery,
      'total': goods + delivery,
      'currency': 'UZS',
      'expiresAtMs': DateTime.now().add(const Duration(minutes: 15)).millisecondsSinceEpoch,
      if (paymentMethods != null) 'paymentMethods': paymentMethods,
      if (cardReason != null) 'cardUnavailableReason': cardReason,
    };
