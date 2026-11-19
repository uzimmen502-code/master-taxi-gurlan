import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/realty_listing.dart';

/// Қўшимча майдонлар (эга 2026-11-19) — матн калитлари ва ихчам
/// кўринишлар БИТТА жойда: форма, тафсилот ва карточкалар бир хил
/// ёрлиқни ишлатади.

String realtyTypeKey(String type) => 'realty_type_$type';

String _trimNum(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

/// Карточка қатори: «Квартира · 3 хона · 4/9 қават · 68 м² · 6 сотих».
/// Тур/сотих йўқ эски ёзувда — аввалги `specsLabel` ўзи.
String realtyCardSpecs(String Function(String key) tr, RealtyListing r) {
  final x = r.extras;
  final parts = <String>[
    if (x.propertyType != null) tr(realtyTypeKey(x.propertyType!)),
    if (r.specsLabel.isNotEmpty) r.specsLabel,
    if (x.landSotix != null) '${_trimNum(x.landSotix!)} ${tr('realty_unit_sotix')}',
  ];
  return parts.join(' · ');
}

/// Пул миқдори валютаси билан: «1 500 000 сўм» / «$45 000».
String realtyMoney(String Function(String key) tr, int amount, String currency) =>
    currency == 'USD' ? '\$${formatPrice(amount)}' : '${formatPrice(amount)} ${tr('realty_currency_uzs')}';

/// Тафсилот экранидаги «Тафсилотлар» бўлими — фақат тўлдирилган
/// майдонлар. Ҳеч нарса бўлмаса — бўш виджет (эски ёзувлар).
class RealtyExtrasSection extends StatelessWidget {
  const RealtyExtrasSection({super.key, required this.listing});

  final RealtyListing listing;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final tr = context.tr;
    final x = listing.extras;
    final rows = <(String, String)>[
      if (x.propertyType != null)
        (tr('realty_field_property_type'), tr(realtyTypeKey(x.propertyType!))),
      if (x.landSotix != null)
        (tr('realty_field_land_sotix'), _trimNum(x.landSotix!)),
      if (x.renovation != null)
        (tr('realty_field_renovation'), tr('realty_renovation_${x.renovation}')),
      if (x.buildingType != null)
        (tr('realty_field_building_type'), tr('realty_building_${x.buildingType}')),
      if (x.yearBuilt != null) (tr('realty_field_year_built'), '${x.yearBuilt}'),
      if (x.bathroom != null)
        (tr('realty_field_bathroom'), tr('realty_bathroom_${x.bathroom}')),
      if (x.utilities.isNotEmpty)
        (
          tr('realty_field_utilities'),
          x.utilities.map((u) => tr('realty_utility_$u')).join(', '),
        ),
      if (x.documents != null)
        (tr('realty_field_documents'), tr('realty_documents_${x.documents}')),
      if (listing.deal == RealtyDeal.rent && x.rentPeriod != null)
        (tr('realty_field_rent_period'), tr('realty_rent_${x.rentPeriod}')),
      if (listing.deal == RealtyDeal.rent && x.deposit != null)
        (tr('realty_field_deposit'), realtyMoney(tr, x.deposit!, x.priceCurrency)),
    ];
    final flags = <String>[
      if (x.furnished) 'realty_flag_furnished',
      if (x.balcony) 'realty_flag_balcony',
      if (x.parking) 'realty_flag_parking',
      if (x.negotiable) 'realty_flag_negotiable',
      if (x.mortgage) 'realty_flag_mortgage',
      if (x.barter) 'realty_flag_barter',
    ];
    if (rows.isEmpty && flags.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('realty_extras_section'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('realty_detail_more'),
            style: TextStyle(
              fontSize: AppText.titleSmall,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      label,
                      style: TextStyle(fontSize: AppText.bodySmall, color: c.ink3),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: AppText.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (flags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in flags)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.chip,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: c.line),
                    ),
                    child: Text(
                      tr(k),
                      style: TextStyle(fontSize: AppText.labelSmall, color: c.ink2),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
