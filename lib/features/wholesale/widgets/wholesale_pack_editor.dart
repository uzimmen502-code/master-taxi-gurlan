import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/price_tier.dart';
import '../models/wholesale_product.dart';
import 'wholesale_field_error.dart';

/// Формадаги битта қадоқнинг таҳрир ҳолати (контроллерлар).
///
/// Нарх (эга, 2026-11-19, B): ЯНГИ/таҳрирланган товарда БИТТА нарх ([price]) + ихтиёрий
/// минимал буюртма ([minQty]); аввалги 3 майдон (1–9 / 10–49 / 50+) олиб ташланди.
/// Орқага мослик: эски товардаги 2–5 поғонанинг биринчиси [price] га тушади (унинг `minQty`
/// си [firstMinQty] да сақланади), қолганлари [extraTiers] да ЎЗГАРИШСИЗ қолади ва сақлашда
/// қайта ёзилади — сотувчи «Олиб ташлаш»ни босмагунча (аввалги форма уларни 3 оралиққа
/// «сиқиб» юборарди — энди йўқотилмайди). Буюртма/квота қоидаси (сервер) ўзгармаган.
class WholesalePackDraft {
  WholesalePackDraft({required this.id, this.existingPhotoUrl = ''});

  /// Мавжуд қадоқдан (таҳрир). [stock] — серверда сақланган қолдиқ.
  factory WholesalePackDraft.fromPack(WholesalePack p, {int? stock}) {
    final d = WholesalePackDraft(
      id: p.id == WholesalePack.defaultId ? 'p1' : p.id,
      existingPhotoUrl: p.photoUrl,
    );
    d.label.text = p.label;
    final tiers = sortPriceTiers(p.priceTiers);
    if (tiers.isNotEmpty) {
      d.price.text = '${tiers.first.price}';
      d.firstMinQty = tiers.first.minQty;
      d.extraTiers = tiers.skip(1).toList();
    }
    d.weight.text = weightKgFieldText(p.unitWeightG ?? 0);
    if (p.unitDims != null) {
      d.dimL.text = '${p.unitDims!.l}';
      d.dimW.text = '${p.unitDims!.w}';
      d.dimH.text = '${p.unitDims!.h}';
    }
    if (stock != null) d.stock.text = '$stock';
    if (p.minOrderQty != null) d.minQty.text = '${p.minOrderQty}';
    return d;
  }

  final String id;
  final label = TextEditingController();
  /// Бир бирлик нархи (бутун сон, валюта — маҳсулотники).
  final price = TextEditingController();

  /// Биринчи поғона бошланиши — янги товарда 1, эски товарда сақланган қиймат.
  int firstMinQty = 1;

  /// Эски товардаги қўшимча поғоналар (2-дан бошлаб) — тегилмайди, фақат олиб ташлаш мумкин.
  List<PriceTier> extraTiers = const [];
  final weight = TextEditingController();
  final dimL = TextEditingController();
  final dimW = TextEditingController();
  final dimH = TextEditingController();
  final stock = TextEditingController();

  /// Минимал буюртма (эга, 2026-11-13): ихтиёрий, бўш — нарх поғонасидан.
  final minQty = TextEditingController();
  String? minQtyErrKey;

  /// Мавжуд расм URL'и; [newPhoto] танланса ёки [removePhoto] — алмашади.
  String existingPhotoUrl;
  XFile? newPhoto;
  bool removePhoto = false;

  /// Хатолар (сақлаш босилгандан кейин кўрсатилади).
  bool labelErr = false;
  bool tiersErr = false;
  String? stockErrKey;

  bool get hasPhoto => newPhoto != null || (existingPhotoUrl.isNotEmpty && !removePhoto);

  void dispose() {
    label.dispose();
    price.dispose();
    weight.dispose();
    dimL.dispose();
    dimW.dispose();
    dimH.dispose();
    stock.dispose();
    minQty.dispose();
  }

  /// Минимал буюртма: бўш — `null` (хато эмас); сон 1..[kWholesaleMaxOrderQty].
  ({int? qty, String? error}) collectMinQty() {
    final raw = minQty.text.trim();
    if (raw.isEmpty) return (qty: null, error: null);
    final n = validMinOrderQty(int.tryParse(raw));
    return n == null ? (qty: null, error: 'wholesale_err_min_qty_invalid') : (qty: n, error: null);
  }

  /// Поғоналар: асосий нарх (бўш/нол/нотўғри — бўш рўйхат = хато) + сақланган қўшимчалар.
  List<PriceTier> collectTiers() {
    final p = int.tryParse(price.text.trim().replaceAll(' ', ''));
    if (p == null || p <= 0) return const [];
    return sortPriceTiers([PriceTier(minQty: firstMinQty, price: p), ...extraTiers]);
  }

