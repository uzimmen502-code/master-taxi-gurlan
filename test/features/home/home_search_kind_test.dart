import 'package:ava_gurlan/features/home/widgets/home_search_kind.dart';
import 'package:ava_gurlan/models/search_index_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SearchIndexEntry _e(String type) => SearchIndexEntry(
      id: 'x',
      type: type,
      moduleId: 'm',
      title: 'T',
    );

void main() {
  group('homeSearchKindOf — 9 ta ichki tur -> 4 ta toifa', () {
    test('Эълон: бозор эълони, иш эълони, юк эълони', () {
      for (final t in [
        SearchIndexEntry.typeMarketAd,
        SearchIndexEntry.typeJob,
        SearchIndexEntry.typeYukListing,
      ]) {
        expect(homeSearchKindOf(_e(t)), HomeSearchKind.ad, reason: t);
      }
    });

    test('Хизмат: хизмат, шаҳарлараро йўналиш, МФЙ', () {
      for (final t in [
        SearchIndexEntry.typeService,
        SearchIndexEntry.typeIntercityRoute,
        SearchIndexEntry.typeLocalPlace,
      ]) {
        expect(homeSearchKindOf(_e(t)), HomeSearchKind.service, reason: t);
      }
    });

    test('Маҳсулот: платформа, нон, овқат', () {
      for (final t in [
        SearchIndexEntry.typePlatformProduct,
        SearchIndexEntry.typeBreadProduct,
        SearchIndexEntry.typeFoodProduct,
      ]) {
        expect(homeSearchKindOf(_e(t)), HomeSearchKind.product, reason: t);
      }
    });

    test('номаълум тур йиқилмайди — «Эълон» га тушади', () {
      expect(homeSearchKindOf(_e('kelajakdagi_tur')), HomeSearchKind.ad);
      expect(homeSearchKindOf(_e('')), HomeSearchKind.ad);
    });

    test('ҳар тоифанинг ўз калити ва иконкаси бор', () {
      final keys = <String>{};
      final icons = <IconData>{};
      for (final k in HomeSearchKind.values) {
        keys.add(k.l10nKey);
        icons.add(k.icon);
      }
      // Такрорланмаслиги керак — акс ҳолда белгилар фарқланмайди.
      expect(keys.length, HomeSearchKind.values.length);
      expect(icons.length, HomeSearchKind.values.length);
    });

    test('«Видео» индексдан эмас — фақат клипдан келади', () {
      // search_index'да video тури умуман йўқ; клиплар `tv_clips` дан
      // бевосита қидирилади, шунинг учун бу харита уни қайтармайди.
      for (final t in [
        SearchIndexEntry.typeMarketAd,
        SearchIndexEntry.typeJob,
        SearchIndexEntry.typeYukListing,
        SearchIndexEntry.typeService,
        SearchIndexEntry.typeIntercityRoute,
        SearchIndexEntry.typeLocalPlace,
        SearchIndexEntry.typePlatformProduct,
        SearchIndexEntry.typeBreadProduct,
        SearchIndexEntry.typeFoodProduct,
      ]) {
        expect(homeSearchKindOf(_e(t)), isNot(HomeSearchKind.video));
      }
    });
  });
}
