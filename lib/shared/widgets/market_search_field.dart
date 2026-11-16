import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/theme/ava_tokens.dart';

/// Бозор экранлари тепа қисми — ихчам (эга, 2026-11-16): AppBar паст, қаторлар орасида 1 px.
const double kMarketAppBarHeight = 44;
const double kMarketTopRowGap = 1;

/// Чиплар/таблар қатори баландлиги (босиш майдони ≥ 36 dp).
const double kMarketTopRowHeight = 36;

/// Бозор таблари (AppBar `bottom`) баландлиги.
const double kMarketTabHeight = 36;

/// Барча бозорлардаги ЯГОНА қидирув майдони (4 янги бозор, Уй-жой, Улгуржи, Хитой, Аралаш; эга 2026-11-16).
///
/// Ихчам: 40 px баландлик, чапда лупа, матн бўлсагина «×» тозалаш. Қидирув мантиғи чақирувчида
/// ([onChanged] / [onClear]) — ҳар бозор ўз манбасида қидиради.
class MarketSearchField extends StatelessWidget {
  const MarketSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
    this.fieldKey,
    this.clearTooltip,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  /// [TextField] калити (тестлар учун).
  final Key? fieldKey;
  final String? clearTooltip;

  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, kMarketTopRowGap, 12, 0),
      child: SizedBox(
        height: height,
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => TextField(
            key: fieldKey,
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            maxLines: 1,
            textAlignVertical: TextAlignVertical.center,
            style: TextStyle(fontSize: 14, color: c.ink),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(fontSize: 14, color: c.ink3),
              prefixIcon: Icon(Icons.search, size: 20, color: c.ink2),
              prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey('market_search_clear'),
                      tooltip: clearTooltip ?? context.tr('platform_store_search_clear'),
                      icon: const Icon(Icons.close, size: 18),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      onPressed: onClear,
                    ),
              isDense: true,
              filled: true,
              fillColor: c.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.line),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
