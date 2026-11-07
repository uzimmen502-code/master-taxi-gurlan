// AVA LOGISTICS — йўл бўлакларини йиғиш ҳолати (эга 2026-11-07).
//
// Жўнатувчи ва курьер экранида битта виджет. Ҳолат СЕРВЕРДАН
// (`shipments/{id}.chain`), бу ерда фақат кўрсатилади (44-банд).
// Фойдаланувчи ички сўзларни кўрмайди (45-банд): «бўлак», «йўл бўлаклари».
//
//   assembling → «Йўл бўлаклари йиғилмоқда: N/M · муддат … (… қолди)»
//                + жўнатувчига: муддатда йиғилмаса пул ҳамёнга қайтади
//   locked     → курьерга: «Ҳамма бўлакка курьер топилди»; жўнатувчига — ҳеч
//                нарса (оддий кузатув)
//   expired    → иккаласига ҳам изоҳ
//   бошқа      → ҳеч нарса

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../domain/logistics_models.dart';
import '../ui/logistics_text.dart';

class ChainStatusBanner extends StatefulWidget {
  const ChainStatusBanner({
    super.key,
    required this.chain,
    this.forSender = false,
    this.legCountFallback = 0,
    this.clock,
  });

  final ShipmentChain chain;

  /// `true` — жўнатувчи экрани (пул қайтиши ҳақида изоҳ), `false` — курьер.
  final bool forSender;

  /// `chain.legCount` бўлмаса — жўнатма ҳужжатидаги `legCount`.
  final int legCountFallback;

  /// Тест учун соат.
  final DateTime Function()? clock;

  @override
  State<ChainStatusBanner> createState() => _ChainStatusBannerState();
}

class _ChainStatusBannerState extends State<ChainStatusBanner> {
  Timer? _tick;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant ChainStatusBanner old) {
    super.didUpdateWidget(old);
    _syncTimer();
  }

  /// Қолган вақт дақиқа аниқлигида — дақиқада бир марта қайта чизиш етарли.
  void _syncTimer() {
    final need = widget.chain.isAssembling && widget.chain.deadlineAt != null;
    if (need && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    } else if (!need) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.chain;
    if (ch.isAssembling) return _assembling(context, ch);
    if (ch.isExpired) {
      return _box(
        context,
        key: const ValueKey('chain-expired'),
        icon: Icons.history_toggle_off_rounded,
        tone: _Tone.danger,
        lines: [context.tr(widget.forSender ? 'logistics_chain_expired_sender' : 'logistics_chain_expired_provider')],
      );
    }
    if (ch.isLocked && !widget.forSender) {
      return _box(
        context,
        key: const ValueKey('chain-locked'),
        icon: Icons.check_circle_outline,
        tone: _Tone.ok,
        lines: [context.tr('logistics_chain_locked')],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _assembling(BuildContext context, ShipmentChain ch) {
    final total = ch.legCount > 0 ? ch.legCount : widget.legCountFallback;
    final lines = <String>[
      context.trMsg('logistics_chain_assembling', params: {
        'claimed': '${ch.claimed}',
        'total': '$total',
      }),
    ];
    final left = ch.remaining(_now());
    if (left != null) {
      final p = chainRemainingParts(left);
      lines.add(context.trMsg('logistics_chain_deadline', params: {
        'time': logisticsDateLabel(ch.deadlineAt),
        'left': context.trMsg('logistics_chain_left', params: {
          'h': '${p.hours}',
          'm': p.minutes.toString().padLeft(2, '0'),
        }),
      }));
    }
    if (widget.forSender) lines.add(context.tr('logistics_chain_sender_note'));
    return _box(
      context,
      key: const ValueKey('chain-assembling'),
      icon: Icons.hourglass_top_rounded,
      tone: _Tone.warn,
      lines: lines,
    );
  }

  Widget _box(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required _Tone tone,
    required List<String> lines,
  }) {
    final c = context.ava;
    final (bg, fg) = switch (tone) {
      _Tone.warn => (c.warnSoft, c.warn),
      _Tone.ok => (c.okSoft, c.ok),
      _Tone.danger => (c.dangerSoft, c.danger),
    };
    return Container(
      key: key,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lines.length; i += 1)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 3),
                    child: Text(
                      lines[i],
                      style: TextStyle(
                        fontSize: i == 0 ? 13 : 12,
                        fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                        color: i == 0 ? fg : c.ink2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Tone { warn, ok, danger }
