import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../data/market_taxonomy_repository.dart';
import '../domain/market_taxonomy.dart';

/// Эълон тафсилотидаги бозор майдонлари (6-босқич): бозор · бўлим, «Импорт» ва `attrs` — таксономия номлари
/// билан, илова тилида. Таксономия сеанс кешидан (ўқиш бир марта); бозор/майдон топилмаса — ҳеч нарса.
class MarketAttrsSection extends StatefulWidget {
  const MarketAttrsSection({
    super.key,
    required this.market,
    required this.category,
    required this.attrs,
    this.imported,
    this.loadTaxonomy,
  });

  final String market;
  final String category;
  final Map<String, Object?> attrs;
  final bool? imported;

  /// Тест учун (бўлмаса [MarketTaxonomyRepository.load]).
  final Future<MarketTaxonomy> Function()? loadTaxonomy;

  @override
  State<MarketAttrsSection> createState() => _MarketAttrsSectionState();
}

class _MarketAttrsSectionState extends State<MarketAttrsSection> {
  late final Future<MarketTaxonomy> _future = (widget.loadTaxonomy ?? MarketTaxonomyRepository.load)();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MarketTaxonomy>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) debugPrint('[MarketAttrs] taxonomy: ${snap.error}');
        final m = snap.data?.market(widget.market);
        if (m == null) return const SizedBox.shrink();
        final lang = context.contentLang;
        final category = m.autoCategory ?? widget.category;
        final cat = m.hasCategoryChoice ? m.category(category) : null;
        final rows = marketAttrRows(m, category, widget.attrs, lang, yes: context.tr('yes'), tr: context.tr);
        final header = [m.label(lang), if (cat != null) cat.label(lang)].join(' · ');
        return Container(
          key: const ValueKey('market_attrs'),
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(header,
                      key: const ValueKey('market_attrs_header'),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                if (m.hasImported && widget.imported == true)
                  Chip(
                    key: const ValueKey('market_attrs_imported'),
                    label: Text(context.tr('market_imported')),
                    visualDensity: VisualDensity.compact,
                  ),
              ]),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(value,
                            textAlign: TextAlign.end,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
