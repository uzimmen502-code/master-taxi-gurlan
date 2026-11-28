import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/navigation/app_home_route.dart';
import '../data/qr_login_api.dart';
import '../qr_login_codes.dart';
import '../services/qr_web_auth.dart';

/// Web: «Компьютерда AVA'га кириш» — QR (2 дақ., ўзи янгиланади), телефон сканерлаб тасдиқлайди.
///
/// Ҳолатни арзон кузатиш: `qr_login_watch/{watchId}` ҳужжатига битта listener (1 ўқиш + ҳар
/// ўзгаришда 1). Token Firestore'да йўқ — `approved` бўлгач `qrLoginConsume` (бир марталик).
class QrWebLoginScreen extends StatefulWidget {
  const QrWebLoginScreen({super.key, this.api, this.onSignedIn});

  final QrLoginApi? api;

  /// Тестлар учун; сукут — Firebase sign-in + бош саҳифа.
  final Future<void> Function(BuildContext context, QrConsumeResult result)? onSignedIn;

  @override
  State<QrWebLoginScreen> createState() => _QrWebLoginScreenState();
}

class _QrWebLoginScreenState extends State<QrWebLoginScreen> {
  late final QrLoginApi _api = widget.api ?? FirebaseQrLoginApi();
  QrStartResult? _qr;
  QrWatchState _state = QrWatchState.pending;
  String? _errorKey;
  bool _loading = false;
  bool _consuming = false;
  bool _stopped = false;
  int _cycles = 0;
  StreamSubscription<String>? _sub;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_newQr());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  Future<void> _newQr() async {
    _sub?.cancel();
    _expiryTimer?.cancel();
    setState(() {
      _loading = true;
      _errorKey = null;
      _stopped = false;
      _state = QrWatchState.pending;
    });
    try {
      final qr = await _api.start();
      if (!mounted) return;
      setState(() {
        _qr = qr;
        _loading = false;
      });
      _sub = _api.watch(qr.watchId).listen(_onStatus, onError: (_) {});
      final ms = qr.expiresAtMs - DateTime.now().millisecondsSinceEpoch;
      _expiryTimer = Timer(Duration(milliseconds: ms.clamp(1000, 5 * 60 * 1000) + 500), _onLocalExpiry);
    } on QrLoginException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _stopped = true;
        _errorKey = qrLoginErrorKey(e.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _stopped = true;
        _errorKey = 'qrl_err_generic';
      });
    }
  }

  void _onStatus(String status) {
    if (!mounted) return;
    final st = qrWatchStateOf(status);
    switch (st) {
      case QrWatchState.scanned:
        setState(() => _state = st);
      case QrWatchState.approved:
        setState(() => _state = st);
        unawaited(_consume());
      case QrWatchState.rejected:
        _halt(st, 'qrl_web_rejected');
      case QrWatchState.expired:
        _onLocalExpiry();
      case QrWatchState.pending:
      case QrWatchState.consumed:
      case QrWatchState.unknown:
        break;
    }
  }

  void _halt(QrWatchState st, String key) {
    _sub?.cancel();
    _expiryTimer?.cancel();
    setState(() {
      _state = st;
      _stopped = true;
      _errorKey = key;
    });
  }

  void _onLocalExpiry() {
    if (!mounted || _consuming || _stopped) return;
    if (_state == QrWatchState.approved) return;
    if (_cycles < kQrAutoRefreshMax) {
      _cycles += 1;
      unawaited(_newQr());
    } else {
      _halt(QrWatchState.expired, 'qrl_web_expired');
    }
  }

  Future<void> _consume() async {
    final qr = _qr;
    if (_consuming || qr == null) return;
    _consuming = true;
    _expiryTimer?.cancel();
    try {
      final r = await _api.consume(sid: qr.sid, secret: qr.secret);
      _sub?.cancel();
      if (!mounted) return;
      final done = widget.onSignedIn ?? _defaultSignedIn;
      await done(context, r);
    } on QrLoginException catch (e) {
      if (mounted) _halt(QrWatchState.expired, qrLoginErrorKey(e.code));
    } catch (_) {
      if (mounted) _halt(QrWatchState.expired, 'qrl_err_generic');
    } finally {
      _consuming = false;
    }
  }

  static Future<void> _defaultSignedIn(BuildContext context, QrConsumeResult r) async {
    await QrWebAuth.completeSignIn(r);
    if (context.mounted) pushAppHome(context);
  }

  void _manualRefresh() {
    _cycles = 0;
    unawaited(_newQr());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('qrl_web_title'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _qrBox(context),
                const SizedBox(height: 20),
                _step(context, 1, 'qrl_web_step1'),
                _step(context, 2, 'qrl_web_step2'),
                _step(context, 3, 'qrl_web_step3'),
                const SizedBox(height: 14),
                Text(
                  context.tr('qrl_web_note'),
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: c.ink2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _qrBox(BuildContext context) {
    final qr = _qr;
    Widget inner;
    if (_loading && qr == null) {
      inner = const SizedBox(height: 240, child: Center(child: CircularProgressIndicator()));
    } else if (_stopped || qr == null) {
      inner = SizedBox(
        height: 240,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              context.tr(_errorKey ?? 'qrl_web_expired'),
              key: const ValueKey('qrl_status_text'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              key: const ValueKey('qrl_refresh'),
              onPressed: _loading ? null : _manualRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.tr('qrl_web_refresh')),
            ),
          ],
        ),
      );
    } else {
      final busy = _state == QrWatchState.scanned || _state == QrWatchState.approved;
      inner = Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: busy ? 0.15 : 1,
            child: QrImageView(
              key: const ValueKey('qrl_qr'),
              data: qr.qrPayload,
              size: 240,
              backgroundColor: Colors.white,
            ),
          ),
          if (busy)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  context.tr(_state == QrWatchState.approved ? 'qrl_web_signing_in' : 'qrl_web_scanned'),
                  key: const ValueKey('qrl_status_text'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.ava.line),
      ),
      child: Center(child: inner),
    );
  }

  Widget _step(BuildContext context, int n, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primary,
            child: Text('$n', style: const TextStyle(fontSize: 12, color: AppColors.onPrimary, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(context.tr(key), style: const TextStyle(fontSize: 14.5, height: 1.35))),
        ],
      ),
    );
  }
}
