import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/idempotency_keys.dart';
import '../../../repositories/courier_capability_repository.dart';

/// «Курьер бўлиш» аризасининг натижаси.
class CourierApplyResult {
  const CourierApplyResult.cancelled()
      : status = null,
        failed = false;
  const CourierApplyResult.done(String this.status) : failed = false;
  const CourierApplyResult.failed()
      : status = null,
        failed = true;

  /// Янги ҳолат (`applied`, `trial`…); бекор ёки хатода `null`.
  final String? status;
  final bool failed;
}

/// Курьер аризасининг ягона оқими: тасдиқ ойнаси → `requestCapability` →
/// хабар. Профил ва «＋» менюси шу функцияни ишлатади — матнлар, хато
/// кодлари ва ҳолат қоидалари битта жойда (7-банд).
///
/// Мануал режимда `applied` (админ тасдиғини кутади), авто режимда дарҳол
/// ишлаш ҳолати (D-15.3, D-15.5).
///
/// Икки марта юбориш ҳимояси (C-2): сўров кетаётганда оқим қайта очилмайди
/// ([_courierApplyInFlight]); `requestId` муваффақиятгача бир хил — таймаутдан
/// кейин қайта уриниш ўша аризани сўрайди ([_courierApplyKeys]).
Future<CourierApplyResult> runCourierApplyFlow(
  BuildContext context, {
  CourierCapabilityRepository? repository,
}) async {
  if (_courierApplyInFlight) return const CourierApplyResult.cancelled();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('courier_apply_button')),
      content: Text(ctx.tr('courier_apply_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.tr('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.tr('courier_apply_confirm')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return const CourierApplyResult.cancelled();
  // Тасдиқ ойнаси очиқ турганда бошқа нусха юбориб улгурган бўлса.
  if (_courierApplyInFlight) return const CourierApplyResult.cancelled();

  final repo = repository ?? CourierCapabilityRepository();
  _courierApplyInFlight = true;
  try {
    final status = await repo.apply(requestId: _courierApplyKeys.keyFor(_courierScope));
    _courierApplyKeys.settled(_courierScope);
    if (!context.mounted) return CourierApplyResult.done(status);
    _snack(
      context,
      context.tr(CourierCapabilityRepository.panelStatuses.contains(status)
          ? 'courier_apply_approved'
          : 'courier_apply_sent'),
    );
    return CourierApplyResult.done(status);
  } on FirebaseFunctionsException catch (e) {
    // 25-қоида: фойдаланувчига тушунарли матн, ички код — log'да.
    debugPrint('courier_apply: ${e.code} ${e.message}');
    if (context.mounted) {
      _snack(
        context,
        context.tr(e.code == 'failed-precondition'
            ? 'courier_apply_blocked'
            : 'courier_apply_failed'),
        isError: true,
      );
    }
    return const CourierApplyResult.failed();
  } catch (e) {
    debugPrint('courier_apply: $e');
    if (context.mounted) {
      _snack(context, context.tr('courier_apply_failed'), isError: true);
    }
    return const CourierApplyResult.failed();
  } finally {
    _courierApplyInFlight = false;
  }
}

/// Илова бўйича битта ариза сўрови (профил ва «＋» бир хил оқимни чақиради).
bool _courierApplyInFlight = false;

/// Хатода калит сақланади (жавоб йўқолган бўлиши мумкин), муваффақиятда тозаланади.
final IdempotencyKeys _courierApplyKeys = IdempotencyKeys(generator: newRequestId);
const String _courierScope = 'courier';

void _snack(BuildContext context, String msg, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: isError ? Colors.red.shade700 : null,
  ));
}