  /// Вазн/ўлчам: иккаласи ихтиёрий; ўлчам — учаласи бирга ёки бўш;
  /// ўлчам бор, вазн йўқ — мумкин эмас (ҳажмий вазн ёлғиз маъносиз).
  ({int? weightG, ShippingDims? dims, String? error}) collectShipping() {
    final wRaw = weight.text.trim();
    int? weightG;
    if (wRaw.isNotEmpty) {
      weightG = parseWeightKgToGrams(wRaw);
      if (weightG == null) return (weightG: null, dims: null, error: 'wholesale_err_weight_invalid');
    }
    final raws = [dimL.text.trim(), dimW.text.trim(), dimH.text.trim()];
    final filled = raws.where((s) => s.isNotEmpty).length;
    ShippingDims? dims;
    if (filled == 3) {
      final l = int.tryParse(raws[0]);
      final w = int.tryParse(raws[1]);
      final h = int.tryParse(raws[2]);
      if (l == null || w == null || h == null) {
        return (weightG: null, dims: null, error: 'wholesale_err_dims_invalid');
      }
      dims = ShippingDims(l: l, w: w, h: h);
      if (!dims.isValid) return (weightG: null, dims: null, error: 'wholesale_err_dims_invalid');
    } else if (filled != 0) {
      return (weightG: null, dims: null, error: 'wholesale_err_dims_invalid');
    }
    if (dims != null && weightG == null) {
      return (weightG: null, dims: null, error: 'wholesale_err_weight_invalid');
    }
    return (weightG: weightG, dims: dims, error: null);
  }

  /// Қолдиқ: бўш — киритилмаган (`null`, хато эмас); сон 0..[WholesaleStock.maxQty].
  ({int? qty, String? error}) collectStock() {
    final raw = stock.text.trim();
    if (raw.isEmpty) return (qty: null, error: null);
    final n = int.tryParse(raw);
    if (n == null || n < 0 || n > WholesaleStock.maxQty) {
      return (qty: null, error: 'wholesale_err_stock_invalid');
    }
    return (qty: n, error: null);
  }
}

/// Битта қадоқ карточкаси. [showLabel] — қадоқ биттадан кўп бўлса ёки
/// номи киритилган бўлса (битта номсиз қадоқ = оддий маҳсулот, эски кўриниш).
class WholesalePackCard extends StatelessWidget {
  const WholesalePackCard({
    super.key,
    required this.draft,
    required this.index,
    required this.unitLabel,
    required this.currencyLabel,
    required this.showLabel,
    required this.onChanged,
    required this.onPickPhoto,
    this.onRemove,
  });

  final WholesalePackDraft draft;
  final int index;
  final String unitLabel;
  final String currencyLabel;
  final bool showLabel;
  final VoidCallback onChanged;
  final VoidCallback onPickPhoto;

  /// `null` — ўчириб бўлмайди (ягона қадоқ).
  final VoidCallback? onRemove;

