import 'package:flutter/material.dart';

import '../l10n/l10n_extension.dart';
import '../theme/ava_tokens.dart';

/// Пуллик жойлашув томошабинга/харидорга очиқ «Реклама» деб белгиланади.
///
/// Аввал бу белги фақат AVAGram'да эди (`TvAdLabel`, 8-босқич, 2026-10-25).
/// Кўчмас мулкнинг пуллик РЕКЛАМА/СРОЧНО эълонлари ҳам харидорга белгисиз
/// кўринарди — шунинг учун кўриниш битта жойда: модуллар фақат ШАРТНИ
/// ўзи текширади (масалан `TvClip.isAd`, `RealtyListing.isPromoted`),
/// белгининг шакли эса шу ерда.
///
/// Матн — мавжуд `tv_ad_label` калити (Реклама / Reklama / Реклама),
/// янги калит очилмаган: маъноси бир хил, учта тилда аллақачон бор.
class AvaAdBadge extends StatelessWidget {
  const AvaAdBadge({
    super.key,
    this.compact = false,
    this.inline = false,
    this.boxKey = const ValueKey('ava_ad_badge'),
  });

  /// Кичик карточкалар учун (постер устида, қатор ичида).
  final bool compact;

  /// Бош саҳифанинг 14 px матн қатори учун: қутисиз, фақат матн —
  /// қутили белги у ерга сиғмай қатор ташқарисига чиқарди.
  final bool inline;

  /// Тестлар белгини шу калит бўйича топади. AVAGram эски калитни
  /// (`tv_ad_label`) сақлаш учун ўзиникини беради.
  final Key boxKey;

  @override
  Widget build(BuildContext context) {
    final text = context.tr('tv_ad_label');
    if (inline) {
      return Semantics(
        label: text,
        excludeSemantics: true,
        child: Text(
          text,
          key: boxKey,
          maxLines: 1,
          style: AvaText.feedRow.copyWith(
            fontWeight: FontWeight.w700,
            color: context.ava.ink3,
          ),
        ),
      );
    }
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        key: boxKey,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white70, width: 0.8),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: compact ? 1 : 2),
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: compact ? 1.2 : 1.3,
            ),
          ),
        ),
      ),
    );
  }
}
