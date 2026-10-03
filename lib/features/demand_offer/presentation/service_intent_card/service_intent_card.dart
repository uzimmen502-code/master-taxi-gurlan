// P0.3 — ХИЗМАТ INTENT КАРТОЧКАСИ.
//
// Эга қарори (2026-10-03): «Уста чақириш» алоҳида катта тугма ЭМАС.
// АСОСИЙ кириш нуқтаси — AVA'дан қидириш майдони.
//
// Оқим (эга спецификацияси):
//   қидирув → intent аниқлаш → МАВЖУД натижаларни кўрсатиш
//   → моси топилмаса: «Таклиф олиш» → сўров яратиш
//
// КАРТОЧКА ФОРМА ЭМАС (концепция қатъий қоидаси):
//   «Хизмат карточкаси форма эмас. AVA адашса, фойдаланувчи карточкани
//    ўтказиб, оддий натижаларни кўради.»
// Шунинг учун у натижаларни ЯШИРМАЙДИ ва ёпилиши шарт эмас — фақат
// таклиф қилади.

import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/ava_tokens.dart';
import '../../domain/demand_enums.dart';
import '../../ui_adapters/demand_ui_adapter.dart';

/// Карточка қандай ҳолатда кўрсатилади.
enum IntentCardPlacement {
  /// Натижалар бор — карточка рўйхат ОХИРИДА, камтарона.
  belowResults,

  /// Натижа йўқ — карточка асосий таклиф, кўринарли.
  noResults,
}

class ServiceIntentCard extends StatelessWidget {
  const ServiceIntentCard({
    super.key,
    required this.intent,
    required this.placement,
    required this.onContinue,
    this.categoryNameResolver,
    this.moduleLabelResolver,
  });

  final IntentResult intent;
  final IntentCardPlacement placement;

  /// Тасдиқланганда — сўров формаси ёки мавжуд модул экрани очилади.
  final void Function(IntentResult intent) onContinue;

  /// `categoryId` → кўринадиган ном (`IntentRouter.categoryName`).
  final String Function(String categoryId)? categoryNameResolver;

  /// Модул → кўринадиган ном.
  final String Function(DemandModule module)? moduleLabelResolver;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final compact = placement == IntentCardPlacement.belowResults;

    return Container(
      margin: EdgeInsets.only(top: compact ? 0 : 4),
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: compact ? c.chip : c.brandSoft,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(
          color: compact ? c.line : c.brand.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Натижа бор бўлганда — «Моси топилмадими?».
          // Натижа йўқ бўлганда — AVA нимани тушунганини айтади.
          Row(
            children: [
              Icon(
                compact ? Icons.help_outline : Icons.auto_awesome_outlined,
                size: 15,
                color: compact ? c.ink2 : c.brand,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  compact
                      ? context.tr('intent_no_match')
                      : context.tr('intent_understood_as'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: compact ? c.ink2 : c.brand,
                  ),
                ),
              ),
            ],
          ),

          // AVA нимани тушунди — қисқа, фойдаланувчи тилида.
          if (!compact) ...[
            const SizedBox(height: 6),
            Text(
              _understoodLine(context),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ],

          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => onContinue(intent),
              style: FilledButton.styleFrom(
                backgroundColor: compact ? c.surface : c.brand,
                foregroundColor: compact ? c.brand : c.brandInk,
                padding: EdgeInsets.symmetric(vertical: compact ? 9 : 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: compact
                      ? BorderSide(color: c.brand.withValues(alpha: 0.4))
                      : BorderSide.none,
                ),
              ),
              child: Text(
                _ctaLabel(context),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Тугма матни.
  ///
  /// Эга хабари: «Моси топилмадими? → Таклиф олиш» ЁКИ тўғридан-тўғри
  /// «Уста топиш».
  ///
  /// Шунинг учун:
  ///   хизмат + аниқ категория  → «Уста топиш» (аниқ ҳаракат)
  ///   хизмат, категория йўқ    → «Уста топиш» (категория кейин сўралади)
  ///   бошқа модул              → «Очиш» (мавжуд экран)
  ///   натижа бор, ноаниқ       → «Таклиф олиш»
  String _ctaLabel(BuildContext context) {
    if (intent.module == DemandModule.service) {
      return context.tr('intent_find_master');
    }
    if (intent.module != null && !intent.coreReady) {
      return context.tr('intent_open_module');
    }
    return context.tr('intent_get_offers');
  }

  /// «AVA шундай тушунди» қатори.
  ///
  /// Техник сўз ЙЎҚ: модул номи ва ажратилган маълумот фойдаланувчи
  /// тилида кўрсатилади.
  String _understoodLine(BuildContext context) {
    final parts = <String>[];

    // Модул номи.
    final m = intent.module;
    if (m != null) {
      parts.add(moduleLabelResolver?.call(m) ?? _fallbackModuleLabel(context, m));
    }

    // Категория (хизмат).
    final cat = intent.categoryId;
    if (cat != null) {
      parts.add(categoryNameResolver?.call(cat) ?? cat);
    } else if (intent.needsChoice) {
      parts.add(context.tr('intent_choose_category'));
    }

    // Ажратилган маълумот — концепция: «"Тошкентга посилка" деса,
    // "Қаерга" майдонида Тошкент туради.»
    if (intent.rooms != null) {
      parts.add('${intent.rooms} ${context.tr('intent_rooms')}');
    }
    if (intent.quantity != null) {
      parts.add('${intent.quantity} ${context.tr('intent_quantity')}');
    }
    if (intent.destinationHint != null) {
      parts.add('${context.tr('intent_destination')}: ${intent.destinationHint}');
    }

    return parts.isEmpty ? intent.rawText : parts.join(' · ');
  }

  String _fallbackModuleLabel(BuildContext context, DemandModule m) {
    switch (m) {
      case DemandModule.service:
        return context.tr('intent_card_service');
      default:
        return context.tr('intent_get_offers');
    }
  }
}
