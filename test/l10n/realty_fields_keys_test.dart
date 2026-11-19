// Уй-жой қўшимча майдонлари (эга 2026-11-19): ҳар бир танлов қийматининг
// матни 3 тилда бор; манзил ёрлиғида «ихтиёрий» йўқ (у мажбурий).
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/models/realty_listing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final keys = <String>[
    'realty_field_property_type', 'realty_type_all', 'realty_more_info',
    'realty_field_land_sotix', 'realty_unit_sotix', 'realty_detail_more',
    'realty_error_field_invalid', 'realty_error_year', 'realty_error_sotix',
    'realty_field_deposit', 'realty_field_rent_period', 'realty_currency_uzs',
    'realty_currency_usd', 'realty_field_utilities', 'realty_field_documents',
    for (final v in RealtyFieldOptions.propertyTypes) 'realty_type_$v',
    for (final v in RealtyFieldOptions.renovations) 'realty_renovation_$v',
    for (final v in RealtyFieldOptions.buildingTypes) 'realty_building_$v',
    for (final v in RealtyFieldOptions.utilities) 'realty_utility_$v',
    for (final v in RealtyFieldOptions.documents) 'realty_documents_$v',
    for (final v in RealtyFieldOptions.bathrooms) 'realty_bathroom_$v',
    for (final v in RealtyFieldOptions.rentPeriods) 'realty_rent_$v',
    for (final f in ['furnished', 'balcony', 'parking', 'negotiable', 'mortgage', 'barter'])
      'realty_flag_$f',
  ];

  for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
    test('$lang: қўшимча майдон калитлари бор ва бўш эмас', () {
      final m = jsonDecode(File('assets/lang/$lang.json').readAsStringSync())
          as Map<String, dynamic>;
      for (final k in keys) {
        expect((m[k] as String?)?.trim() ?? '', isNotEmpty, reason: '$lang/$k');
      }
      final addr = (m['realty_field_address'] as String).toLowerCase();
      expect(addr.contains('ихтиёрий') || addr.contains('ixtiyoriy') || addr.contains('необязательно'),
          isFalse, reason: 'манзил мажбурий — ёрлиқда «ихтиёрий» бўлмасин');
    });
  }
}
