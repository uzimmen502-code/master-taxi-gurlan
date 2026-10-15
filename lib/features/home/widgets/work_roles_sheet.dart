import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/driver_roles.dart';
import '../../../repositories/courier_capability_repository.dart';

/// «＋» → «Ҳайдовчи / Курьер» ойнасида танланадиган иш тури.
enum WorkChoice { intercity, local, marshrut, courier }

/// Курьер ҳолати бўйича ёрлиқ рангининг тоифаси.
enum WorkTone { join, active, inactive, pending, blocked }

/// Қаторнинг ҳолат ёрлиғи: матн калити ва тоифаси. Соф функция — тест учун.
({String key, WorkTone tone}) workRowState(WorkChoice choice, DriverRoles r) {
  switch (choice) {
    case WorkChoice.courier:
      final s = r.courierStatus;
      // Тўхтатилган ҳолат panelStatuses ичида ҳам бор (қўлдаги ишни
      // тугатиш учун) — шунинг учун АВВАЛ шу текширилади.
      if (CourierCapabilityRepository.finishOnlyStatuses.contains(s)) {
        return (key: 'work_state_suspended', tone: WorkTone.blocked);
      }
      if (CourierCapabilityRepository.panelStatuses.contains(s)) {
        return r.courierOnline
            ? (key: 'driver_chip_active', tone: WorkTone.active)
            : (key: 'driver_chip_inactive', tone: WorkTone.inactive);
      }
      if (s == CourierCapabilityRepository.applied) {
        return (key: 'work_state_pending', tone: WorkTone.pending);
      }
      return (key: 'work_state_join', tone: WorkTone.join);
    case WorkChoice.intercity:
    case WorkChoice.local:
    case WorkChoice.marshrut:
      final type = choice.name;
      if (!r.types.contains(type)) {
        return (key: 'work_state_join', tone: WorkTone.join);
      }
      return r.isActive(type)
          ? (key: 'driver_chip_active', tone: WorkTone.active)
          : (key: 'driver_chip_inactive', tone: WorkTone.inactive);
  }
}

String _labelKey(WorkChoice c) =>
    c == WorkChoice.courier ? 'work_type_courier' : 'role_type_${c.name}';

/// Тўрт йўналиш ва уларнинг ҳолати: ҳайдовчилик турлари + курьер.
Future<WorkChoice?> showWorkRolesSheet(
  BuildContext context, {
  required DriverRoles roles,
  List<WorkChoice> choices = WorkChoice.values,
}) {
  return showModalBottomSheet<WorkChoice>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final c = ctx.ava;
      Color toneColor(WorkTone t) {
        switch (t) {
          case WorkTone.active:
            return Colors.green.shade600;
          case WorkTone.inactive:
            return Colors.grey.shade600;
          case WorkTone.pending:
            return Colors.orange.shade800;
          case WorkTone.blocked:
            return Colors.red.shade700;
          case WorkTone.join:
            return c.brand;
        }
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AvaSpace.screen, 0, AvaSpace.screen, 8),
              child: Text(
                ctx.tr('work_sheet_title'),
                style: AvaText.sectionTitle.copyWith(color: c.ink),
              ),
            ),
            for (final choice in choices)
              Builder(builder: (_) {
                final st = workRowState(choice, roles);
                final color = toneColor(st.tone);
                return ListTile(
                  leading: Icon(
                    choice == WorkChoice.courier
                        ? Icons.delivery_dining
                        : Icons.local_taxi_outlined,
                    color: c.brand,
                  ),
                  title: Text(ctx.tr(_labelKey(choice))),
                  trailing: Text(
                    ctx.tr(st.key),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop(choice),
                );
              }),
          ],
        ),
      );
    },
  );
}

/// Янги ҳайдовчи сифатида рўйхатдан ўтишдан олдин тасдиқ. Тур танланиши
/// ЎЗИ рўйхатдан ўтказмайди: капабилити (`starter`) ва ариза шундан кейин
/// юборилади — «Бекор қилиш» ҳеч нарса ёзмайди (эга, 2026-10-15: «＋» орқали
/// кириб ҳайдовчи бўлишни бекор қилиб бўлмади).
Future<bool> confirmBecomeDriver(BuildContext context, WorkChoice choice) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('work_confirm_title')),
      content: Text(
        ctx.tr('work_confirm_body').replaceAll('{type}', ctx.tr('role_type_${choice.name}')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.tr('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.tr('confirm')),
        ),
      ],
    ),
  );
  return ok == true;
}