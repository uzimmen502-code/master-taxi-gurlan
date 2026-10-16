import 'package:cloud_functions/cloud_functions.dart';

/// Ҳайдовчи БИТТА такси турини ўзи бекор қилади (`leaveDriverType` callable,
/// эга қарори 2026-10-16). Ҳамма текширув серверда: ўз ҳисоби, фаол ишнинг
/// йўқлиги, батч билан тозалаш. Клиент фақат натижани ҳикоя қилади.
enum DriverTypeLeaveResult {
  /// Тур олиб ташланди.
  left,

  /// Тур аллақачон йўқ эди (қайта чақирув) — ҳолат ўзгармади.
  alreadyLeft,

  /// Тур онлайн/фаол ёки қабул қилинган сафар бор — сервер рад этди.
  blockedActive,

  /// Тармоқ ёки сервер хатоси (диагностика серверда).
  failed,
}

/// Тест учун алмаштириладиган callable ижрочиси.
typedef LeaveTypeCallable = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> args);

Future<Map<String, dynamic>> _callServer(Map<String, dynamic> args) async {
  final res = await FirebaseFunctions.instance
      .httpsCallable('leaveDriverType')
      .call<Object?>(args);
  final d = res.data;
  return d is Map ? Map<String, dynamic>.from(d) : const <String, dynamic>{};
}

/// [taxiType] — `intercity` | `local` | `marshrut`.
Future<DriverTypeLeaveResult> leaveDriverType({
  required String uid,
  required String taxiType,
  LeaveTypeCallable? callable,
}) async {
  try {
    final d = await (callable ?? _callServer)({
      'userPhone': uid,
      'taxiType': taxiType,
    });
    if (d['ok'] != true) return DriverTypeLeaveResult.failed;
    return d['alreadyLeft'] == true
        ? DriverTypeLeaveResult.alreadyLeft
        : DriverTypeLeaveResult.left;
  } on FirebaseFunctionsException catch (e) {
    return e.code == 'failed-precondition'
        ? DriverTypeLeaveResult.blockedActive
        : DriverTypeLeaveResult.failed;
  } catch (_) {
    return DriverTypeLeaveResult.failed;
  }
}
