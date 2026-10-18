import 'package:ava_gurlan/repositories/news_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

FirebaseException _denied() =>
    FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

/// REGRESSION (қурилмада, 2026-10-19): «Хабарлар»ни очиб ўқилса ҳам пастки
/// белги (25) камаймасди. Сабаб: 9 хонали алиас `users/912778777` га ёзув
/// `permission-denied` берарди, цикл тўхтарди ва белгини қайта ҳисоблаш
/// (`recomputeHomeBadgePersonal`) ҳеч қачон бажарилмасди.
void main() {
  group('writeToUserDocIds', () {
    test('REGRESSION: алиас рад этилса — цикл давом этади, хато чиқмайди', () async {
      final written = <String>[];
      await writeToUserDocIds(['998912778777', '912778777'], (id) async {
        if (id == '912778777') throw _denied();
        written.add(id);
      });
      expect(written, ['998912778777'], reason: 'канон ёзилди, алиас рад — жим ўтилди');
    });

    test('алиас рад этилгандан КЕЙИНГИ ёзув ҳам бажарилади', () async {
      final written = <String>[];
      await writeToUserDocIds(['998900000000', '900000000', '12345678901'], (id) async {
        if (id == '900000000') throw _denied();
        written.add(id);
      });
      expect(written, ['998900000000', '12345678901']);
    });

    test('канон (биринчи) id хатоси ЮҚОРИГА чиқади — ёзув ўтмаган, жимлик ёлғон бўлади', () {
      expect(
        writeToUserDocIds(['998912778777', '912778777'], (id) async {
          if (id == '998912778777') throw _denied();
        }),
        throwsA(isA<FirebaseException>()),
      );
    });

    test('алиасдаги ЭЪТИБОРСИЗ қолмайдиган хато (permission-denied эмас) — юқорига', () {
      expect(
        writeToUserDocIds(['998912778777', '912778777'], (id) async {
          if (id == '912778777') {
            throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
          }
        }),
        throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'unavailable')),
      );
    });

    test('битта id — оддий ёзув', () async {
      final written = <String>[];
      await writeToUserDocIds(['998912778777'], (id) async => written.add(id));
      expect(written, ['998912778777']);
    });

    test('бўш рўйхат — ҳеч нарса қилмайди', () async {
      await writeToUserDocIds(const [], (id) async => fail('чақирилмаслиги керак'));
    });
  });
}
