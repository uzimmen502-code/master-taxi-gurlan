import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';

/// ⚡ «Ҳозирги заряд» слайдери (5–100%, қадам 5) — сафар экранида ва йўлда
/// «Зарядни янгилаш» варағида БИР ХИЛ (битта манба, такрорланмайди).
class EvSocSliderCard extends StatelessWidget {
  const EvSocSliderCard({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  static const double min = 5;
  static const double max = 100;
  static const int divisions = 19;

  /// [percent]ни слайдер қадамига (5) яқин қийматга келтиради (5..100).
  static int snap(num percent) {
    final stepped = (percent / 5).round() * 5;
    return stepped.clamp(min.toInt(), max.toInt());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E7EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.battery_charging_full_rounded,
                  color: AppColors.primaryText, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('ev_trip_charge_now'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              Text('${value.round()}%',
                  key: const ValueKey('ev_soc_value'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          Slider(
            key: const ValueKey('ev_soc_slider'),
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            label: '${value.round()}%',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// ⚡ «Зарядни янгилаш» варағи: ҳайдовчи ҳақиқий зарядни киритади, қолган
/// йўл шу заряд ва машинанинг ҳозирги жойидан қайта ҳисобланади. Слайдер
/// режадаги КУТИЛГАН зарядга қўйилган ([initial]) — ҳайдовчи фақат фарқини
/// тузатади. Матн киритиш йўқ (йўлда қулай).
class EvSocUpdateSheet extends StatefulWidget {
  const EvSocUpdateSheet({super.key, required this.initial});

  final int initial;

  /// Танланган заряд (%) ёки (ёпилса) `null`.
  static Future<int?> show(BuildContext context, {required int initial}) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.scaffold,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EvSocUpdateSheet(initial: initial),
    );
  }

  @override
  State<EvSocUpdateSheet> createState() => _EvSocUpdateSheetState();
}

class _EvSocUpdateSheetState extends State<EvSocUpdateSheet> {
  late double _value =
      EvSocSliderCard.snap(widget.initial).toDouble();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('ev_soc_update'),
              key: const ValueKey('ev_soc_update_title'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('ev_soc_update_hint'),
              style: const TextStyle(fontSize: 13, color: AvaLight.ink2),
            ),
            const SizedBox(height: 12),
            EvSocSliderCard(
              value: _value,
              onChanged: (v) => setState(() => _value = v),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: ElevatedButton(
                key: const ValueKey('ev_soc_update_apply'),
                onPressed: () => Navigator.of(context).pop(_value.round()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: AppColors.onPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  context.tr('ev_soc_update_apply'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
