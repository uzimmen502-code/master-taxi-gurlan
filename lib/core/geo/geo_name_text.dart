import 'package:flutter/material.dart';

import '../l10n/l10n_extension.dart';
import 'geo_names.dart';

/// Туман номи фойдаланувчи тилида ([GeoNames]); ном келгунча — [fallback]
/// (ҳужжатда сақланган кирилл ёрлиқ).
class GeoDistrictText extends StatelessWidget {
  const GeoDistrictText(
    this.districtId, {
    super.key,
    this.fallback = '',
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String districtId;
  final String fallback;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: GeoNames.revision,
      builder: (context, _, __) => Text(
        GeoNames.district(districtId, context.contentLang, fallback: fallback),
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}
