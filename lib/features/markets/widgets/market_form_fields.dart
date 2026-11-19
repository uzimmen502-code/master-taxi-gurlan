import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/market_taxonomy.dart';

/// Сотувчи формасидаги «Бозорлар» қисмлари (5-босқич): «Қаерда сотасиз?» чиплари, бўлим чиплари ва
/// таксономиядан қуриладиган динамик майдонлар. Форма ўзи битта ([BusinessProductFormScreen]).

/// «Қаерда сотасиз?» — танлаш мумкин бўлган бозорлар: модули фаол туманда очиладиганлари, `order` бўйича.
/// Аралаш (бозор майдонисиз) — чақирувчи ўзи биринчи қўяди.
List<MarketDef> openableMarkets(MarketTaxonomy taxonomy, bool Function(String moduleId) isOpenable) =>
    [for (final m in taxonomy.ordered) if (isOpenable(m.moduleId)) m];

/// Бозор қисқа номи (чип): `market_short_<id>` калити; калит йўқ бўлса — таксономиядаги ном.
String marketShortLabel(BuildContext context, MarketDef m) {
  final key = 'market_short_${m.id}';
  final s = context.tr(key);
  return s == key ? m.label(context.contentLang) : s;
}

/// Аралаш бозор карточкасидаги бозор белгиси (8-босқич): `market_short_<id>`; бозорсиз ёки калит йўқ — бўш.
String marketShortBadge(String Function(String key) tr, String marketId) {
  final id = marketId.trim();
  if (id.isEmpty) return '';
  final key = 'market_short_$id';
  final s = tr(key);
  return s == key ? '' : s;
}

/// Хато коди → матн.
String marketFieldErrorText(BuildContext context, MarketField f, MarketFieldError e) {
  String fill(String key, Object? v) => context.tr(key).replaceAll('{value}', '${v ?? ''}');
  return switch (e) {
    MarketFieldError.required => context.tr('market_err_required'),
    MarketFieldError.number => context.tr('market_err_number'),
    MarketFieldError.min => fill('market_err_min', f.min),
    MarketFieldError.max => fill('market_err_max', f.max),
    MarketFieldError.maxLen => fill('market_err_max_len', f.maxLen),
    MarketFieldError.option => context.tr('market_err_required'),
    MarketFieldError.incomplete => context.tr('market_err_box_all'),
  };
}

