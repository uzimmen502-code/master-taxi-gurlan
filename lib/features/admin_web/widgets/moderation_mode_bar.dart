import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../services/admin_moderation_modes_service.dart';

/// Moderatsiya rejimi oqimi / o'rnatuvchisi (test uchun almashtiriladi).
typedef ModerationModeWatch = Stream<bool> Function();
typedef ModerationModeSet = Future<void> Function(bool enabled);

/// Barcha moderatsiya ekranlaridagi YAGONA «АВТО / ҚЎЛДА» paneli (ega 2026-11-28, audit C-1).
///
/// Avval har ekranda o'z nusxasi bor edi (`_TvAutoApproveBar`, `_MarketAutoApproveBar`, `_JobsAutoApproveBar`,
/// `_DatingAutoApproveBar`, Ulgurji `_AutoApproveBar` ×2, `_ShopAutoApproveBar`), yarmi `settings/app` ga
/// to'g'ridan-to'g'ri, auditsiz yozardi. Endi hammasi [AdminModerationModesService] → `adminSetModerationMode`.
class ModerationModeBar extends StatefulWidget {
  const ModerationModeBar({
    super.key,
    required this.mode,
    required this.onLabel,
    required this.offLabel,
    this.hint,
    this.confirmTitle,
    this.confirmBody,
    this.keyPrefix,
    this.margin = const EdgeInsets.fromLTRB(18, 10, 18, 0),
    this.watch,
    this.set,
    this.service,
  });

  /// [ModerationMode] dagi nom.
  final String mode;
  final String onLabel;
  final String offLabel;

  /// Ikkinchi qator (ixtiyoriy).
  final String? hint;

  /// Berilsa — АВТО yoqishdan oldin tasdiq oynasi.
  final String? confirmTitle;
  final String? confirmBody;

  /// Test kalitlari: `<prefix>_auto_bar`, `<prefix>_auto_manual`, `<prefix>_auto_on`, `<prefix>_auto_confirm`.
  final String? keyPrefix;
  final EdgeInsetsGeometry margin;

  final ModerationModeWatch? watch;
  final ModerationModeSet? set;
  final AdminModerationModesService? service;

  @override
  State<ModerationModeBar> createState() => _ModerationModeBarState();
}

class _ModerationModeBarState extends State<ModerationModeBar> {
  late final AdminModerationModesService _service = widget.service ?? AdminModerationModesService();
  late final Stream<bool> _stream = (widget.watch ?? () => _service.watch(widget.mode))();
  bool _busy = false;

  Key? _k(String suffix) => widget.keyPrefix == null ? null : ValueKey('${widget.keyPrefix}_$suffix');

  Future<void> _setAuto(bool enabled) async {
    if (enabled && widget.confirmTitle != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(widget.confirmTitle!),
          content: widget.confirmBody == null ? null : Text(widget.confirmBody!),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
            FilledButton(
              key: _k('auto_confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ёқиш'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await (widget.set ?? (v) => _service.set(widget.mode, v))(enabled);
    } catch (e) {
      debugPrint('[ModerationModeBar] ${widget.mode}=$enabled: $e');
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(
        backgroundColor: Colors.red.shade700,
        content: Text(moderationModeErrorText(e)),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Container(
            key: _k('auto_bar'),
            width: double.infinity,
            margin: widget.margin,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              'Модерация режимини юклаб бўлмади. Саҳифани янгиланг.',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          );
        }
        final auto = snap.data == true;
        final fg = auto ? AvaLight.ok : Colors.orange.shade900;
        return Container(
          key: _k('auto_bar'),
          width: double.infinity,
          margin: widget.margin,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: auto ? AvaLight.okSoft : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: auto ? AvaLight.ok : Colors.orange.shade200),
          ),
          child: Row(children: [
            Icon(auto ? Icons.flash_on : Icons.admin_panel_settings,
                color: auto ? AvaLight.ok : Colors.orange.shade800, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  auto ? widget.onLabel : widget.offLabel,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg),
                ),
                if (widget.hint != null) ...[
                  const SizedBox(height: 2),
                  Text(widget.hint!, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ],
              ]),
            ),
            if (_busy)
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            else ...[
              OutlinedButton(
                key: _k('auto_manual'),
                onPressed: auto ? () => _setAuto(false) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade800,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
                child: const Text('ҚЎЛДА', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: _k('auto_on'),
                onPressed: auto ? null : () => _setAuto(true),
                icon: const Icon(Icons.flash_on, size: 16),
                label: const Text('АВТО', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.button,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
              ),
            ],
          ]),
        );
      },
    );
  }
}

/// Foydalanuvchiga qisqa matn (25-band): diagnostik kod ichki logda, stack trace ko'rsatilmaydi.
String moderationModeErrorText(Object e) {
  var code = 'CLIENT_ERROR';
  if (e is FirebaseFunctionsException) {
    final d = e.details;
    code = (d is Map && d['code'] is String) ? d['code'] as String : e.code;
  }
  final text = switch (code) {
    'PERMISSION_DENIED' || 'permission-denied' => 'Бу созламани ўзгартиришга рухсатингиз йўқ',
    'UNAUTHENTICATED' || 'unauthenticated' => 'Қайта киринг',
    'MODE_RETIRED' => 'Бу созлама ишлатилмайди',
    _ => 'Сақлаб бўлмади. Қайта уриниб кўринг',
  };
  return '$text ($code)';
}
