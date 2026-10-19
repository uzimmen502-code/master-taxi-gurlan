// Таом формаси — «Мижоз учун қўшимча маълумот» блоки (D-REST-16/17/24).
//
// Тўртта йиғиладиган карточка: Порция · Таркиби (КБЖУ) · Кухна · Белгилар.
// ҲАММАСИ ИХТИЁРИЙ (прогрессив очиш: форма узун кўринмайди, сотувчи
// мажбурланмайди); тўлдирилгани карточкада белги билан кўринади ва тепада
// «n / 4» ҳисоби бор. Мантиқ ([DishFacts]) соф ва тестланган; бу ерда фақат
// кўрсатиш ва киритиш. Қиймат ўзгарса — [onChanged] янги [DishFacts] билан.
//
// Дизайн (ega рухсати 2026-10-19: янги ранг/услуб — токен орқали): КБЖУ
// диаграммаси `AvaMacroColors`; барча бошқа ранг/радиус/оралиқ мавжуд
// `ava_tokens.dart`дан. Шрифт ўзгартирилмайди — Inter ўзбек Қ/Ғ/Ҳ/Ў ҳарфларини
// қоплайди (қаранг: `AvaFont`). Рангдан ташқари белги ҳам бор (иконка + матн).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../domain/cuisine.dart';
import '../domain/dish_facts.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;
import 'form_chip_style.dart';

typedef CuisineLoader = Future<List<Cuisine>> Function();
typedef CuisineAdder = Future<Cuisine> Function(String name, String group);

enum _Card { portion, nutrition, cuisine, tags }

class DishFactsEditor extends StatefulWidget {
  const DishFactsEditor({
    super.key,
    required this.initial,
    required this.priceController,
    required this.onChanged,
    required this.loadCuisines,
    required this.addCuisine,
    this.showErrors = false,
  });

  final DishFacts initial;

  /// Таом нархи майдони — «бир кишилик нарх» шундан ҳисобланади.
  final TextEditingController priceController;
  final ValueChanged<DishFacts> onChanged;
  final CuisineLoader loadCuisines;
  final CuisineAdder addCuisine;

  /// Сақлаш уриниб кўрилгандан кейин `true`: тўлиқ бўлмаган КБЖУ ҳам хато
  /// сифатида кўрсатилади ва хатоли карточкалар очилади.
  final bool showErrors;

  @override
  State<DishFactsEditor> createState() => _DishFactsEditorState();
}

class _DishFactsEditorState extends State<DishFactsEditor> {
  static String _s(int? v) => v == null ? '' : '$v';

  late final _servings = TextEditingController(text: _s(widget.initial.servings));
  late final _weight = TextEditingController(text: _s(widget.initial.weightG));
  late final _kcal = TextEditingController(text: _s(widget.initial.kcal));
  late final _protein = TextEditingController(text: _s(widget.initial.protein));
  late final _fat = TextEditingController(text: _s(widget.initial.fat));
  late final _carbs = TextEditingController(text: _s(widget.initial.carbs));
  late String? _group = widget.initial.cuisineGroup;
  late String? _cuisineId = widget.initial.cuisineId;
  late final Set<String> _tags = {...widget.initial.tags};

