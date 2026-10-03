// `service` модулининг UI adapter'и — P0 ПИЛОТИ.
//
// Нега айни шу модул пилот (Т-17, эга қарори Қ-1): бугун бу оқим
// УМУМАН ЙЎҚ. Одамлар `ads`га «электрикман» деб эълон бериб, мижоз
// ўзи топиб қўнғироқ қилишини кутади. Шунинг учун кўчириладиган
// маълумот ҳам, dual-write ҳам, бузиладиган production оқими ҳам йўқ.
//
// Форма АТАЙЛАБ қисқа: ҳар қўшимча майдон формани узайтиради ва
// тўлдирилмай қолади. Усталарга керакли минимум:
//   - қандай иш (категория)
//   - қаерда (жойлашув)
//   - қачон
//   - қанчагача (ихтиёрий)
//   - расм ва изоҳ (ихтиёрий)

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../domain/demand_enums.dart';
import '../domain/demand_match.dart';
import '../domain/offer.dart';
import 'demand_ui_adapter.dart';

class ServiceUiAdapter implements DemandUiAdapter {
  const ServiceUiAdapter();

  @override
  DemandModule get module => DemandModule.service;

  @override
  String get primaryActionL10nKey => 'request_call_master';

  @override
  String get intentCardTitleL10nKey => 'intent_card_service';

  @override
  DemandDraft newDraft({
    required String clientRequestId,
    String source = 'module',
  }) {
    return DemandDraft(
      module: DemandModule.service,
      clientRequestId: clientRequestId,
      source: source,
      timeMode: 'today',
      attributes: <String, dynamic>{
        'visitType': 'at_my_place',
        'preferredTimeOfDay': 'any',
      },
    );
  }

  @override
  void prefillFromIntent(DemandDraft draft, IntentResult intent) {
    draft.source = 'intent_card';
    draft.inputType = 'text';
    draft.rawText = intent.rawText;

    // Кўп маъноли калит сўз бўлса категория ҚЎЙИЛМАЙДИ — фойдаланувчи
    // ўзи танлайди («котёл» → газ устаси ёки иситиш тизими).
    if (!intent.needsChoice && intent.categoryId != null) {
      draft.categoryId = intent.categoryId;
    }

    // Матндан тушунилган сарлавҳа — лекин фойдаланувчи кўрган матн,
    // техник шакл эмас.
    if (draft.title.isEmpty && intent.rawText.trim().isNotEmpty) {
      final t = intent.rawText.trim();
      draft.title = t.length <= 120 ? t : t.substring(0, 120);
    }
  }

  @override
  DraftValidation validate(DemandDraft draft) {
    final errors = <String, String>{};

    if (draft.categoryId == null || draft.categoryId!.isEmpty) {
      errors['categoryId'] = 'request_what_needed';
    }
    // Усте мижозга борадиган бўлса жойлашув ШАРТ — акс ҳолда ким
    // мослигини аниқлаб бўлмайди.
    final visitType = draft.attributes['visitType'] ?? 'at_my_place';
    if (visitType == 'at_my_place' &&
        (draft.location == null || !draft.location!.hasCoords)) {
      errors['location'] = 'request_where';
    }
    if (draft.title.trim().length < 3 && draft.description.trim().isEmpty) {
      errors['title'] = 'request_describe';
    }
    // Сервер ҳам текширади (JSON Schema), лекин фойдаланувчига дарҳол
    // айтиш яхшироқ.
    if (draft.budgetMax != null && draft.budgetMax! <= 0) {
      errors['budgetMax'] = 'request_budget';
    }

    return DraftValidation(errors);
  }

