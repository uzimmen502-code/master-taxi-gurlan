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
  };
}

Widget _chip(BuildContext context,
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
  );
}

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
        const SizedBox(height: 8),
        Wrap(
          key: const ValueKey('market_choice'),
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(context,
                key: const ValueKey('market_choice_aralash'),
                label: context.tr('market_aralash'),
                selected: selected.isEmpty,
                onSelected: enabled ? (_) => onChanged('') : null),
            for (final m in markets)
              _chip(context,
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

/// Бўлим чиплари (битта бўлимли бозорда чақирилмайди).
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('market_category'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          key: const ValueKey('market_category'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in market.categories)
              _chip(context,
                  key: ValueKey('market_cat_${c.id}'),
                  label: c.label(lang),
                  selected: selected == c.id,
                  onSelected: enabled ? (_) => onChanged(c.id) : null),
          ],
        ),
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
  });

  final List<MarketField> fields;
  final Map<String, Object?> values;
  final Map<String, MarketFieldError> errors;
  final void Function(String key, Object? value) onChanged;
  final bool enabled;

  /// Тест учун (бўлмаса `showDatePicker`).
  final Future<DateTime?> Function(BuildContext context, DateTime? initial)? pickDate;

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

  @override
  Widget build(BuildContext context) {
    if (widget.fields.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('market_fields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in widget.fields) ...[
          const SizedBox(height: 12),
          _field(context, f),
        ],
      ],
    );
  }
}
