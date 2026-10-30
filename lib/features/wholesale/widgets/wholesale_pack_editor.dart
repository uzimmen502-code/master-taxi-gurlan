import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/price_tier.dart';
import '../models/wholesale_product.dart';
import 'wholesale_field_error.dart';

/// Формадаги битта қадоқнинг таҳрир ҳолати (контроллерлар). Нарх
/// поғоналари — тайёр оралиқлар 1–9 / 10–49 / 50+ ([kStandardTierBrackets]),
/// тўлдириш ихтиёрий, камида биттаси шарт.
class WholesalePackDraft {
  WholesalePackDraft({required this.id, this.existingPhotoUrl = ''});

  /// Мавжуд қадоқдан (таҳрир). [stock] — серверда сақланган қолдиқ.
  factory WholesalePackDraft.fromPack(WholesalePack p, {int? stock}) {
    final d = WholesalePackDraft(
      id: p.id == WholesalePack.defaultId ? 'p1' : p.id,
      existingPhotoUrl: p.photoUrl,
    );
    d.label.text = p.label;
    for (final t in p.priceTiers) {
      final idx = t.minQty >= kPlatformHighMinQty ? 2 : (t.minQty >= kPlatformMidMinQty ? 1 : 0);
      d.prices[idx].text = '${t.price}';
    }
    d.weight.text = weightKgFieldText(p.unitWeightG ?? 0);
    if (p.unitDims != null) {
      d.dimL.text = '${p.unitDims!.l}';
      d.dimW.text = '${p.unitDims!.w}';
      d.dimH.text = '${p.unitDims!.h}';
    }
    if (stock != null) d.stock.text = '$stock';
    return d;
  }

  final String id;
  final label = TextEditingController();
  final prices = List.generate(kStandardTierBrackets.length, (_) => TextEditingController());
  final weight = TextEditingController();
  final dimL = TextEditingController();
  final dimW = TextEditingController();
  final dimH = TextEditingController();
  final stock = TextEditingController();

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
    for (final c in prices) {
      c.dispose();
    }
    weight.dispose();
    dimL.dispose();
    dimW.dispose();
    dimH.dispose();
    stock.dispose();
  }

  /// Тўлдирилган поғоналар (бўш ёки нотўғри майдон ўтказиб юборилади).
  List<PriceTier> collectTiers() =>
      collectStandardTiers([for (final c in prices) c.text]);

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
            for (var i = 0; i < kStandardTierBrackets.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      '${kStandardTierBrackets[i].$2} $unitLabel',
                      style: const TextStyle(fontSize: AppText.bodyMedium, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: ValueKey('wholesale-pack-price-${draft.id}-$i'),
                      controller: draft.prices[i],
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) {
                        if (draft.tiersErr) draft.tiersErr = false;
                        onChanged();
                      },
                      decoration: _deco(
                        context.tr('wholesale_field_tier_price').replaceAll('{currency}', currencyLabel),
                      ),
                    ),
                  ),
                ]),
              ),
            if (draft.tiersErr) const WholesaleFieldError(textKey: 'wholesale_err_tier_required'),
            const SizedBox(height: 4),
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
