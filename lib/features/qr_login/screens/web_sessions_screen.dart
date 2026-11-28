import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../data/qr_login_api.dart';
import '../qr_login_codes.dart';
import 'qr_login_confirm_screen.dart';
import 'qr_scan_screen.dart';

/// Телефон: «Компьютерда кириш» — QR сканерлаш, фаол web киришлар ва «Чиқиш».
/// Бошқариш (сканер/чиқиш) фақат рақам боғланган асосий телефонда (сервер текширади).
class WebSessionsScreen extends StatefulWidget {
  const WebSessionsScreen({super.key, this.api, this.scan});

  final QrLoginApi? api;

  /// Тестлар учун сканер ўрнига (`sid` қайтаради).
  final Future<String?> Function(BuildContext context)? scan;

  @override
  State<WebSessionsScreen> createState() => _WebSessionsScreenState();
}

class _WebSessionsScreenState extends State<WebSessionsScreen> {
  late final QrLoginApi _api = widget.api ?? FirebaseQrLoginApi();
  QrWebSessionsList? _list;
  String? _errorKey;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final l = await _api.listSessions();
      if (mounted) {
        setState(() {
          _list = l;
          _errorKey = null;
        });
      }
    } on QrLoginException catch (e) {
      if (mounted) setState(() => _errorKey = qrLoginErrorKey(e.code));
    } catch (_) {
      if (mounted) setState(() => _errorKey = 'qrl_err_generic');
    }
  }

  void _snack(String key) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr(key))));
  }

  Future<void> _scan() async {
    final sid = await (widget.scan ?? _defaultScan)(context);
    if (!mounted || sid == null || sid.isEmpty) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => QrLoginConfirmScreen(sid: sid, api: _api)),
    );
    if (!mounted) return;
    if (ok == true) {
      _snack('qrl_confirm_done');
      // Web token олиши бир неча сония — рўйхатни бироздан кейин янгилаймиз.
      unawaited(Future<void>.delayed(const Duration(seconds: 3), _reload));
    }
  }

  static Future<String?> _defaultScan(BuildContext context) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const QrScanScreen()));

  Future<void> _revoke({String? id, bool all = false}) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ctx.tr(all ? 'qrl_logout_all' : 'qrl_logout_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('qrl_confirm_no'))),
          TextButton(
            key: const ValueKey('qrl_logout_yes'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('qrl_disconnect')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.revoke(webSessionId: id, all: all);
      if (mounted) _snack('qrl_logout_done');
    } on QrLoginException catch (e) {
      if (mounted) _snack(qrLoginErrorKey(e.code));
    } catch (_) {
      if (mounted) _snack('qrl_err_generic');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _reload();
  }

  String _when(int ms) {
    if (ms <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final l = _list;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('qrl_sessions_title'))),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (l == null && _errorKey == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (_errorKey != null)
              Text(context.tr(_errorKey!), style: TextStyle(color: Colors.red.shade700)),
            if (l != null) ...[
              Text(context.tr('qrl_sessions_intro'), style: TextStyle(color: c.ink2, height: 1.35)),
              const SizedBox(height: 14),
              if (!l.enabled)
                Text(context.tr('qrl_disabled'), key: const ValueKey('qrl_disabled_text'), style: TextStyle(color: c.ink2))
              else if (!l.canManage)
                Text(context.tr('qrl_not_main_phone'), style: TextStyle(color: c.ink2))
              else
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    key: const ValueKey('qrl_scan_btn'),
                    onPressed: _busy ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: Text(context.tr('qrl_scan_btn'), style: const TextStyle(fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      foregroundColor: AppColors.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              Text(context.tr('qrl_sessions_active'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              if (l.items.isEmpty)
                Text(context.tr('qrl_sessions_empty'), style: TextStyle(color: c.ink2)),
              for (final s in l.items)
                Card(
                  key: ValueKey('qrl_session_${s.webSessionId}'),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.computer_rounded),
                          title: Text(s.browserLabel.isEmpty ? context.tr('qrl_unknown_device') : s.browserLabel),
                          subtitle: Text([
                            if (s.approxCity.isNotEmpty) s.approxCity,
                            context.tr('qrl_session_last_active').replaceAll('{time}', _when(s.lastActiveAtMs)),
                          ].join(' · ')),
                        ),
                        // Эга 2026-11-28: «телефонда исталган пайтда Компьютерни тизимдан чиқариш».
                        if (l.canManage)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: ElevatedButton.icon(
                              key: ValueKey('qrl_logout_${s.webSessionId}'),
                              onPressed: _busy ? null : () => _revoke(id: s.webSessionId),
                              icon: const Icon(Icons.logout_rounded),
                              label: Text(context.tr('qrl_disconnect'), style: const TextStyle(fontWeight: FontWeight.w800)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(46),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (l.canManage && l.items.length > 1) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const ValueKey('qrl_logout_all'),
                  onPressed: _busy ? null : () => _revoke(all: true),
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(context.tr('qrl_logout_all')),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
