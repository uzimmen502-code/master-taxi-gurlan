import 'package:flutter/material.dart';

import 'service_config_holder.dart';

/// Глобал бренд + туман контексти (икки қаторли иерархия).
///
/// Бренд доим: [brand]. Туман — [ServiceConfigHolder.districtLabel]
/// (қисқа ном); бўш бўлса иккинчи қатор кўрсатилмайди.
class BrandLabels {
  BrandLabels._();

  static const String brand = 'AVA';

  /// `Гурлан тумани` → `Гурлан`, `Urganch shahri` → `Urganch`.
  static String shortDistrictName(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    const suffixes = <String>[
      ' тумани',
      ' tumani',
      ' шаҳри',
      ' shahri',
      ' района',
      ' район',
      ' город',
    ];
    final lower = s.toLowerCase();
    for (final suffix in suffixes) {
      if (lower.endsWith(suffix.toLowerCase())) {
        s = s.substring(0, s.length - suffix.length).trim();
        break;
      }
    }
    return s;
  }

  /// Жорий кешдан қисқа туман; бўш бўлса `null` (UI яширади).
  static String? get districtContext {
    final label = ServiceConfigHolder.districtLabel.trim();
    return label.isEmpty ? null : label;
  }
}

/// Катта бренд + (ихтиёрий) кичик туман қатори.
class BrandTitleColumn extends StatelessWidget {
  const BrandTitleColumn({
    super.key,
    this.brandStyle,
    this.districtStyle,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.spacing = 4,
    this.listenToConfig = true,
  });

  final TextStyle? brandStyle;
  final TextStyle? districtStyle;
  final CrossAxisAlignment crossAxisAlignment;
  final double spacing;
  final bool listenToConfig;

  @override
  Widget build(BuildContext context) {
    if (!listenToConfig) {
      return _build(BrandLabels.districtContext);
    }
    return ValueListenableBuilder<int>(
      valueListenable: ServiceConfigHolder.revision,
      builder: (_, __, ___) => _build(BrandLabels.districtContext),
    );
  }

  Widget _build(String? district) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(
          BrandLabels.brand,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: brandStyle ??
              const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: Colors.white,
              ),
        ),
        if (district != null) ...[
          SizedBox(height: spacing),
          Text(
            district,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: districtStyle ??
                TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
          ),
        ],
      ],
    );
  }
}
