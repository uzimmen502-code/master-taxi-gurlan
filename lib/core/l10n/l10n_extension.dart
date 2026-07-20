import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

extension L10nExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;

  String tr(String key) => AppLocalizations.tr(this, key);

  /// Controller xabarlari: `key` yoki `key|param` (`error_generic|…`, `place_saved|…`).
  String trMsg(String message, {Map<String, String> params = const {}}) {
    final parts = message.split('|');
    final key = parts[0];
    var s = tr(key);
    final merged = Map<String, String>.from(params);
    if (parts.length > 1) {
      final tail = parts.sublist(1).join('|');
      switch (key) {
        case 'error_generic':
        case 'courier_error_generic':
          merged['error'] = tail;
          break;
        case 'max_saved_places':
          merged['count'] = tail;
          break;
        case 'place_saved':
        case 'place_deleted':
          merged['name'] = tail;
          break;
        case 'ghost_blocked':
        case 'retry_after_minutes':
        case 'local_taxi_block_active':
          merged['minutes'] = tail;
          break;
        default:
          merged['value'] = tail;
      }
    }
    for (final e in merged.entries) {
      s = s.replaceAll('{${e.key}}', e.value);
    }
    return s;
  }
}
