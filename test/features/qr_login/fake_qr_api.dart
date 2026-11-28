import 'dart:async';

import 'package:ava_gurlan/features/qr_login/data/qr_login_api.dart';

/// Firebase'сиз сохта callable'лар (виджет тестлари учун).
class FakeQrApi implements QrLoginApi {
  final StreamController<String> watchCtrl = StreamController<String>.broadcast();

  bool probe = true;
  int starts = 0;
  Object? startError;
  int expiresInMs = 120000;

  QrPeekResult peekResult = const QrPeekResult(
    sid: 'a',
    browserLabel: 'Chrome · Windows',
    approxCity: 'Urgench',
    createdAtMs: 1,
    expiresAtMs: 2,
    outflowBlockHours: 24,
  );
  Object? peekError;
  final List<bool> decisions = [];
  Object? decideError;

  final List<String> consumed = [];
  Object? consumeError;

  QrWebSessionsList list = const QrWebSessionsList(enabled: true, canManage: true, items: [
    QrWebSessionItem(webSessionId: 'w1', browserLabel: 'Chrome · Windows', lastActiveAtMs: 1),
  ]);
  int listCalls = 0;
  final List<String?> revokedIds = [];
  bool revokedAll = false;

  @override
  Future<bool> probeEnabled() async => probe;

  @override
  Future<QrStartResult> start() async {
    starts += 1;
    if (startError != null) throw startError!;
    return QrStartResult(
      sid: 'sid$starts'.padRight(32, '0'),
      secret: 'secret$starts',
      watchId: 'watch$starts',
      qrPayload: 'AVAQR1:${'sid$starts'.padRight(32, '0')}',
      expiresAtMs: DateTime.now().millisecondsSinceEpoch + expiresInMs,
    );
  }

  @override
  Stream<String> watch(String watchId) => watchCtrl.stream;

  @override
  Future<QrConsumeResult> consume({required String sid, required String secret}) async {
    consumed.add('$sid|$secret');
    if (consumeError != null) throw consumeError!;
    return QrConsumeResult(customToken: 't', phone: '998901234567', webSessionId: 'ws', renewSecret: 'rs');
  }

  @override
  Future<QrPeekResult> peek(String sid) async {
    if (peekError != null) throw peekError!;
    return peekResult;
  }

  @override
  Future<void> decide(String sid, {required bool approve}) async {
    decisions.add(approve);
    if (decideError != null) throw decideError!;
  }

  @override
  Future<QrWebSessionsList> listSessions() async {
    listCalls += 1;
    return list;
  }

  @override
  Future<int> revoke({String? webSessionId, bool all = false}) async {
    revokedIds.add(webSessionId);
    revokedAll = revokedAll || all;
    return 1;
  }
}
