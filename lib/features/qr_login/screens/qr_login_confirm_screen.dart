import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../data/qr_login_api.dart';
import '../qr_login_codes.dart';

/// Телефон: «Компьютерда киришни тасдиқлайсизми?» — браузер, тахминий жой, вақт, огоҳлантириш.
/// Натижа: `true` — тасдиқланди, `false`/`null` — йўқ.
class QrLoginConfirmScreen extends StatefulWidget {
  const QrLoginConfirmScreen({super.key, required this.sid, required this.api});

  final String sid;
  final QrLoginApi api;

  @override
  State<QrLoginConfirmScreen> createState() => _QrLoginConfirmScreenState();
}

class _QrLoginConfirmScreenState extends State<QrLoginConfirmScreen> {
  QrPeekResult? _info;
  String? _errorKey;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await widget.api.peek(widget.sid);
      if (mounted) setState(() => _info = info);
    } on QrLoginException catch (e) {
      if (mounted) setState(() => _errorKey = qrLoginErrorKey(e.code));
    } catch (_) {
      if (mounted) setState(() => _errorKey = 'qrl_err_generic');
    }
  }

  Future<void> _decide(bool approve) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.decide(widget.sid, approve: approve);
      if (mounted) Navigator.of(context).pop(approve);
    } on QrLoginException catch (e) {
      if (!mounted) return;
      if (!approve) {
        Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _busy = false;
        _errorKey = qrLoginErrorKey(e.code);
      });
    } catch (_) {
      if (!mounted) return;
      if (!approve) {
        Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _busy = false;
        _errorKey = 'qrl_err_generic';
      });
    }
  }

  String _time(int ms) {
    if (ms <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final info = _info;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('qrl_sessions_title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: info == null && _errorKey == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.computer_rounded, size: 56, color: AppColors.primaryText),
                    const SizedBox(height: 12),
                    Text(
                      context.tr('qrl_confirm_title'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 18),
                    if (info != null) ...[
                      _row(context, Icons.language_rounded, 'qrl_confirm_device',
                          info.browserLabel.isEmpty ? context.tr('qrl_unknown_device') : info.browserLabel),
                      if (info.approxCity.isNotEmpty)
                        _row(context, Icons.place_outlined, 'qrl_confirm_place', info.approxCity),
                      _row(context, Icons.schedule_rounded, 'qrl_confirm_time', _time(info.createdAtMs)),
                      const SizedBox(height: 14),
                      _note(context, context.tr('qrl_confirm_warning'), Colors.orange.shade50, Colors.orange.shade900),
                      const SizedBox(height: 8),
                      // Ега 2026-11-28: битта рақам — 1 та компьютер (олдинги компьютер чиқарилади).
                      _note(context, context.tr('qrl_confirm_one_computer'), c.surface, c.ink2),
                    ],
                    if (_errorKey != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        context.tr(_errorKey!),
                        key: const ValueKey('qrl_confirm_error'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
                      ),
                    ],
                    const Spacer(),
                    if (info != null && _errorKey == null)
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          key: const ValueKey('qrl_confirm_yes'),
                          onPressed: _busy ? null : () => _decide(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: AppColors.onPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(context.tr('qrl_confirm_yes'), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const ValueKey('qrl_confirm_no'),
                      onPressed: _busy
                          ? null
                          : () => info != null && _errorKey == null ? _decide(false) : Navigator.of(context).pop(false),
                      child: Text(context.tr('qrl_confirm_no')),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String labelKey, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.ava.ink2),
          const SizedBox(width: 10),
          Text('${context.tr(labelKey)}: ', style: TextStyle(color: context.ava.ink2)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 13, height: 1.35)),
    );
  }
}
