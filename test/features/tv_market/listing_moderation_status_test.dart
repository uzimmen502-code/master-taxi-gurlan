// «Бозорлар» 2b (эга 2026-11-15): сотувчи кўрадиган ҳолат (нишон, сабаб, «N кун қолди», «Янгилаш»),
// янгилаш хатолари, PriceUnit.ton ва `listing_mod_*` калитлари 3 тилда.

import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/tv_market/domain/listing_status_view.dart';
import 'package:ava_gurlan/features/tv_market/domain/price_unit.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/features/tv_market/services/listing_renew_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: subtype_of_sealed_class
class _Doc implements DocumentSnapshot<Map<String, dynamic>> {
  _Doc(this.id, this._data);

  @override
  final String id;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic> data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

TvShopItem _item({String status = 'active', DateTime? expiresAt, String reason = ''}) => TvShopItem(
      id: 'i1',
      ownerPhone: '998901111111',
      ownerName: 'x',
      title: 'Олма',
      price: 12000,
      photoUrl: '',
      kind: 'product',
      districtId: 'gurlan',
      districtLabel: '',
      status: status,
      expiresAt: expiresAt,
      rejectReason: reason,
      priceUnit: PriceUnit.kg,
      description: 'Тавсиф',
    );

Map<String, dynamic> _lang(String l) =>
    jsonDecode(File('assets/lang/$l.json').readAsStringSync()) as Map<String, dynamic>;

FirebaseFunctionsException _fx(String code, [String? detailCode]) => FirebaseFunctionsException(
      code: code,
      message: 'server text that must not reach the user',
      details: detailCode == null ? null : {'code': detailCode},
    );

void main() {
  final now = DateTime(2026, 11, 15, 12);

  group('listingStatusView', () {
    test('pending / rejected+сабаб / expired+янгилаш / blocked', () {
      final p = listingStatusView(_item(status: 'pending'), now: now);
      expect((p.badge, p.labelKey, p.canRenew), (ListingBadge.pending, 'listing_mod_status_pending', false));

      final r = listingStatusView(_item(status: 'rejected', reason: '  Расм сифатсиз  '), now: now);
      expect((r.badge, r.labelKey, r.reason), (ListingBadge.rejected, 'listing_mod_status_rejected', 'Расм сифатсиз'));
      expect(r.canRenew, isFalse, reason: 'сервер фақат expired → pending');

      final e = listingStatusView(_item(status: 'expired'), now: now);
      expect((e.badge, e.labelKey, e.canRenew), (ListingBadge.expired, 'listing_mod_status_expired', true));

      final b = listingStatusView(_item(status: 'blocked'), now: now);
      expect(b.labelKey, 'bizprod_status_blocked', reason: 'мавжуд калит қайта ишлатилади');
    });

    test('active: «N кун қолди» юқорига яхлитланади; муддат йўқ/ўтган — йўқ (эски ҳужжат ўзгармайди)', () {
      expect(listingStatusView(_item(expiresAt: now.add(const Duration(days: 30))), now: now).daysLeft, 30);
      expect(listingStatusView(_item(expiresAt: now.add(const Duration(hours: 23))), now: now).daysLeft, 1);
      expect(listingStatusView(_item(expiresAt: now.add(const Duration(days: 1, minutes: 1))), now: now).daysLeft, 2);
      expect(listingStatusView(_item(expiresAt: now), now: now).daysLeft, isNull, reason: 'чегара: айни дақиқа');
      expect(listingStatusView(_item(expiresAt: now.subtract(const Duration(hours: 1))), now: now).daysLeft, isNull);
      final old = listingStatusView(_item(), now: now);
      expect((old.badge, old.labelKey, old.daysLeft), (ListingBadge.none, null, null));
    });

    test('номаълум/келажак ҳолат — нишонсиз, crash эмас', () {
      expect(listingStatusView(_item(status: 'archived'), now: now).labelKey, isNull);
      expect(listingStatusView(_item(status: 'deleted'), now: now).labelKey, isNull);
    });
  });

  group('TvShopItem — 2a майдонлари', () {
    test('fromFirestore ўқийди; эски ҳужжатда — бўш; toMap модерация майдонларини ЁЗМАЙДИ (rules)', () {
      final exp = DateTime.utc(2026, 12, 15);
      final item = TvShopItem.fromFirestore(_Doc('a', {
        'title': 'Олма',
        'status': 'rejected',
        'expiresAt': Timestamp.fromDate(exp),
        'submittedAt': Timestamp.fromDate(exp),
        'rejectReason': ' Нархи нотўғри ',
        'market': 'farm',
      }));
      expect(item.isRejected, isTrue);
      expect(item.expiresAt, exp.toLocal());
      expect(item.rejectReason, 'Нархи нотўғри');
      expect(item.market, 'farm');
      final m = item.toMap();
      for (final k in ['expiresAt', 'submittedAt', 'rejectReason', 'moderatedAt', 'market']) {
        expect(m.containsKey(k), isFalse, reason: k);
      }

      final old = TvShopItem.fromFirestore(_Doc('b', {'title': 'Эски', 'expiresAt': 'бузилган'}));
      expect((old.status, old.expiresAt, old.submittedAt, old.rejectReason, old.market), ('active', null, null, '', ''));
    });
  });

  group('editResubmitsForModeration', () {
    bool resub(TvShopItem it, {String? title, int? price, String? desc, PriceUnit? unit}) => editResubmitsForModeration(
          it,
          title: title ?? it.title,
          price: price ?? it.price,
          description: desc ?? it.description,
          priceUnit: unit ?? it.priceUnit,
        );

    test('active/expired/pending + контент ўзгарди → true; ўзгармади → false', () {
      for (final s in ['active', 'expired', 'pending']) {
        expect(resub(_item(status: s), title: 'Нок'), isTrue, reason: s);
        expect(resub(_item(status: s), price: 13000), isTrue, reason: s);
        expect(resub(_item(status: s), desc: 'Янги'), isTrue, reason: s);
        expect(resub(_item(status: s), unit: PriceUnit.ton), isTrue, reason: s);
        expect(resub(_item(status: s)), isFalse, reason: '$s: ўзгаришсиз');
      }
    });

    test('rejected/blocked — сервер қайта юбормайди → false', () {
      expect(resub(_item(status: 'rejected'), title: 'Нок'), isFalse);
      expect(resub(_item(status: 'blocked'), title: 'Нок'), isFalse);
    });
  });

  group('renew', () {
    test('хато → фойдаланувчи калити (сервер матни эмас) ва диагностик код', () {
      expect(renewErrorKey(_fx('failed-precondition', 'LISTING_NOT_EXPIRED')), 'listing_mod_renew_not_expired');
      expect(renewDiagnosticCode(_fx('failed-precondition', 'LISTING_NOT_EXPIRED')), 'LISTING_NOT_EXPIRED');
      expect(renewErrorKey(_fx('permission-denied', 'NOT_OWNER')), 'listing_mod_renew_failed');
      expect(renewDiagnosticCode(_fx('permission-denied', 'NOT_OWNER')), 'NOT_OWNER');
      expect(renewErrorKey(_fx('unavailable')), 'err_network');
      expect(renewDiagnosticCode(_fx('unavailable')), 'unavailable');
      expect(renewErrorKey(StateError('boom')), 'listing_mod_renew_failed');
      expect(renewDiagnosticCode(StateError('boom')), 'CLIENT_ERROR');
    });

    test('сервис: тўғри callable ва payload; хато қайта отилади', () async {
      final calls = <String>[];
      final ok = ListingRenewService(invoke: (name, p) async {
        calls.add('$name:${p['collection']}:${p['id']}');
        return {'ok': true, 'status': 'pending', 'changed': true};
      });
      await ok.renew(collection: 'tv_shop_items', id: 'i1');
      expect(calls, ['renewMarketListing:tv_shop_items:i1']);

      final bad = ListingRenewService(invoke: (_, __) async => throw _fx('failed-precondition', 'LISTING_NOT_EXPIRED'));
      expect(() => bad.renew(collection: 'tv_shop_items', id: 'i1'), throwsA(isA<FirebaseFunctionsException>()));
    });
  });

  group('PriceUnit.ton', () {
    test('wire round-trip; kg дан кейин (rules/PRICE_UNITS тартиби); суффикс калити', () {
      expect(PriceUnit.fromWire('ton'), PriceUnit.ton);
      expect(PriceUnit.ton.wire, 'ton');
      expect(PriceUnit.fromWire(PriceUnit.ton.wire), PriceUnit.ton);
      expect(PriceUnit.wires.indexOf('ton'), PriceUnit.wires.indexOf('kg') + 1);
      expect(PriceUnit.ton.labelKey, 'price_unit_ton');
      expect(PriceUnit.ton.suffixKey, 'price_unit_short_ton');
      expect(PriceUnit.fromWire('TON'), PriceUnit.fixed, reason: 'катта ҳарф — номаълум');
    });

    test('formatOfferPrice 3 тилда', () {
      String Function(String) t(Map<String, dynamic> m) => (k) => (m[k] as String?) ?? k;
      expect(formatOfferPrice(2500000, PriceUnit.ton, t(_lang('uz_Cyrl'))), '2 500 000 сўм / т');
      expect(formatOfferPrice(2500000, PriceUnit.ton, t(_lang('uz_Latn'))), '2 500 000 сўм / t');
      expect(formatOfferPrice(2500000, PriceUnit.ton, t(_lang('ru'))), '2 500 000 сўм / т');
      expect(formatOfferPrice(0, PriceUnit.ton, t(_lang('ru'))), '');
    });
  });

  test('l10n: listing_mod_* калитлари 3 тилда бир хил тўплам, бўш эмас, ўрин белгилари сақланган', () {
    final langs = {for (final l in ['uz_Cyrl', 'uz_Latn', 'ru']) l: _lang(l)};
    Set<String> keys(Map<String, dynamic> m) => m.keys.where((k) => k.startsWith('listing_mod_')).toSet();
    final base = keys(langs['uz_Cyrl']!);
    expect(base.length, 9);
    for (final e in langs.entries) {
      expect(keys(e.value), base, reason: e.key);
      for (final k in base) {
        expect((e.value[k] as String).trim(), isNotEmpty, reason: '${e.key} $k');
      }
      expect(e.value['listing_mod_days_left'], contains('{n}'), reason: e.key);
      expect(e.value['listing_mod_reject_reason'], contains('{reason}'), reason: e.key);
      for (final k in ['price_unit_ton', 'price_unit_short_ton']) {
        expect((e.value[k] as String?)?.trim(), isNotEmpty, reason: '${e.key} $k');
      }
    }
  });
}
