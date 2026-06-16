import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../controllers/marshrut_driver_panel_controller.dart';
import '../services/marshrut_panel_status_sounds.dart';

/// Smena ma'lumotlari — bottom sheet.
Future<void> showMarshrutSmenaInfoSheet(
  BuildContext context, {
  required MarshrutDriverPanelController controller,
  required Future<void> Function() onEditProfile,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _MarshrutSmenaInfoSheet(
      controller: controller,
      onEditProfile: onEditProfile,
    ),
  );
}

class _MarshrutSmenaInfoSheet extends StatefulWidget {
  const _MarshrutSmenaInfoSheet({
    required this.controller,
    required this.onEditProfile,
  });

  final MarshrutDriverPanelController controller;
  final Future<void> Function() onEditProfile;

  @override
  State<_MarshrutSmenaInfoSheet> createState() => _MarshrutSmenaInfoSheetState();
}

class _MarshrutSmenaInfoSheetState extends State<_MarshrutSmenaInfoSheet> {
  bool _statusSoundsEnabled = true;
  bool _loadingPref = true;

  @override
  void initState() {
    super.initState();
    _loadPref();
  }

  Future<void> _loadPref() async {
    final enabled = await MarshrutPanelStatusSounds.isEnabled();
    if (!mounted) return;
    setState(() {
      _statusSoundsEnabled = enabled;
      _loadingPref = false;
    });
  }

  Future<void> _onStatusSoundsChanged(bool value) async {
    setState(() => _statusSoundsEnabled = value);
    await MarshrutPanelStatusSounds.setEnabled(value);
    if (value) {
      await MarshrutPanelStatusSounds.previewOnline();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final stops = c.stops;
    final from = stops.isNotEmpty ? stops.first : '—';
    final to = stops.isNotEmpty ? stops.last : '—';
    final routeText = c.direction == 'forward' ? '$from → $to' : '$to → $from';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            context.tr('marshrut_smena_info_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: AppText.titleMedium,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _InfoTile(
            icon: Icons.route,
            label: context.tr('marshrut_smena_info_route'),
            value: routeText,
          ),
          _InfoTile(
            icon: Icons.place_outlined,
            label: context.tr('marshrut_smena_info_stops'),
            value: stops.isEmpty ? '—' : stops.join(' · '),
          ),
          _InfoTile(
            icon: Icons.event_seat_outlined,
            label: context.tr('marshrut_smena_info_seats'),
            value: context
                .tr('seats_ratio')
                .replaceAll('{left}', '${c.seatsLeft}')
                .replaceAll(
                  '{total}',
                  '${c.seatsTotal > 0 ? c.seatsTotal : c.seats}',
                ),
          ),
          if (c.isOnline)
            _InfoTile(
              icon: Icons.format_list_numbered,
              label: context.tr('marshrut_smena_info_queue'),
              value: context
                  .tr('marshrut_queue_position')
                  .replaceAll('{n}', '${c.queuePosition}'),
            ),
          _InfoTile(
            icon: Icons.directions_car_outlined,
            label: context.tr('marshrut_smena_info_car'),
            value: '${c.carModel} · ${c.plate}',
          ),
          const SizedBox(height: 4),
          Material(
            color: AppColors.moduleBg,
            borderRadius: BorderRadius.circular(12),
            child: SwitchListTile(
              secondary: Icon(
                _statusSoundsEnabled ? Icons.volume_up : Icons.volume_off,
                color: AppColors.primaryDark,
              ),
              title: Text(
                context.tr('marshrut_status_sounds_title'),
                style: const TextStyle(
                  fontSize: AppText.bodyMedium,
                  fontWeight: FontWeight.w600,
                ),
              ),
              value: _statusSoundsEnabled,
              onChanged: _loadingPref ? null : _onStatusSoundsChanged,
              activeThumbColor: AppColors.primaryMid,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await widget.onEditProfile();
            },
            icon: const Icon(Icons.person_outline, size: 18),
            label: Text(context.tr('edit_driver_data')),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppText.labelSmall,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: AppText.bodyMedium,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
