import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../models/driver_roles.dart';
import '../../../repositories/courier_capability_repository.dart';

/// Иш панели ([DriverHubScreen]) ва «＋» курьер ҳолатидаги иш тури.
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