  final Set<_Card> _open = {};
  List<Cuisine>? _cuisines;
  bool _cuisinesLoading = false;
  Object? _cuisinesError;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    if (i.servings != null || i.weightG != null) _open.add(_Card.portion);
    if (i.kcal != null) _open.add(_Card.nutrition);
    if (i.hasCuisine) _open.add(_Card.cuisine);
    if (i.tags.isNotEmpty) _open.add(_Card.tags);
    if (_open.contains(_Card.cuisine)) _ensureCuisines();
  }

  @override
  void didUpdateWidget(DishFactsEditor old) {
    super.didUpdateWidget(old);
    if (widget.showErrors && !old.showErrors) {
      // Хатоли карточкаларни очамиз — сотувчи нима тузатишни кўрсин.
      final errs = _facts.validate();
      setState(() {
        if (errs.contains(DishFactsError.servings) || errs.contains(DishFactsError.weight)) _open.add(_Card.portion);
        if (errs.any((e) => e.startsWith('nutrition'))) _open.add(_Card.nutrition);
        if (errs.contains(DishFactsError.cuisine)) _open.add(_Card.cuisine);
        if (errs.contains(DishFactsError.tags)) _open.add(_Card.tags);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_servings, _weight, _kcal, _protein, _fat, _carbs]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Ҳолат ───────────────────────────────────────────────────────────

  static int? _n(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  DishFacts get _facts => DishFacts(
        servings: _n(_servings),
        weightG: _n(_weight),
        kcal: _n(_kcal),
        protein: _n(_protein),
        fat: _n(_fat),
        carbs: _n(_carbs),
        cuisineGroup: _group,
        cuisineId: _cuisineId,
        tags: DishTag.all.where(_tags.contains).toList(),
      );

  void _changed() {
    setState(() {});
    widget.onChanged(_facts);
  }

  void _toggle(_Card card) {
    final opening = !_open.contains(card);
    setState(() => opening ? _open.add(card) : _open.remove(card));
    if (opening && card == _Card.cuisine) _ensureCuisines();
  }

  Future<void> _ensureCuisines({bool force = false}) async {
    if (_cuisinesLoading || (!force && _cuisines != null)) return;
    setState(() {
      _cuisinesLoading = true;
      _cuisinesError = null;
    });
    try {
      final list = await widget.loadCuisines();
      if (!mounted) return;
      setState(() => _cuisines = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cuisinesError = e);
    } finally {
      if (mounted) setState(() => _cuisinesLoading = false);
    }
  }

  void _pickGroup(String? group) {
    setState(() {
      _group = group;
      final selected = _cuisineId;
      if (selected != null && group != null) {
        final c = _cuisines?.where((x) => x.id == selected);
        // Танланган кухна бошқа гуруҳники бўлса — тозаланади (ID гуруҳни ўз ичига олади).
        if (c != null && c.isNotEmpty && c.first.group != group) _cuisineId = null;
      }
      if (group == null) _cuisineId = null;
    });
    if (group != null) _ensureCuisines();
    widget.onChanged(_facts);
  }

  Future<void> _addOwnCuisine() async {
    final group = _group;
    if (group == null || _adding) return;
    final name = await showDialog<String>(context: context, builder: (_) => const _CuisineNameDialog());
    if (name == null || !mounted) return;
    setState(() => _adding = true);
    try {
      final c = await widget.addCuisine(name, group);
      if (!mounted) return;
      setState(() {
        _cuisines = [...?_cuisines?.where((x) => x.id != c.id), c];
        _cuisineId = c.id;
      });
      widget.onChanged(_facts);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(restaurantsErrorText(context, e)), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  // ── Хатолар ─────────────────────────────────────────────────────────

  /// Кўрсатиладиган хатолар: ёзиш пайтида ТЎҒРИДАН-ТЎҒРИ кўринадиганлар ва (сақлаш
  /// уриниб кўрилгач) ҳаммаси. Тугалланмаган КБЖУ ёзиш жараёнида хато эмас.
  List<String> get _visibleErrors {
    final errs = _facts.validate();
    if (widget.showErrors) return errs;
    return errs.where((e) => e != DishFactsError.nutritionIncomplete).toList();
  }

  String? _errorText(BuildContext context, Iterable<String> keys, {int? calc}) {
    final shown = _visibleErrors.where(keys.contains);
    if (shown.isEmpty) return null;
    final key = shown.first;
    return context.tr('restaurants_m_dish_err_$key').replaceAll('{n}', calc == null ? '' : '$calc');
  }

  // ── Қурилиш ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final f = _facts;
    // «Тўлдирилган» — киритилган ВА хатосиз (хатоли карточка яшил белги олмайди, ҳисобга кирмайди).
    final errs = f.validate();
    bool clean(Iterable<String> keys) => !errs.any(keys.contains);
    final portionOk = (f.servings != null || f.weightG != null) && clean(const [DishFactsError.servings, DishFactsError.weight]);
    final nutritionOk = f.hasNutrition &&
        clean(const [DishFactsError.nutritionIncomplete, DishFactsError.nutritionRange, DishFactsError.nutritionMismatch]);
    final cuisineOk = f.hasCuisine && clean(const [DishFactsError.cuisine]);
    final tagsOk = f.tags.isNotEmpty && clean(const [DishFactsError.tags]);
    final filled = [portionOk, nutritionOk, cuisineOk, tagsOk].where((x) => x).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('restaurants_m_dish_title'),
                style: AvaText.sectionTitle.copyWith(color: c.ink),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              label: context.tr('restaurants_m_dish_progress').replaceAll('{n}', '$filled').replaceAll('{total}', '4'),
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: filled == 0 ? c.chip : c.okSoft,
                    borderRadius: BorderRadius.circular(AvaRadius.chip),
                    border: Border.all(color: filled == 0 ? c.line : c.ok.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '$filled / 4',
                    style: AvaText.caption.copyWith(
                      color: filled == 0 ? c.ink2 : c.ok,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(context.tr('restaurants_m_dish_intro'), style: AvaText.caption.copyWith(color: c.ink2)),
        const SizedBox(height: 12),
        _FactCard(
          icon: Icons.restaurant_menu_rounded,
          title: context.tr('restaurants_m_dish_portion'),
          summary: _portionSummary(context, f),
          filled: portionOk,
          hasError: _errorText(context, const [DishFactsError.servings, DishFactsError.weight]) != null,
          open: _open.contains(_Card.portion),
          onToggle: () => _toggle(_Card.portion),
          child: _portionBody(context, f),
        ),
        _FactCard(
          icon: Icons.local_fire_department_rounded,
          title: context.tr('restaurants_m_dish_nutrition'),
          summary: f.hasNutrition ? context.tr('restaurants_m_dish_kcal_short').replaceAll('{n}', '${f.kcal}') : context.tr('restaurants_m_dish_empty'),
          filled: nutritionOk,
          hasError: _errorText(context, const [
                DishFactsError.nutritionIncomplete,
                DishFactsError.nutritionRange,
                DishFactsError.nutritionMismatch,
              ]) !=
              null,
          open: _open.contains(_Card.nutrition),
          onToggle: () => _toggle(_Card.nutrition),
          child: _nutritionBody(context, f),
        ),
        _FactCard(
          icon: Icons.public_rounded,
          title: context.tr('restaurants_m_dish_cuisine'),
          summary: _cuisineSummary(context, f),
          filled: cuisineOk,
          hasError: _errorText(context, const [DishFactsError.cuisine]) != null,
          open: _open.contains(_Card.cuisine),
          onToggle: () => _toggle(_Card.cuisine),
          child: _cuisineBody(context),
        ),
        _FactCard(
          icon: Icons.sell_outlined,
          title: context.tr('restaurants_m_dish_tags'),
          summary: f.tags.isEmpty
              ? context.tr('restaurants_m_dish_empty')
              : f.tags.map((t) => context.tr('restaurants_m_dish_tag_$t')).join(' · '),
          filled: tagsOk,
          hasError: _errorText(context, const [DishFactsError.tags]) != null,
          open: _open.contains(_Card.tags),
          onToggle: () => _toggle(_Card.tags),
          child: _tagsBody(context),
        ),
      ],
    );
  }

  String _portionSummary(BuildContext context, DishFacts f) {
    final parts = <String>[
      if (f.servings != null) context.tr('restaurants_m_dish_servings_short').replaceAll('{n}', '${f.servings}'),
      if (f.weightG != null) context.tr('restaurants_m_dish_grams').replaceAll('{n}', '${f.weightG}'),
    ];
    return parts.isEmpty ? context.tr('restaurants_m_dish_empty') : parts.join(' · ');
  }

  String _cuisineSummary(BuildContext context, DishFacts f) {
    final id = f.cuisineId;
    if (id == null) return context.tr('restaurants_m_dish_empty');
    final match = _cuisines?.where((x) => x.id == id);
    if (match != null && match.isNotEmpty) return match.first.displayName(context.contentLang);
    return context.tr('restaurants_m_dish_cuisine_selected');
  }


  InputDecoration _dec(BuildContext context, String label, {String? helper, String? error, String? suffix}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        errorText: error,
        errorMaxLines: 3,
        suffixText: suffix,
        border: const OutlineInputBorder(),
        isDense: true,
      );

  Widget _numberField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required int maxLength,
    String? helper,
    String? error,
  }) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(maxLength)],
        decoration: _dec(context, label, helper: helper, error: error),
        onChanged: (_) => _changed(),
      );

  Widget _portionBody(BuildContext context, DishFacts f) {
    final c = context.ava;
    final servingsErr = _errorText(context, const [DishFactsError.servings]);
    final weightErr = _errorText(context, const [DishFactsError.weight]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final n in const [1, 2, 3, 4, 5, 6])
              ChoiceChip(
                label: Text('$n', style: FormChipStyle.label(c, f.servings == n)),
                selected: f.servings == n,
                showCheckmark: false,
                side: FormChipStyle.side(c, f.servings == n),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                selectedColor: c.brandSoft,
                onSelected: (_) {
                  _servings.text = '$n';
                  _changed();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        _numberField(
          context,
          controller: _servings,
          label: context.tr('restaurants_m_dish_servings'),
          helper: context.tr('restaurants_m_dish_servings_help'),
          maxLength: 2,
          error: servingsErr,
        ),
        ListenableBuilder(
          listenable: widget.priceController,
          builder: (context, _) {
            final price = int.tryParse(widget.priceController.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
            final per = f.pricePerPerson(price);
            if (per == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.person_outline_rounded, size: 18, color: c.brandText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.tr('restaurants_m_dish_per_person').replaceAll('{price}', formatPrice(per)),
                      style: AvaText.body.copyWith(color: c.brandText, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        _numberField(
          context,
          controller: _weight,
          label: context.tr('restaurants_m_dish_weight'),
          maxLength: 4,
          error: weightErr,
        ),
      ],
    );
  }

  Widget _nutritionBody(BuildContext context, DishFacts f) {
    final c = context.ava;
    final err = _errorText(
      context,
      const [DishFactsError.nutritionIncomplete, DishFactsError.nutritionRange, DishFactsError.nutritionMismatch],
      calc: f.hasNutrition ? DishFacts.calcKcal(protein: f.protein!, fat: f.fat!, carbs: f.carbs!) : null,
    );
    final complete = f.hasNutrition && f.validate().where((e) => e.startsWith('nutrition')).isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('restaurants_m_dish_nutrition_help'), style: AvaText.caption.copyWith(color: c.ink2)),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _numberField(context, controller: _kcal, label: context.tr('restaurants_m_dish_kcal'), maxLength: 4)),
            const SizedBox(width: 8),
            Expanded(child: _numberField(context, controller: _protein, label: context.tr('restaurants_m_dish_protein'), maxLength: 3)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _numberField(context, controller: _fat, label: context.tr('restaurants_m_dish_fat'), maxLength: 3)),
            const SizedBox(width: 8),
            Expanded(child: _numberField(context, controller: _carbs, label: context.tr('restaurants_m_dish_carbs'), maxLength: 3)),
          ],
        ),
        if (f.protein != null || f.fat != null || f.carbs != null) ...[
          const SizedBox(height: 12),
          _MacroBar(protein: f.protein ?? 0, fat: f.fat ?? 0, carbs: f.carbs ?? 0),
        ],
        if (err != null)
          _Note(icon: Icons.error_outline_rounded, color: c.danger, text: err)
        else if (complete)
          _Note(
            icon: Icons.check_circle_outline_rounded,
            color: c.ok,
            text: context
                .tr('restaurants_m_dish_kcal_calc')
                .replaceAll('{n}', '${DishFacts.calcKcal(protein: f.protein!, fat: f.fat!, carbs: f.carbs!)}'),
          ),
      ],
    );
  }

  Widget _cuisineBody(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    final group = _group;
    final all = _cuisines;
    final inGroup = group == null || all == null
        ? const <Cuisine>[]
        : Cuisine.selectable(all.where((x) => x.group == group), lang);
    final selectedKnown = _cuisineId != null && (all?.any((x) => x.id == _cuisineId) ?? false);
    final err = _errorText(context, const [DishFactsError.cuisine]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<String>(
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: c.brandSoft,
            selectedForegroundColor: c.brandText,
            minimumSize: const Size(0, AvaTap.minSize),
          ),
          segments: [
            ButtonSegment(value: CuisineGroup.national, label: Text(context.tr('restaurants_m_dish_group_national'))),
            ButtonSegment(value: CuisineGroup.world, label: Text(context.tr('restaurants_m_dish_group_world'))),
          ],
          selected: group == null ? <String>{} : {group},
          onSelectionChanged: (s) => _pickGroup(s.isEmpty ? null : s.first),
        ),
        const SizedBox(height: 12),
        if (group == null)
          Text(context.tr('restaurants_m_dish_cuisine_pick_group'), style: AvaText.caption.copyWith(color: c.ink2))
        else if (_cuisinesLoading && all == null)
          Row(
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(context.tr('restaurants_m_dish_cuisine_loading'), style: AvaText.caption.copyWith(color: c.ink2)),
              ),
            ],
          )
        else if (_cuisinesError != null && all == null)
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 18, color: c.danger),
              const SizedBox(width: 6),
              Expanded(child: Text(context.tr('restaurants_m_dish_cuisine_error'), style: AvaText.caption.copyWith(color: c.danger))),
              TextButton(onPressed: () => _ensureCuisines(force: true), child: Text(context.tr('restaurants_m_dish_retry'))),
            ],
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              // Танланган кухна рўйхатда йўқ (яширилган/юкланмаган) — тозалаш имкони билан.
              if (_cuisineId != null && !selectedKnown)
                InputChip(
                  label: Text(context.tr('restaurants_m_dish_cuisine_selected')),
                  selected: true,
                  selectedColor: c.brandSoft,
                  onDeleted: () {
                    setState(() => _cuisineId = null);
                    widget.onChanged(_facts);
                  },
                ),
              for (final cu in inGroup)
                ChoiceChip(
                  label: Text(cu.displayName(lang), style: FormChipStyle.label(c, _cuisineId == cu.id)),
                  selected: _cuisineId == cu.id,
                  showCheckmark: false,
                  side: FormChipStyle.side(c, _cuisineId == cu.id),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  selectedColor: c.brandSoft,
                  onSelected: (on) {
                    setState(() => _cuisineId = on ? cu.id : null);
                    widget.onChanged(_facts);
                  },
                ),
              ActionChip(
                avatar: _adding
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.add_rounded, size: 18, color: c.brandText),
                label: Text(context.tr('restaurants_m_dish_cuisine_add')),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onPressed: _adding ? null : _addOwnCuisine,
              ),
            ],
          ),
        if (err != null) _Note(icon: Icons.error_outline_rounded, color: c.danger, text: err),
      ],
    );
  }

  Widget _tagsBody(BuildContext context) {
    final c = context.ava;
    final err = _errorText(context, const [DishFactsError.tags]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('restaurants_m_dish_tags_help'), style: AvaText.caption.copyWith(color: c.ink2)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final t in DishTag.all)
              FilterChip(
                label: Text(context.tr('restaurants_m_dish_tag_$t'), style: FormChipStyle.label(c, _tags.contains(t))),
                selected: _tags.contains(t),
                side: FormChipStyle.side(c, _tags.contains(t)),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                selectedColor: c.brandSoft,
                showCheckmark: true,
                onSelected: (on) {
                  setState(() => on ? _tags.add(t) : _tags.remove(t));
                  widget.onChanged(_facts);
                },
              ),
          ],
        ),
        if (err != null) _Note(icon: Icons.error_outline_rounded, color: c.danger, text: err),
      ],
    );
  }
}

