import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../models/marshrut_search_filter_stats.dart';

/// Qidiruv filter statistikasini yo'lovchi tushunadigan qisqa xabarga aylantiradi.
String? marshrutHumanFilterHint(
  BuildContext context,
  MarshrutSearchFilterStats s, {
  required bool emptyResults,
}) {
  if (s.totalActive == 0) {
    return context.tr('marshrut_empty_no_active');
  }

  if (emptyResults) {
    if (s.routeMismatch > 0 && s.shown == 0) {
      return context.tr('marshrut_empty_wrong_route');
    }
    if (s.full > 0 && s.shown == 0 && s.offline == 0) {
      return context
          .tr('marshrut_empty_all_full')
          .replaceAll('{n}', '${s.full}');
    }
    if (s.offline > 0 && s.shown == 0) {
      return context.tr('marshrut_empty_all_offline');
    }
    if (s.tooFar > 0 && s.shown == 0) {
      return context.tr('marshrut_empty_too_far');
    }
    return null;
  }

  if (s.hasHiddenReasons && s.hidden > 0) {
    return context
        .tr('marshrut_more_drivers_hidden')
        .replaceAll('{n}', '${s.hidden}');
  }
  return null;
}
