// AVA Logistics — матн ёрдамчилари (хато матни, ҳудуд номи, сана).

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../data/logistics_repository.dart';

/// Сервер `details.reason` → фойдаланувчи матни (25-банд: ички код
/// кўрсатилмайди). Матни йўқ код — умумий матн.
String logisticsErrorText(BuildContext context, Object error) {
  if (error is LogisticsException) {
    final key = error.l10nKey;
    final text = context.tr(key);
    if (text != key) return text;
  }
  return context.tr('logistics_err_generic');
}

/// `toshkent_shahri` → «Toshkent shahri». Проекцияда фақат ID келади
/// (ижрочи карточкаси учун етарли; мижоз экранида манзил матни бор).
String logisticsGeoLabel(String id) {
  if (id.isEmpty) return '';
  return id
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// «07.10 14:05» — маҳаллий вақт.
String logisticsDateLabel(DateTime? d) {
  if (d == null) return '';
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.day)}.${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
}