// ── Йиғиладиган карточка ──────────────────────────────────────────────

class _FactCard extends StatelessWidget {
  const _FactCard({
    required this.icon,
    required this.title,
    required this.summary,
    required this.filled,
    required this.hasError,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String summary;
  final bool filled;
  final bool hasError;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final border = hasError ? c.danger : c.line;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AvaRadius.card),
        border: Border.all(color: border, width: hasError ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            onTap: onToggle,
            label: '$title. $summary',
            child: ExcludeSemantics(
              child: InkWell(
                onTap: onToggle,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: hasError ? c.dangerSoft : (filled ? c.okSoft : c.chip),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            filled && !hasError ? Icons.check_rounded : icon,
                            size: 20,
                            color: hasError ? c.danger : (filled ? c.ok : c.brandText),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: AvaText.body.copyWith(color: c.ink, fontWeight: FontWeight.w600)),
                              Text(
                                summary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AvaText.caption.copyWith(color: hasError ? c.danger : c.ink2),
                              ),
                            ],
                          ),
                        ),
                        if (hasError) ...[
                          Icon(Icons.error_outline_rounded, size: 20, color: c.danger),
                          const SizedBox(width: 4),
                        ],
                        AnimatedRotation(
                          turns: open ? 0.5 : 0,
                          duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
                          child: Icon(Icons.expand_more_rounded, color: c.ink2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: AvaText.caption.copyWith(color: color, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

/// КБЖУ диаграммаси: сегментлар калорияга ҳисса бўйича (4·О, 9·Ё, 4·У); ҳар қиймат
/// рақам билан ёзилган (ранг ягона белги эмас), қўшни сегментлар орасида бўшлиқ.
class _MacroBar extends StatelessWidget {
  const _MacroBar({required this.protein, required this.fat, required this.carbs});

  final int protein;
  final int fat;
  final int carbs;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final m = context.avaMacro;
    final kp = 4 * protein;
    final kf = 9 * fat;
    final kc = 4 * carbs;
    final total = kp + kf + kc;

    String grams(int v) => context.tr('restaurants_m_dish_grams').replaceAll('{n}', '$v');
    final legend = [
      (m.protein, '${context.tr('restaurants_m_dish_protein_short')} ${grams(protein)}'),
      (m.fat, '${context.tr('restaurants_m_dish_fat_short')} ${grams(fat)}'),
      (m.carbs, '${context.tr('restaurants_m_dish_carbs_short')} ${grams(carbs)}'),
    ];

    final segments = <(Color, int)>[
      if (kp > 0) (m.protein, kp),
      if (kf > 0) (m.fat, kf),
      if (kc > 0) (m.carbs, kc),
    ];

    return Semantics(
      container: true,
      label: legend.map((e) => e.$2).join(', '),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (total > 0)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    // stretch: `ColoredBox` боласиз ҳолда енг кичик (0) ўлчамга тушади — тик ўлчамни
                    // қаттиқ бериш шарт (қурилмада кўринмай қолган эди, тест ҳам ўлчайди).
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < segments.length; i++) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          flex: math.max(1, (segments[i].$2 * 1000 / total).round()),
                          child: ColoredBox(color: segments[i].$1),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else
              Container(height: 10, decoration: BoxDecoration(color: c.chip, borderRadius: BorderRadius.circular(6))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final e in legend)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: e.$1, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Flexible(child: Text(e.$2, style: AvaText.caption.copyWith(color: c.ink))),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CuisineNameDialog extends StatefulWidget {
  const _CuisineNameDialog();

  @override
  State<_CuisineNameDialog> createState() => _CuisineNameDialogState();
}

class _CuisineNameDialogState extends State<_CuisineNameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (v.length >= 2) Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('restaurants_m_dish_cuisine_add_title')),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: context.tr('restaurants_m_dish_cuisine_add_label'),
          helperText: context.tr('restaurants_m_dish_cuisine_add_hint'),
          helperMaxLines: 4,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('cancel'))),
        FilledButton(
          onPressed: _name.text.trim().length >= 2 ? _submit : null,
          child: Text(context.tr('restaurants_m_dish_cuisine_add_ok')),
        ),
      ],
    );
  }
}
