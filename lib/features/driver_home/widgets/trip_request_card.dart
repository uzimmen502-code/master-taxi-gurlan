import 'package:flutter/material.dart';

import '../../../models/trip_request.dart';
import '../../../core/theme/app_theme.dart';

/// Карта ҳолати:
/// normal    — оддий, яшил Қабул / қизил Рад фаол.
/// reserving — бу ҳайдовчи банд қилган: 10 сония таймер + Қабул/Рад.
/// waiting   — бошқа банд қилган: сариқ "Кутиб туринг" (пассив).
enum TripCardMode { normal, reserving, waiting }

/// "Янги буюртмалар" рўйхатидаги битта карта.
class TripRequestCard extends StatelessWidget {
  const TripRequestCard({
    super.key,
    required this.ride,
    required this.onAccept,
    required this.onReject,
    this.mode = TripCardMode.normal,
    this.reserveSecsLeft = 0,
    this.disabled = false,
  });

  final TripRequest ride;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final TripCardMode mode;
  final int reserveSecsLeft;
  final bool disabled;

  static const _green = AppColors.primaryDark;
  static const _red = Color(0xFFB71C1C);
  static const _amber = Color(0xFFF9A825);

  String _genderLabel() {
    switch (ride.userGender) {
      case 'female':
        return '👩 Аёл';
      case 'male':
        return '👨 Эркак';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final secs = ride.secsLeft;
    final m = secs ~/ 60;
    final s = secs % 60;
    final timerColor = secs > 60 ? _green : secs > 30 ? AppColors.primary : _red;

    final name = ride.userName.trim().isNotEmpty
        ? ride.userName.trim()
        : ride.userPhone;
    final age = ride.age;
    final gender = _genderLabel();

    final subParts = <String>[
      if (gender.isNotEmpty) gender,
      if (age != null) '$age ёш',
    ];

    final isWaiting = mode == TripCardMode.waiting;

    return Opacity(
      opacity: isWaiting ? 0.7 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: mode == TripCardMode.reserving
              ? Border.all(color: _green, width: 1.5)
              : secs <= 30
                  ? Border.all(color: _red.withOpacity(0.4), width: 1.5)
                  : Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Йўловчи маълумоти ───
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: AppText.bodyLarge,
                              fontWeight: FontWeight.bold)),
                      if (subParts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subParts.join('  ·  '),
                              style: TextStyle(
                                  fontSize: AppText.labelSmall,
                                  color: Colors.grey.shade600)),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(ride.userPhone,
                            style: TextStyle(
                                fontSize: AppText.labelSmall,
                                color: Colors.grey.shade500)),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (ride.distanceKm > 0)
                      Text('${ride.distanceKm.toStringAsFixed(1)} км',
                          style: const TextStyle(
                              fontSize: AppText.bodyMedium,
                              fontWeight: FontWeight.bold,
                              color: _green)),
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: timerColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: timerColor.withOpacity(0.3))),
                      child: Text('⏱ $m:${s.toString().padLeft(2, '0')}',
                          style: TextStyle(
                              fontSize: AppText.labelSmall,
                              fontWeight: FontWeight.bold,
                              color: timerColor)),
                    ),
                  ],
                ),
              ],
            ),
            if (ride.from.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.location_on, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    ride.to.isNotEmpty
                        ? '${ride.from} → ${ride.to}'
                        : ride.from,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: AppText.labelSmall,
                        color: Colors.grey.shade600),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 10),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    // "Кутиб туринг" — пассив сариқ.
    if (mode == TripCardMode.waiting) {
      return Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _amber.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _amber, width: 1.5),
        ),
        child: const Text('⏳ Кутиб туринг',
            style: TextStyle(
                fontSize: AppText.bodyMedium,
                fontWeight: FontWeight.bold,
                color: Color(0xFFB8860B))),
      );
    }

    // Банд қилинган — таймер + Қабул/Рад.
    if (mode == TripCardMode.reserving) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Гаплашиб Қабул/Рад қилишингиз учун $reserveSecsLeft сония',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: AppText.labelSmall,
                  fontWeight: FontWeight.w600,
                  color: _green),
            ),
          ),
          Row(children: [
            Expanded(
              child: _ActionButton(
                  label: 'Рад', color: _red, filled: false, onTap: onReject),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _ActionButton(
                  label: 'Қабул', color: _green, filled: true, onTap: onAccept),
            ),
          ]),
        ],
      );
    }

    // Оддий.
    return Row(children: [
      Expanded(
        child: _ActionButton(
          label: 'Рад',
          color: _red,
          filled: false,
          onTap: disabled ? null : onReject,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: _ActionButton(
          label: 'Қабул',
          color: _green,
          filled: true,
          onTap: disabled ? null : onAccept,
        ),
      ),
    ]);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1.0,
        child: Container(
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: AppText.bodyMedium,
                  fontWeight: FontWeight.bold,
                  color: filled ? Colors.white : color)),
        ),
      ),
    );
  }
}