/// Ихчам танлов чипи (бозор/бўлим/бирлик/автомобиль; ягона кўриниш).
Widget marketChip(BuildContext context,
    {required Key key, required String label, required bool selected, required ValueChanged<bool>? onSelected}) {
  final c = context.ava;
  return ChoiceChip(
    key: key,
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    onSelected: onSelected,
    selectedColor: c.brandSoft,
    backgroundColor: c.chip,
    side: BorderSide(color: selected ? c.brand : c.line, width: selected ? 1.5 : 1),
    labelStyle: TextStyle(fontSize: 13, color: c.ink, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
    // Ихчам (эга 2026-11-19): форма қисқароқ бўлсин.
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    labelPadding: kMarketChipLabelPadding,
  );
}

/// Ихчам чип ички чеккаси ва Wrap оралиқлари (бозор/бўлим/бирлик чиплари учун ягона қиймат, эга 2026-11-19).
const EdgeInsets kMarketChipLabelPadding = EdgeInsets.symmetric(horizontal: 6);
const double kMarketChipSpacing = 6;
const double kMarketChipRunSpacing = 4;

/// «Қаерда сотасиз?»: Аралаш · [markets]. [selected] бўш — Аралаш.
class MarketChoiceChips extends StatelessWidget {
  const MarketChoiceChips({
    super.key,
    required this.markets,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final List<MarketDef> markets;
  final String selected;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('market_where_sell'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Wrap(
          key: const ValueKey('market_choice'),
          spacing: kMarketChipSpacing,
          runSpacing: kMarketChipRunSpacing,
          children: [
            marketChip(context,
                key: const ValueKey('market_choice_aralash'),
                label: context.tr('market_aralash'),
                selected: selected.isEmpty,
                onSelected: enabled ? (_) => onChanged('') : null),
            for (final m in markets)
              marketChip(context,
                  key: ValueKey('market_choice_${m.id}'),
                  label: marketShortLabel(context, m),
                  selected: selected == m.id,
                  onSelected: enabled ? (_) => onChanged(m.id) : null),
          ],
        ),
      ],
    );
  }
}

/// Бўлим чиплари (битта бўлимли бозорда чақирилмайди). «Бўлим» сарлавҳаси йўқ (эга 2026-11-19) — чиплар ўзи.
class MarketCategoryChips extends StatelessWidget {
  const MarketCategoryChips({
    super.key,
    required this.market,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final MarketDef market;
  final String selected;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final lang = context.contentLang;
    return Wrap(
      key: const ValueKey('market_category'),
      spacing: kMarketChipSpacing,
      runSpacing: kMarketChipRunSpacing,
      children: [
        for (final c in market.categories)
          marketChip(context,
              key: ValueKey('market_cat_${c.id}'),
              label: c.label(lang),
              selected: selected == c.id,
              onSelected: enabled ? (_) => onChanged(c.id) : null),
      ],
    );
  }
}

/// Динамик майдонлар (таксономия тартибида; бўлимга тегишлилари). Қийматлар [values]да (int/text/date — матн,
/// select — option id, bool — `bool`); ўзгариш [onChanged] орқали. Матн контроллерлари калит бўйича сақланади.
class MarketFieldsEditor extends StatefulWidget {
  const MarketFieldsEditor({
    super.key,
    required this.fields,
    required this.values,
    required this.errors,
    required this.onChanged,
    this.enabled = true,
    this.pickDate,
    this.topGap = 12,
  });

  final List<MarketField> fields;
  final Map<String, Object?> values;
  final Map<String, MarketFieldError> errors;
  final void Function(String key, Object? value) onChanged;
  final bool enabled;

  /// Тест учун (бўлмаса `showDatePicker`).
  final Future<DateTime?> Function(BuildContext context, DateTime? initial)? pickDate;

  /// Биринчи майдон устидаги оралиқ (форма тепасидаги марка/модель блокида 0).
  final double topGap;

  @override
  State<MarketFieldsEditor> createState() => _MarketFieldsEditorState();
}

class _MarketFieldsEditorState extends State<MarketFieldsEditor> {
  final Map<String, TextEditingController> _ctrl = {};

  TextEditingController _controller(String key) =>
      _ctrl[key] ??= TextEditingController(text: '${widget.values[key] ?? ''}');

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<DateTime?> _defaultPick(BuildContext context, DateTime? initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
    );
  }

  Widget _field(BuildContext context, MarketField f) {
    final lang = context.contentLang;
    final err = widget.errors[f.key];
    final errText = err == null ? null : marketFieldErrorText(context, f, err);
    final label = f.required ? '${f.label(lang)} *' : f.label(lang);
    final key = ValueKey('market_field_${f.key}');
    switch (f.type) {
      case MarketFieldType.int:
      case MarketFieldType.text:
        final isInt = f.type == MarketFieldType.int;
        return TextField(
          key: key,
          controller: _controller(f.key),
          enabled: widget.enabled,
          keyboardType: isInt ? TextInputType.number : TextInputType.text,
          inputFormatters: isInt ? [FilteringTextInputFormatter.digitsOnly] : null,
          maxLength: isInt ? null : f.maxLen,
          onChanged: (v) => widget.onChanged(f.key, v),
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), errorText: errText),
        );
      case MarketFieldType.select:
        final current = widget.values[f.key];
        return DropdownButtonFormField<String>(
          key: key,
          initialValue: current is String && f.option(current) != null ? current : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), errorText: errText),
          items: [
            if (!f.required) DropdownMenuItem<String>(value: null, child: Text(context.tr('market_not_set'))),
            for (final o in f.options) DropdownMenuItem<String>(value: o.id, child: Text(o.label(lang))),
          ],
          onChanged: widget.enabled ? (v) => widget.onChanged(f.key, v) : null,
        );
      case MarketFieldType.bool:
        return CheckboxListTile(
          key: key,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: widget.values[f.key] == true,
          title: Text(label),
          subtitle: errText == null ? null : Text(errText, style: TextStyle(color: Colors.red.shade700)),
          onChanged: widget.enabled ? (v) => widget.onChanged(f.key, v == true) : null,
        );
      case MarketFieldType.date:
        final raw = '${widget.values[f.key] ?? ''}';
        final d = parseIsoDate(raw);
        return InkWell(
          key: key,
          onTap: !widget.enabled
              ? null
              : () async {
                  final picked = await (widget.pickDate ?? _defaultPick)(context, d);
                  if (picked != null) widget.onChanged(f.key, isoDate(picked));
                },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              errorText: errText,
              suffixIcon: d == null
                  ? const Icon(Icons.event_outlined)
                  : IconButton(
                      key: ValueKey('market_field_${f.key}_clear'),
                      icon: const Icon(Icons.close),
                      onPressed: widget.enabled ? () => widget.onChanged(f.key, '') : null,
                    ),
            ),
            child: Text(d == null ? context.tr('market_date_pick') : displayDate(d)),
          ),
        );
    }
  }

  /// Ёш (эга 2026-11-19): «йил» + «ой (0–11)» бир қаторда; қиймат — бутун ой матни ([kAgeMonthsKey]).
  Widget _ageRow(BuildContext context, MarketField f) {
    final err = widget.errors[f.key];
    final errText = err == null ? null : marketFieldErrorText(context, f, err);
    final yCtrl = _ctrl['${f.key}__y'] ??= TextEditingController(text: _agePart(widget.values[f.key], years: true));
    final mCtrl = _ctrl['${f.key}__m'] ??= TextEditingController(text: _agePart(widget.values[f.key], years: false));
    void emit() {
      final y = yCtrl.text.trim(), m = mCtrl.text.trim();
      if (y.isEmpty && m.isEmpty) return widget.onChanged(f.key, '');
      widget.onChanged(f.key, '${(int.tryParse(y) ?? 0) * 12 + (int.tryParse(m) ?? 0)}');
    }

    InputDecoration deco(String labelKey) => InputDecoration(
          labelText: context.tr(labelKey),
          border: const OutlineInputBorder(),
          isDense: true,
        );
    return Column(
      key: ValueKey('market_field_${f.key}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(f.required ? '${context.tr('market_age_label')} *' : context.tr('market_age_label'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextField(
              key: ValueKey('market_field_${f.key}_y'),
              controller: yCtrl,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
              onChanged: (_) => emit(),
              decoration: deco('market_age_years'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: ValueKey('market_field_${f.key}_m'),
              controller: mCtrl,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, const MaxIntInputFormatter(11)],
              onChanged: (_) => emit(),
              decoration: deco('market_age_months'),
            ),
          ),
        ]),
        if (errText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(errText, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
          ),
      ],
    );
  }

  static String _agePart(Object? v, {required bool years}) {
    final n = int.tryParse('${v ?? ''}'.trim());
    if (n == null || n < 0) return '';
    final part = years ? n ~/ 12 : n % 12;
    // 0 йил — бўш; 0 ой — фақат умумий қиймат 0 бўлса кўрсатилади.
    if (part == 0 && (years || n != 0)) return '';
    return '$part';
  }

  /// Каробка ўлчамлари (эга 2026-11-19): эни × узунлиги × баландлиги — бир қаторда учта кичик майдон.
  Widget _boxRow(BuildContext context, List<MarketField> boxFields) {
    const labels = {'box_w_cm': 'market_box_w', 'box_l_cm': 'market_box_l', 'box_h_cm': 'market_box_h'};
    String? errText;
    for (final f in boxFields) {
      final e = widget.errors[f.key];
      if (e != null) {
        errText = marketFieldErrorText(context, f, e);
        break;
      }
    }
    return Column(
      key: const ValueKey('market_box_dims'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('market_box_dims_label'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Row(children: [
          for (var i = 0; i < boxFields.length; i++) ...[
            if (i > 0)
              const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('×')),
            Expanded(
              child: TextField(
                key: ValueKey('market_field_${boxFields[i].key}'),
                controller: _controller(boxFields[i].key),
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                onChanged: (v) => widget.onChanged(boxFields[i].key, v),
                decoration: InputDecoration(
                  labelText: context.tr(labels[boxFields[i].key] ?? boxFields[i].key),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: widget.errors[boxFields[i].key] == null ? null : '',
                  errorStyle: const TextStyle(height: 0, fontSize: 0),
                ),
              ),
            ),
          ],
        ]),
        if (errText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(errText, style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fields.isEmpty) return const SizedBox.shrink();
    final box = hasBoxDims(widget.fields)
        ? [for (final k in kBoxDimKeys) widget.fields.firstWhere((f) => f.key == k)]
        : const <MarketField>[];
    return Column(
      key: const ValueKey('market_fields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.fields.length; i++)
          if (box.isNotEmpty && kBoxDimKeys.contains(widget.fields[i].key)) ...[
            // Учала майдон биринчисининг ўрнида битта қатор бўлиб чиқади.
            if (widget.fields[i].key == kBoxDimKeys.first) ...[
              SizedBox(height: i == 0 ? widget.topGap : 12),
              _boxRow(context, box),
            ],
          ] else ...[
            SizedBox(height: i == 0 ? widget.topGap : 12),
            widget.fields[i].key == kAgeMonthsKey && widget.fields[i].type == MarketFieldType.int
                ? _ageRow(context, widget.fields[i])
                : _field(context, widget.fields[i]),
          ],
      ],
    );
  }
}

/// Рақамни [max] дан оширмайди (ортиқ бўлса — аввалги қиймат қолади). Масалан ой: 0–11.
class MaxIntInputFormatter extends TextInputFormatter {
  const MaxIntInputFormatter(this.max);
  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final n = int.tryParse(newValue.text);
    return n == null || n > max ? oldValue : newValue;
  }
}
