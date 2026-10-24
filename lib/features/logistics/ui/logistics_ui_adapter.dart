// AVA LOGISTICS — ядро UI adapter'и (ИЖРОЧИ томони).
//
// Мижоз (жўнатувчи) ядро формасини ИШЛАТМАЙДИ: посилка «Жўнатма»
// бўлимидан буюртма + тўлов билан берилади (`createLogisticsOrder`),
// сервер эса LEG'ларни `demands` сифатида ўзи яратади. Шунинг учун бу
// adapter'да форма/валидация бўш — у фақат ижрочига келган LEG'ни
// карточка қилиб чизади ва «олиш → custody» амалларини беради.
//
// Ижрочи кўради: кузатув рақами, йўналиш (туман даражасида), ўлчам,
// ҲАҚ (бу унинг даромади). Мижоз нархи КЎРСАТИЛМАЙДИ (14-банд) — сервер
// уни проекцияга ёзмайди.

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../demand_offer/domain/demand_enums.dart';
import '../../demand_offer/domain/demand_match.dart';
import '../../demand_offer/domain/offer.dart';
import '../../demand_offer/ui_adapters/demand_ui_adapter.dart';
import '../domain/logistics_models.dart';
import 'leg_actions.dart';
import 'logistics_text.dart';

class LogisticsUiAdapter implements DemandUiAdapter {
  const LogisticsUiAdapter();

  @override
  DemandModule get module => DemandModule.logistics;

  @override
  String get primaryActionL10nKey => 'logistics_send';

  @override
  String get intentCardTitleL10nKey => 'logistics_title';

  @override
  DemandDraft newDraft({
    required String clientRequestId,
    String source = 'module',
  }) {
    return DemandDraft(
      module: DemandModule.logistics,
      clientRequestId: clientRequestId,
      source: source,
    );
  }

  @override
  void prefillFromIntent(DemandDraft draft, IntentResult intent) {
    draft.rawText = intent.rawText;
  }

  /// Ядро орқали юбориб БЎЛМАЙДИ (сервер схемаси ҳам рад этади) —
  /// фойдаланувчи «Жўнатма» бўлимига йўналтирилади.
  @override
  DraftValidation validate(DemandDraft draft) =>
      const DraftValidation({'module': 'logistics_use_send_screen'});

  @override
  List<ConfirmRow> buildConfirmRows(BuildContext context, DemandDraft draft) =>
      const [];

  @override
  Widget buildForm(
    BuildContext context,
    DemandDraft draft,
    VoidCallback onChanged,
  ) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        context.tr('logistics_use_send_screen'),
        style: TextStyle(fontSize: 13, color: c.ink2),
      ),
    );
  }

  @override
  Widget buildMatchCard(BuildContext context, DemandMatch match) =>
      LegMatchCard(match: match);

  /// Таклиф ЙЎҚ: нарх тарифдан (D-8), ижрочи «олиш» билан қабул қилади.
  @override
  Widget buildOfferCard(
    BuildContext context,
    Offer offer,
    VoidCallback? onChoose,
  ) =>
      const SizedBox.shrink();

  @override
  Widget? buildMatchActions(
    BuildContext context,
    DemandMatch match, {
    required String providerId,
  }) =>
      LogisticsLegActions(match: match, providerId: providerId);
}

/// Ижрочи кўрадиган LEG карточкаси — ПРОЕКЦИЯДАН.
class LegMatchCard extends StatelessWidget {
  const LegMatchCard({super.key, required this.match});

  final DemandMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final leg = LegProjection.fromAttributes(match.projection.attributes);
    final from = logisticsGeoLabel(leg.fromDistrictId);
    final to = logisticsGeoLabel(
      leg.toDistrictId.isNotEmpty ? leg.toDistrictId : leg.toRegionId,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: match.isNew ? c.brand : c.line,
          width: match.isNew ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (match.isNew)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
                ),
              Icon(Icons.local_post_office_rounded, size: 16, color: c.brand),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  leg.trackingNumber.isNotEmpty
                      ? leg.trackingNumber
                      : context.tr('logistics_parcel'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (leg.legCount > 1)
                _chip(
                  context,
                  Icons.alt_route,
                  '${context.tr('logistics_leg_step')} ${leg.legIndex + 1}/${leg.legCount}',
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.route_outlined, size: 14, color: c.ink2),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$from → $to',
                  style: TextStyle(fontSize: 13, color: c.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                context,
                Icons.scale_outlined,
                '${logisticsWeightLabel(leg.chargeableWeightG, gramUnit: context.tr('misc_unit_g'), kgUnit: context.tr('kg'))} · '
                    '${leg.lengthCm}×${leg.widthCm}×${leg.heightCm} ${context.tr('misc_unit_cm')}',
              ),
              if (leg.fragile)
                _chip(context, Icons.warning_amber_rounded, context.tr('logistics_fragile')),
              if (match.metrics.distanceKm != null)
                _chip(
                  context,
                  Icons.straighten,
                  '${context.tr('match_distance_from_you')} '
                      '${match.metrics.distanceKm!.toStringAsFixed(1)} ${context.tr('ev_trip_km')}',
                ),
            ],
          ),
          const SizedBox(height: 10),
          // ҲАҚ — ижрочининг даромади, карточкадаги энг муҳим рақам.
          Row(
            children: [
              Text(
                context.tr('logistics_leg_payout'),
                style: TextStyle(fontSize: 12, color: c.ink2),
              ),
              const Spacer(),
              Text(
                '${logisticsMoney(leg.payout)} ${context.tr('sum')}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: c.brand,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text) {
    final c = context.ava;
    // `Wrap` боласига чегара шарт — узун матн экрандан чиқиб кетмасин
    // (ServiceMatchCard'даги тажриба).
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.6,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.chip,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: c.ink2),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                style: TextStyle(fontSize: 11, color: c.ink2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
