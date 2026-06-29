import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';

/// Reys kartochkasida bo'sh o'rinlar sonini РєСћСЂСЃР°С‚Р°РґРёРіР°РЅ РјРµСЂС†Р°Р№РґРёРіР°РЅ badge.
/// 1 С‚Р° qolsa вЂ” tez РјРµСЂС†Р°Р№РґРё, 2-3 вЂ” СћСЂС‚Р°С‡Р°, 4+ вЂ” СЃРµРєРёРЅ.
class SeatPulse extends StatefulWidget {
  const SeatPulse({super.key, required this.seats, required this.color});

  final int seats;
  final Color color;

  @override
  State<SeatPulse> createState() => _SeatPulseState();
}

class _SeatPulseState extends State<SeatPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    final ms = widget.seats == 1
        ? 400
        : widget.seats <= 3
            ? 700
            : 1200;
    _ctrl = AnimationController(
        vsync: this, duration: Duration(milliseconds: ms))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: widget.color.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.airline_seat_recline_normal,
                size: 15, color: widget.color),
            const SizedBox(width: 4),
            Text(
              context
                  .tr('intercity_seats_left')
                  .replaceAll('{n}', '${widget.seats}'),
              style: TextStyle(
                fontSize: AppText.labelLarge,
                fontWeight: FontWeight.w800,
                color: widget.color,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
