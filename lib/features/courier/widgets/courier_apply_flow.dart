import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/idempotency_keys.dart';
import '../../../repositories/courier_capability_repository.dart';
import '../../../shared/widgets/celebration_dialog.dart';
import '../screens/courier_screen.dart';

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
/// Тасдиқланганда (эга, 2026-10-31): шу телефон учун БИРИНЧИ марта — табрик
/// (конфетти), «Курьер панели» босилгач курьер панели очилади ([openPanel]);
/// кейинги марталар — аввалги snack. Ариза юборилди / хато — snack.
///
/// Икки марта юбориш ҳимояси (C-2): сўров кетаётганда оқим қайта очилмайди
/// ([_courierApplyInFlight]); `requestId` муваффақиятгача бир хил — таймаутдан
/// кейин қайта уриниш ўша аризани сўрайди ([_courierApplyKeys]).
Future<CourierApplyResult> runCourierApplyFlow(
  BuildContext context, {
  CourierCapabilityRepository? repository,
  @visibleForTesting Future<void> Function(BuildContext context)? openPanel,
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
  final String status;
  try {
    status = await repo.apply(requestId: _courierApplyKeys.keyFor(_courierScope));
    _courierApplyKeys.settled(_courierScope);
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

  // Ариза сақланди — қолгани фақат хабар (у ердаги UI хатоси «ариза юборилмади» деб
  // кўрсатилмасин, шунинг учун try'дан ташқарида).
  if (!context.mounted) return CourierApplyResult.done(status);
  if (!CourierCapabilityRepository.panelStatuses.contains(status)) {
    _snack(context, context.tr('courier_apply_sent'));
    return CourierApplyResult.done(status);
  }
  // Тўхтатилган / ҳужжат рад этилган — табрик эмас (аввалги хабар ўзгармади).
  final celebrate =
      !CourierCapabilityRepository.finishOnlyStatuses.contains(status) &&
          await _claimCourierCelebration();
  if (!context.mounted) return CourierApplyResult.done(status);
  if (!celebrate) {
    _snack(context, context.tr('courier_apply_approved'));
    return CourierApplyResult.done(status);
  }
  await showCelebration(
    context,
    icon: Icons.delivery_dining_rounded,
    title: context.tr('courier_apply_approved_title'),
    subtitle: context.tr('courier_apply_approved_sub'),
    buttonLabel: context.tr('home_create_courier_open'),
  );
  if (context.mounted) await (openPanel ?? _openCourierPanel)(context);
  return CourierApplyResult.done(status);
}

/// «Бир марта» — шу телефон учун (`courier_approved_<телефон>`). Телефон номаълум бўлса
/// табрик йўқ (объектга боғлаб бўлмайди) — аввалги snack.
Future<bool> _claimCourierCelebration() async {
  String phone;
  try {
    final prefs = await SharedPreferences.getInstance();
    phone = canonicalPhoneId(prefs.getString('user_phone') ?? '');
  } catch (_) {
    return false;
  }
  if (phone.length < 9) return false;
  return CelebrationOnce.claim('courier_approved_$phone');
}

Future<void> _openCourierPanel(BuildContext context) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CourierScreen()),
    );

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
