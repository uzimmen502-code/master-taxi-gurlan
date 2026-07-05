import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../models/relative_event.dart';

/// Qarindoshlar moduli — umumiy l10n yordamchilari.
class RelativesL10n {
  RelativesL10n._();

  static Map<String, String> genderOptions(BuildContext context) => {
        '': context.tr('rel_gender_none'),
        'male': context.tr('rel_gender_male'),
        'female': context.tr('rel_gender_female'),
      };

  static Map<String, String> sideOptions(BuildContext context) => {
        '': context.tr('rel_gender_none'),
        'paternal': context.tr('rel_side_paternal'),
        'maternal': context.tr('rel_side_maternal'),
      };

  static String sideLabel(BuildContext context, String side) {
    switch (side) {
      case 'paternal':
        return context.tr('rel_side_paternal');
      case 'maternal':
        return context.tr('rel_side_maternal');
      default:
        return '';
    }
  }

  static String historyTypeLabel(BuildContext context, String type) {
    final key = switch (type) {
      'link' => 'rel_history_type_link',
      'merge' => 'rel_history_type_merge',
      'edit' => 'rel_history_type_edit',
      'create' => 'rel_history_type_create',
      _ => null,
    };
    return key != null ? context.tr(key) : type;
  }

  static String trParams(
    BuildContext context,
    String key,
    Map<String, String> params,
  ) {
    var s = context.tr(key);
    for (final e in params.entries) {
      s = s.replaceAll('{${e.key}}', e.value);
    }
    return s;
  }
}

extension RelativeEventTypeL10n on RelativeEventType {
  String trLabel(BuildContext context) =>
      context.tr('rel_event_type_$id');
}
