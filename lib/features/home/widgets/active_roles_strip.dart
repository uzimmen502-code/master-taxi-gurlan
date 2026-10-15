import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../models/driver_roles.dart';

/// Бош экран тасмасидаги ёзув: фақат ФАОЛ хизматлар. Масалан
/// «Шаҳарлараро ҳайдовчисиз», «Курьер+Маҳаллий такси ҳайдовчисиз»,
/// «Курьерсиз». Фаол ҳеч нарса бўлмаса `null`. Тўрттадан кўп бўлса —
/// «N хизматда фаолсиз».
String? activeRolesLabel(DriverRoles r, String Function(String key) tr) {
  final types = [
    for (final t in r.types)
      if (r.isActive(t)) t,
  ];
  final count = types.length + (r.courierOnline ? 1 : 0);
  if (count == 0) return null;
  if (count > 3) return tr('role_strip_many').replaceAll('{n}', '$count');
  if (types.isEmpty) return tr('role_strip_courier');
  final parts = types.map((t) => tr('role_type_$t')).join('+');
  final key = r.courierOnline ? 'role_strip_courier_driver' : 'role_strip_driver';
  return tr(key).replaceAll('{parts}', parts);
}

/// Локация қатори остидаги тўқ яшил тасма. Нуқта секин милтиллайди
/// (матн эмас); тизимда «анимацияни камайтириш» ёқилган бўлса — қимирламайди.
class ActiveRolesStrip extends StatefulWidget {
  const ActiveRolesStrip({super.key, required this.roles, this.onTap});

  final DriverRoles roles;
  final VoidCallback? onTap;

  @override
  State<ActiveRolesStrip> createState() => _ActiveRolesStripState();
}

class _ActiveRolesStripState extends State<ActiveRolesStrip>
    with SingleTickerProviderStateMixin {
  static const _darkGreen = Color(0xFF1B5E20);

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = activeRolesLabel(widget.roles, context.tr);
    if (label == null) return const SizedBox.shrink();

    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Semantics(
        button: widget.onTap != null,
        label: label,
        child: Material(
          color: _darkGreen,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: reduce
                        ? const AlwaysStoppedAnimation(1.0)
                        : Tween<double>(begin: 1.0, end: 0.25).animate(
                            CurvedAnimation(
                                parent: _pulse, curve: Curves.easeInOut),
                          ),
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: Color(0xFF76FF03),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
