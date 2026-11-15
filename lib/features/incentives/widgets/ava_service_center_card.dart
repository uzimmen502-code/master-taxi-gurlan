import 'package:flutter/material.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/map_launcher.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';
import '../../../repositories/settings_repository.dart';

/// Туман AVA Сервис маркази ва (йўқ бўлса) диспетчер телефони.
typedef AvaServiceInfo = ({OilServicePoint? center, String fallbackPhone});

/// Фаол (тепада кўрсатилган) туманнинг AVA Сервис маркази; йўқ бўлса — диспетчер телефони.
/// «Менинг машинам» ва Мошина бозори «Эҳтиёт қисмлар» таби учун умумий (9-босқич, 2026-11-15).
Future<AvaServiceInfo> loadAvaServiceInfo() async {
  final results = await Future.wait<Object?>([
    OilChangeRepository().fetchAvaCenter(GeoContext.active.districtId),
    SettingsRepository().getDispatcherPhone(),
  ]);
  return (center: results[0] as OilServicePoint?, fallbackPhone: (results[1] as String?) ?? '');
}

/// AVA сервис картаси: ном, манзил, «Қўнғироқ», «Йўл» (аввал `AutoHubScreen._serviceCard`; калитлар ўзгармаган).
class AvaServiceCenterCard extends StatelessWidget {
  const AvaServiceCenterCard({
    super.key,
    required this.info,
    this.margin = const EdgeInsets.fromLTRB(12, 10, 12, 0),
  });

  final Future<AvaServiceInfo> info;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AvaServiceInfo>(
      future: info,
      builder: (context, snap) {
        if (snap.hasError) debugPrint('[AvaService] AVA_SERVICE_LOAD_FAILED: ${snap.error}');
        final center = snap.data?.center;
        final phone = (center != null && center.phone.trim().isNotEmpty
                ? center.phone
                : (snap.data?.fallbackPhone ?? ''))
            .trim();
        final name = center != null && center.name.trim().isNotEmpty
            ? center.name.trim()
            : context.tr('auto_hub_service_title');
        final address = center?.address.trim() ?? '';
        return Card(
          key: const ValueKey('auto_hub_service'),
          margin: margin,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.build_circle, size: 34, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          Text(
                            address.isNotEmpty ? address : context.tr('auto_hub_service_sub'),
                            key: const ValueKey('auto_hub_service_address'),
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (phone.isNotEmpty || (center?.hasLocation ?? false)) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (phone.isNotEmpty)
                        FilledButton.tonalIcon(
                          key: const ValueKey('auto_hub_call'),
                          onPressed: () => callPhone(phone),
                          icon: const Icon(Icons.phone),
                          label: Text(context.tr('auto_hub_call')),
                        ),
                      if (center != null && center.hasLocation)
                        OutlinedButton.icon(
                          key: const ValueKey('auto_hub_route'),
                          onPressed: () => openMapsNavigation(lat: center.lat!, lng: center.lng!, label: name),
                          icon: const Icon(Icons.directions),
                          label: Text(context.tr('auto_hub_route')),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
