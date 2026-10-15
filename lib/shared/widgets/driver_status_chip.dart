import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../models/driver_roles.dart';
import '../../repositories/driver_repository.dart';

/// Профилдаги ҳайдовчи индикатори. Фақат ФАОЛ турлар кўрсатилади
/// (масалан «Ҳайдовчи · Шаҳарлараро»); ҳеч бири фаол бўлмаса — оддий
/// «Ҳайдовчи». Босилса барча турлар ва уларнинг ҳолати чиқади.
/// Ҳайдовчи бўлмаса умуман кўринмайди.
class DriverStatusChip extends StatefulWidget {
  const DriverStatusChip({super.key, required this.userId, this.load});

  final String userId;

  /// Тест учун: ҳолатни юклаш ўрнига шу функция.
  final Future<DriverRoles> Function(String uid)? load;

  @override
  State<DriverStatusChip> createState() => _DriverStatusChipState();
}

class _DriverStatusChipState extends State<DriverStatusChip> {
  late final Future<DriverRoles> _future;

  @override
  void initState() {
    super.initState();
    final load =
        widget.load ?? (uid) => context.read<DriverRepository>().driverRoles(uid);
    _future = load(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DriverRoles>(
      future: _future,
      builder: (context, snap) {
        final roles = snap.data;
        if (roles == null || !roles.isDriver) return const SizedBox.shrink();
        final activeLabels = [
          for (final t in roles.types)
            if (roles.isActive(t)) context.tr('driver_type_$t'),
        ];
        final title = context.tr('driver_chip_title');
        final text =
            activeLabels.isEmpty ? title : '$title · ${activeLabels.join(' · ')}';
        final color =
            roles.hasActive ? Colors.green.shade600 : Colors.grey.shade600;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              label: text,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showAll(context, roles),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_taxi_outlined, size: 16, color: color),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          text,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: color,
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
      },
    );
  }

  void _showAll(BuildContext context, DriverRoles roles) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in roles.types)
              ListTile(
                leading: Icon(
                  Icons.local_taxi_outlined,
                  color: roles.isActive(t)
                      ? Colors.green.shade600
                      : Colors.grey.shade600,
                ),
                title: Text(ctx.tr('driver_type_$t')),
                trailing: Text(
                  roles.isActive(t)
                      ? ctx.tr('driver_chip_active')
                      : ctx.tr('driver_chip_inactive'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: roles.isActive(t)
                        ? Colors.green.shade600
                        : Colors.grey.shade600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
