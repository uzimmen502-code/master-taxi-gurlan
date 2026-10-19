// Таом формасидаги чипларнинг ЯГОНА услуби (кухна, теглар, порция, категория).
//
// Танланган чип рангдан ТАШҚАРИ ҳам ажралади: қалин контур ва қалин ёзув —
// рангни ажратолмайдиганлар учун (ранг ягона белги эмас). Оддий чип контури `line`.

import 'package:flutter/material.dart';

import '../../../core/theme/ava_tokens.dart';

abstract final class FormChipStyle {
  static BorderSide side(AvaColors c, bool selected) =>
      BorderSide(color: selected ? c.brandText : c.line, width: selected ? 1.5 : 1);

  static TextStyle label(AvaColors c, bool selected) => AvaText.body.copyWith(
        color: selected ? c.brandText : c.ink,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      );
}