  @override
  List<ConfirmRow> buildConfirmRows(BuildContext context, DemandDraft draft) {
    final rows = <ConfirmRow>[];

    rows.add(ConfirmRow(
      labelKey: 'request_what_needed',
      value: _categoryLabel(context, draft.categoryId),
      editField: 'categoryId',
      icon: Icons.build_outlined,
    ));

    if (draft.location != null) {
      rows.add(ConfirmRow(
        labelKey: 'request_where',
        // ДИҚҚАТ: тасдиқлаш экрани фойдаланувчининг ЎЗИГА кўрсатилади,
        // шунинг учун аниқ манзил кўрсатилади. Таклифчига борадиган
        // проекцияда эса фақат тахминий нуқта бўлади (Т-20).
        value: draft.location!.addressText.isNotEmpty
            ? draft.location!.addressText
            : context.tr('request_where'),
        editField: 'location',
        icon: Icons.location_on_outlined,
      ));
    }

    rows.add(ConfirmRow(
      labelKey: 'request_when',
      value: _timeLabel(context, draft),
      editField: 'timeMode',
      icon: Icons.schedule_outlined,
    ));

    if (draft.budgetMax != null) {
      rows.add(ConfirmRow(
        labelKey: 'request_budget',
        value: '${_money(draft.budgetMax!)} ${context.tr('sum')}',
        editField: 'budgetMax',
        icon: Icons.payments_outlined,
      ));
    }

    if (draft.description.trim().isNotEmpty) {
      rows.add(ConfirmRow(
        labelKey: 'request_describe',
        value: draft.description.trim(),
        editField: 'description',
        icon: Icons.notes_outlined,
      ));
    }

    if (draft.images.isNotEmpty) {
      rows.add(ConfirmRow(
        labelKey: 'request_add_photo',
        value: '${draft.images.length}',
        editField: 'images',
        icon: Icons.photo_outlined,
      ));
    }

    return rows;
  }

  @override
  Widget buildForm(
    BuildContext context,
    DemandDraft draft,
    VoidCallback onChanged,
  ) {
    return ServiceDemandForm(draft: draft, onChanged: onChanged);
  }

  @override
  Widget buildMatchCard(BuildContext context, DemandMatch match) {
    return ServiceMatchCard(match: match);
  }

  @override
  Widget buildOfferCard(
    BuildContext context,
    Offer offer,
    VoidCallback? onChoose,
  ) {
    return ServiceOfferCard(offer: offer, onChoose: onChoose);
  }

  // ── Ёрдамчилар ──────────────────────────────────────────────────────

  String _categoryLabel(BuildContext context, String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) {
      return context.tr('request_what_needed');
    }
    // Категория номлари `taxonomy` коллекциясидан келади (13.6.1).
    // Ҳозирча калит сифатида ишлатилади; топилмаса калитнинг ўзи
    // қайтади ва экран бузилмайди.
    return context.tr('category_$categoryId');
  }

  String _timeLabel(BuildContext context, DemandDraft draft) {
    switch (draft.timeMode) {
      case 'now':
        return context.tr('request_when_now');
      case 'today':
        return context.tr('request_when_today');
      default:
        if (draft.neededBy != null) {
          final d = draft.neededBy!;
          final hh = d.hour.toString().padLeft(2, '0');
          final mm = d.minute.toString().padLeft(2, '0');
          return '${d.day}.${d.month} $hh:$mm';
        }
        return context.tr('request_when_other');
    }
  }

  static String _money(num v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i += 1) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

/// Хизмат сўрови формаси.
class ServiceDemandForm extends StatelessWidget {
  const ServiceDemandForm({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  final DemandDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, 'request_describe'),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: draft.description,
          minLines: 2,
          maxLines: 4,
          maxLength: 2000,
          decoration: InputDecoration(
            hintText: context.tr('request_describe'),
            filled: true,
            fillColor: c.surface,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.line),
            ),
          ),
          onChanged: (v) {
            draft.description = v;
            onChanged();
          },
        ),
        const SizedBox(height: 16),

        _label(context, 'request_when'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            _timeChip(context, 'now', 'request_when_now'),
            _timeChip(context, 'today', 'request_when_today'),
            _timeChip(context, 'custom', 'request_when_other'),
          ],
        ),
        const SizedBox(height: 16),

        _label(context, 'request_budget'),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: draft.budgetMax?.toString() ?? '',
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: context.tr('request_budget_hint'),
            suffixText: context.tr('sum'),
            filled: true,
            fillColor: c.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.line),
            ),
          ),
          onChanged: (v) {
            draft.budgetMax = num.tryParse(v.replaceAll(RegExp(r'\s'), ''));
            onChanged();
          },
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('request_budget_hint'),
          style: TextStyle(fontSize: 11, color: c.ink3),
        ),
      ],
    );
  }

  Widget _label(BuildContext context, String key) => Text(
        context.tr(key),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.ava.ink,
        ),
      );

  Widget _timeChip(BuildContext context, String mode, String labelKey) {
    final c = context.ava;
    final selected = draft.timeMode == mode;
    return ChoiceChip(
      label: Text(context.tr(labelKey)),
      selected: selected,
      onSelected: (_) {
        draft.timeMode = mode;
        onChanged();
      },
      selectedColor: c.brandSoft,
      backgroundColor: c.chip,
      labelStyle: TextStyle(
        fontSize: 12,
        color: selected ? c.brand : c.ink,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(color: selected ? c.brand : c.line),
    );
  }
}

