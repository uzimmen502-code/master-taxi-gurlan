import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../favorites_controller.dart';
import '../screens/favorites_screen.dart';

/// Бош саҳифа юқори ўнг бурчагида «❤ N» (эга 2026-11-15): фақат N > 0 бўлса кўринади,
/// босилса «Танланганлар» экрани (Кабинетда эмас).
class FavoritesTopChip extends StatefulWidget {
  const FavoritesTopChip({super.key, this.controller, this.onOpen});

  final FavoritesController? controller;

  /// Тест учун; бўлмаса [FavoritesScreen] очилади.
  final VoidCallback? onOpen;

  @override
  State<FavoritesTopChip> createState() => _FavoritesTopChipState();
}

class _FavoritesTopChipState extends State<FavoritesTopChip> {
  FavoritesController get _c => widget.controller ?? FavoritesController.instance;

  @override
  void initState() {
    super.initState();
    _c.ensureStarted();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final n = _c.count;
        if (n <= 0) return const SizedBox.shrink(key: ValueKey('fav_top_chip_hidden'));
        final c = context.ava;
        final label = '${context.tr('fav_title')}: $n';
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Semantics(
            button: true,
            label: label,
            child: InkWell(
              key: const ValueKey('fav_top_chip'),
              borderRadius: BorderRadius.circular(AvaRadius.chip),
              onTap: widget.onOpen ??
                  () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FavoritesScreen())),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AvaTap.minSize),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.favorite_rounded, size: 18, color: AvaLight.danger),
                    const SizedBox(width: 3),
                    Text(n > 99 ? '99+' : '$n', style: AvaText.caption.copyWith(color: c.ink, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
