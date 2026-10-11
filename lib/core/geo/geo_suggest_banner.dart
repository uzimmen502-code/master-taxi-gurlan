import 'package:flutter/material.dart';

import '../l10n/l10n_extension.dart';
import '../theme/app_theme.dart';
import 'geo_context.dart';

/// «Сиз ҳозир Чилонзордасиз. Шу ҳудуддагиларни кўрсатайми?» (D-GEO-12).
class GeoSuggestBanner extends StatelessWidget {
  const GeoSuggestBanner({
    super.key,
    required this.area,
    required this.onYes,
    required this.onNo,
  });

  final GeoArea area;
  final VoidCallback onYes;
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final place = area.districtLabel.isNotEmpty ? area.districtLabel : area.label;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.my_location, color: AppColors.primaryText, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('geo_suggest_text').replaceAll('{place}', place),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const ValueKey('geo_suggest_no'),
                  onPressed: onNo,
                  child: Text(context.tr('geo_suggest_no')),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  key: const ValueKey('geo_suggest_yes'),
                  onPressed: onYes,
                  child: Text(context.tr('geo_suggest_yes')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
