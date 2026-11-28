import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../data/qr_login_api.dart';
import '../screens/qr_web_login_screen.dart';

/// Кириш экранларида (фақат веб): «Телефондаги AVA орқали QR билан кириш».
/// Сервер босқичи OFF бўлса — ҳеч нарса чизилмайди (бир марта probe, жараён давомида кеш).
class QrWebLoginEntry extends StatefulWidget {
  const QrWebLoginEntry({super.key, this.api, this.forceWeb = false, this.dark = false});

  final QrLoginApi? api;

  /// Тестлар учун (`kIsWeb` тестда false).
  final bool forceWeb;

  /// Тўқ фон (градиент) устида.
  final bool dark;

  static Future<bool>? _probe;

  @visibleForTesting
  static void resetProbeCache() => _probe = null;

  @override
  State<QrWebLoginEntry> createState() => _QrWebLoginEntryState();
}

class _QrWebLoginEntryState extends State<QrWebLoginEntry> {
  bool _enabled = false;

  bool get _isWeb => kIsWeb || widget.forceWeb;

  @override
  void initState() {
    super.initState();
    if (!_isWeb) return;
    final api = widget.api ?? FirebaseQrLoginApi();
    QrWebLoginEntry._probe ??= api.probeEnabled();
    QrWebLoginEntry._probe!.then((v) {
      if (mounted && v) setState(() => _enabled = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isWeb || !_enabled) return const SizedBox.shrink();
    final fg = widget.dark ? AppColors.onPrimary : AppColors.primaryText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OutlinedButton.icon(
        key: const ValueKey('qrl_web_entry'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => QrWebLoginScreen(api: widget.api)),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: fg.withValues(alpha: 0.6)),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.qr_code_2_rounded),
        label: Text(context.tr('qrl_web_entry_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