  InputDecoration _deco(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    final s = draft.collectShipping();
    String? preview;
    if (s.error == null && s.weightG != null) {
      final vol = s.dims?.volumetricWeightG() ?? 0;
      preview = context
          .tr('wholesale_chargeable_weight')
          .replaceAll('{weight}', formatWeightG(chargeableWeightG(s.weightG!, s.dims)))
          .replaceAll('{vol}', s.dims == null ? '—' : formatWeightG(vol));
    }
    return Card(
      key: ValueKey('wholesale-pack-${draft.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('wholesale_pack_n').replaceAll('{n}', '${index + 1}'),
                    style: const TextStyle(fontSize: AppText.bodyMedium, fontWeight: FontWeight.w700),
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    key: ValueKey('wholesale-pack-remove-${draft.id}'),
                    tooltip: context.tr('wholesale_pack_remove'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onRemove,
                  ),
              ],
            ),
            if (showLabel) ...[
              const SizedBox(height: 4),
              TextField(
                key: ValueKey('wholesale-pack-label-${draft.id}'),
                controller: draft.label,
                maxLength: WholesalePack.maxLabelLength,
                onChanged: (_) {
                  if (draft.labelErr) draft.labelErr = false;
                  onChanged();
                },
                decoration: _deco(
                  context.tr('wholesale_pack_label'),
                  hint: context.tr('wholesale_pack_label_hint'),
                ),
              ),
              if (draft.labelErr) const WholesaleFieldError(textKey: 'wholesale_err_pack_label'),
            ],
            const SizedBox(height: 8),
            // Нарх + минимал буюртма — бир қаторда (эга, 2026-11-19, B: битта нарх).
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: ValueKey('wholesale-pack-price-${draft.id}'),
                  controller: draft.price,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                  onChanged: (_) {
                    if (draft.tiersErr) draft.tiersErr = false;
                    onChanged();
                  },
                  decoration: _deco(
                    context
                        .tr('wholesale_field_unit_price')
                        .replaceAll('{unit}', draft.firstMinQty > 1 ? '${draft.firstMinQty}+ $unitLabel' : '1 $unitLabel')
                        .replaceAll('{currency}', currencyLabel),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  key: ValueKey('wholesale-pack-minqty-${draft.id}'),
                  controller: draft.minQty,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                  onChanged: (_) {
                    if (draft.minQtyErrKey != null) draft.minQtyErrKey = null;
                    onChanged();
                  },
                  decoration: _deco(
                    context.tr('wholesale_min_qty_field').replaceAll('{unit}', unitLabel),
                    hint: context.tr('wholesale_min_qty_hint'),
                  ),
                ),
              ),
            ]),
            if (draft.tiersErr) const WholesaleFieldError(textKey: 'wholesale_err_tier_required'),
            if (draft.minQtyErrKey != null) WholesaleFieldError(textKey: draft.minQtyErrKey!),
            if (draft.extraTiers.isNotEmpty) _ExtraTiersNote(draft: draft, unitLabel: unitLabel, currencyLabel: currencyLabel, onChanged: onChanged),
            const SizedBox(height: 12),
            Text(
              context.tr('wholesale_shipping_group'),
              style: TextStyle(fontSize: AppText.bodySmall, fontWeight: FontWeight.w600, color: AppColors.sectionMuted),
            ),
            const SizedBox(height: 6),
            TextField(
              key: ValueKey('wholesale-pack-weight-${draft.id}'),
              controller: draft.weight,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              onChanged: (_) => onChanged(),
              decoration: _deco(context.tr('wholesale_field_weight_kg').replaceAll('{unit}', unitLabel)),
            ),
            const SizedBox(height: 8),
            Row(children: [
              for (final (ctrl, key) in [
                (draft.dimL, 'wholesale_field_dim_l'),
                (draft.dimW, 'wholesale_field_dim_w'),
                (draft.dimH, 'wholesale_field_dim_h'),
              ]) ...[
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    onChanged: (_) => onChanged(),
                    decoration: _deco(context.tr(key)),
                  ),
                ),
                if (key != 'wholesale_field_dim_h') const SizedBox(width: 8),
              ],
            ]),
            if (preview != null) ...[
              const SizedBox(height: 4),
              Text(preview, style: TextStyle(fontSize: AppText.bodySmall, color: AppColors.primaryText)),
            ] else if (s.error != null) ...[
              const SizedBox(height: 4),
              WholesaleFieldError(textKey: s.error!),
            ],
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('wholesale-pack-stock-${draft.id}'),
              controller: draft.stock,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
              onChanged: (_) {
                if (draft.stockErrKey != null) draft.stockErrKey = null;
                onChanged();
              },
              decoration: _deco(
                context.tr('wholesale_stock_field').replaceAll('{unit}', unitLabel),
                hint: context.tr('wholesale_stock_hint'),
              ),
            ),
            if (draft.stockErrKey != null) WholesaleFieldError(textKey: draft.stockErrKey!),
            const SizedBox(height: 8),
            _PhotoRow(draft: draft, onPick: onPickPhoto, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Эски товардаги қўшимча поғоналар — фақат кўрсатилади; «Олиб ташлаш» уларни ўчиради
/// (сақлангандан кейин товар битта нархли бўлади).
class _ExtraTiersNote extends StatelessWidget {
  const _ExtraTiersNote({
    required this.draft,
    required this.unitLabel,
    required this.currencyLabel,
    required this.onChanged,
  });

  final WholesalePackDraft draft;
  final String unitLabel;
  final String currencyLabel;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final list = draft.extraTiers.map((t) => t.label(unitLabel, currencyLabel)).join(' · ');
    return Container(
      key: ValueKey('wholesale-pack-extra-tiers-${draft.id}'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Expanded(
          child: Text(
            context.tr('wholesale_extra_tiers').replaceAll('{list}', list),
            style: const TextStyle(fontSize: AppText.bodySmall),
          ),
        ),
        TextButton(
          key: ValueKey('wholesale-pack-extra-tiers-remove-${draft.id}'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () {
            draft.extraTiers = const [];
            onChanged();
          },
          child: Text(context.tr('wholesale_extra_tiers_remove')),
        ),
      ]),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.draft, required this.onPick, required this.onChanged});

  final WholesalePackDraft draft;
  final VoidCallback onPick;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    Widget? thumb;
    if (draft.newPhoto != null) {
      thumb = FutureBuilder(
        future: draft.newPhoto!.readAsBytes(),
        builder: (_, snap) => snap.hasData
            ? Image.memory(snap.data!, fit: BoxFit.cover)
            : const ColoredBox(color: Colors.black12),
      );
    } else if (draft.hasPhoto) {
      thumb = Image.network(draft.existingPhotoUrl, fit: BoxFit.cover);
    }
    return Row(
      children: [
        if (thumb != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 48, height: 48, child: thumb),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: OutlinedButton.icon(
            key: ValueKey('wholesale-pack-photo-${draft.id}'),
            onPressed: onPick,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: Text(
              context.tr(draft.hasPhoto ? 'wholesale_pack_photo_change' : 'wholesale_pack_photo'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (draft.hasPhoto)
          IconButton(
            tooltip: context.tr('wholesale_pack_photo_remove'),
            icon: const Icon(Icons.close),
            onPressed: () {
              draft.newPhoto = null;
              draft.removePhoto = true;
              onChanged();
            },
          ),
      ],
    );
  }
}