/// Таклифчи кўрадиган карточка — ПРОЕКЦИЯДАН.
///
/// Бу карточка `demand_matches.projection`дан чизилади. Аниқ манзил ва
/// телефон бу ерда ЙЎҚ ва бўлиши ҳам мумкин эмас: сервер уларни
/// проекцияга ёзмайди.
class ServiceMatchCard extends StatelessWidget {
  const ServiceMatchCard({super.key, required this.match});

  final DemandMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final p = match.projection;

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
                  decoration: BoxDecoration(
                    color: c.brand,
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Text(
                  p.title.isNotEmpty ? p.title : context.tr('intent_card_service'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (p.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              p.description,
              style: TextStyle(fontSize: 12, color: c.ink2),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (p.districtId != null)
                _chip(context, Icons.place_outlined, p.districtId!),
              if (match.metrics.distanceKm != null)
                _chip(
                  context,
                  Icons.straighten,
                  '${context.tr('match_distance_from_you')} '
                      '${match.metrics.distanceKm!.toStringAsFixed(1)} km',
                ),
              if (match.metrics.detourKm != null)
                _chip(
                  context,
                  Icons.alt_route,
                  '${context.tr('match_on_your_way')} '
                      '+${match.metrics.detourKm!.toStringAsFixed(1)} km',
                ),
              if (p.budget?.max != null)
                _chip(
                  context,
                  Icons.payments_outlined,
                  '${ServiceUiAdapter._money(p.budget!.max!)} ${context.tr('sum')}',
                ),
            ],
          ),
          // Тахминий жой изоҳи — фойдаланувчи «нега аниқ манзил йўқ?»
          // деб ўйламаслиги учун.
          if (p.hasApproxPoint) ...[
            const SizedBox(height: 6),
            Text(
              context.tr('match_approx_location'),
              style: TextStyle(fontSize: 10, color: c.ink3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String text) {
    final c = context.ava;

    // ЧЕГАРА ШАРТ: `Wrap` боласига чексиз кенглик беради, шунинг учун
    // узун матнли чип экрандан чиқиб кетади. Бу тестда топилди
    // («RenderFlex overflowed by 36 pixels»), лекин production'да ҳам
    // бўлади: русча таржима узунроқ ва фойдаланувчи шрифтни 130% гача
    // катталаштириши мумкин.
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

/// Харидор кўрадиган таклиф карточкаси.
class ServiceOfferCard extends StatelessWidget {
  const ServiceOfferCard({
    super.key,
    required this.offer,
    this.onChoose,
  });

  final Offer offer;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  offer.providerName.isNotEmpty
                      ? offer.providerName
                      : context.tr('offer_no_rating'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
              if (offer.providerRating != null) ...[
                Icon(Icons.star_rounded, size: 14, color: c.warn),
                const SizedBox(width: 2),
                Text(
                  offer.providerRating!.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ] else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.brandSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    context.tr('offer_no_rating'),
                    style: TextStyle(fontSize: 10, color: c.brand),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Нарх ва ETA — иккиси ҳам ўзгарувчан узунликда, шунинг учун
          // иккиси ҳам чегараланган. Узун таржима ёки катта шрифтда
          // қатор экрандан чиқиб кетмаслиги керак (тестда топилди).
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  offer.price != null
                      ? '${ServiceUiAdapter._money(offer.price!)} ${context.tr('sum')}'
                      : context.tr('offer_price_negotiable'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: c.brand,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (offer.etaMinutes != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${offer.etaMinutes} ${context.tr('offer_eta_minutes')}',
                    style: TextStyle(fontSize: 11, color: c.ink2),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          if (offer.message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              offer.message,
              style: TextStyle(fontSize: 12, color: c.ink2),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (offer.delivery) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.local_shipping_outlined, size: 12, color: c.ok),
                const SizedBox(width: 4),
                Text(
                  context.tr('offer_with_delivery'),
                  style: TextStyle(fontSize: 11, color: c.ok),
                ),
              ],
            ),
          ],
          if (onChoose != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onChoose,
                style: FilledButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: c.brandInk,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(context.tr('offer_choose')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
