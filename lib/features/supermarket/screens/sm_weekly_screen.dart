import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../data/sm_lists_repository.dart';
import '../data/supermarket_repository.dart' show smOriginWeekly;
import '../domain/sm_list.dart';
import '../domain/sm_offer.dart';
import '../domain/sm_qty.dart';
import '../domain/sm_search.dart';
import '../domain/sm_taxonomy.dart';
import '../supermarket_controller.dart';
import '../widgets/sm_compare_dialog.dart';
import '../widgets/sm_offer_pick_sheet.dart';
import '../widgets/sm_widgets.dart';
import 'supermarket_home_screen.dart';

/// Ҳафта кунлари калитлари (1 = душанба … 7 = якшанба).
String smWeekdayKey(int d) => 'sm_weekday_$d';

/// «Ҳафталик сават» (2-босқич, эга 2026-11-21): биринчи марта — «Бўш саватдан» / «Тайёр намунадан»;
/// кейин — сақланган рўйхатлар. ҲЕЧ ҚАЧОН буюртма бермайди: фақат саватга қўшади.
class SmWeeklyScreen extends StatefulWidget {
  const SmWeeklyScreen({super.key, required this.controller, this.store, this.memo, this.openListId});

  /// Push/«Хабарлар»дан (sm_weekly_reminder, smListId): юклангач шу рўйхат очилади (топилмаса — рўйхатлар).
  final String? openListId;

  final SupermarketController controller;

  /// Тест учун; бўлмаса — [FirestoreSmListsStore].
  final SmListsStore? store;
  final SmListPriceMemo? memo;

  @override
  State<SmWeeklyScreen> createState() => _SmWeeklyScreenState();
}

class _SmWeeklyScreenState extends State<SmWeeklyScreen> {
  late final SmListsStore _store = widget.store ?? FirestoreSmListsStore();
  late final SmListPriceMemo _memo = widget.memo ?? SmListPriceMemo();
  List<SmList>? _lists;
  bool _error = false;
  late String? _pendingOpen = widget.openListId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = false);
    try {
      final l = await _store.load();
      if (!mounted) return;
      setState(() => _lists = l);
      final target = _pendingOpen;
      _pendingOpen = null;
      if (target != null) {
        for (final x in l) {
          if (x.id == target) {
            await _open(x);
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('[Supermarket] SM_LISTS_LOAD_FAILED: $e');
      if (mounted) setState(() => _error = true);
    }
  }

  Future<void> _newList({required bool template}) async {
    final items = template ? smTemplateItems(widget.controller.taxonomy) : const <SmListItem>[];
    final saved = await Navigator.of(context).push<SmList>(MaterialPageRoute(
      builder: (_) => SmListEditorScreen(
        controller: widget.controller,
        store: _store,
        memo: _memo,
        initial: SmList(id: '', name: context.tr('sm_weekly_default_name'), items: items),
        existingCount: _lists?.length ?? 0,
      ),
    ));
    if (saved != null) await _load();
  }

  Future<void> _open(SmList l) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => SmSavedListScreen(controller: widget.controller, store: _store, memo: _memo, list: l),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lists = _lists;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('sm_weekly_title')),
        actions: [SmCartAction(controller: widget.controller, onTap: () => smOpenCart(context, widget.controller))],
      ),
      body: _error
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(context.tr('sm_err_load'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: Text(context.tr('sm_retry'))),
                ]),
              ),
            )
          : lists == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: lists.isEmpty ? _firstRun(context) : _saved(context, lists),
                ),
    );
  }

  List<Widget> _firstRun(BuildContext context) {
    final c = context.ava;
    return [
      Text(context.tr('sm_weekly_intro'), key: const ValueKey('sm_weekly_intro'), style: TextStyle(fontSize: 16, color: c.ink)),
      const SizedBox(height: 16),
      _BigChoice(
        key: const ValueKey('sm_weekly_start_empty'),
        icon: Icons.add_shopping_cart_rounded,
        title: context.tr('sm_weekly_start_empty'),
        onTap: () => _newList(template: false),
      ),
      const SizedBox(height: 12),
      _BigChoice(
        key: const ValueKey('sm_weekly_start_template'),
        icon: Icons.checklist_rounded,
        title: context.tr('sm_weekly_start_template'),
        subtitle: context.tr('sm_weekly_template_hint'),
        onTap: () => _newList(template: true),
      ),
      const SizedBox(height: 16),
      _NeverOrdersNote(),
    ];
  }

  List<Widget> _saved(BuildContext context, List<SmList> lists) {
    final c = context.ava;
    final full = lists.length >= kSmMaxLists;
    return [
      for (final l in lists) ...[
        Material(
          key: ValueKey('sm_weekly_list_${l.id}'),
          color: c.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _open(l),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.shopping_basket_outlined, color: c.brandText),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                    Text(context.tr('sm_weekly_items_count').replaceAll('{n}', '${l.items.length}'),
                        style: TextStyle(fontSize: 14, color: c.ink2)),
                    if (l.remind.enabled)
                      Text(_remindText(context, l.remind), style: TextStyle(fontSize: 14, color: c.ink2)),
                    if (l.invalid.isNotEmpty)
                      Text(context.tr('sm_list_invalid'),
                          key: ValueKey('sm_weekly_invalid_${l.id}'), style: TextStyle(fontSize: 14, color: c.danger)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: c.ink3),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
      OutlinedButton.icon(
        key: const ValueKey('sm_weekly_new'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: full ? null : () => _newList(template: false),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.tr('sm_weekly_new'), style: const TextStyle(fontSize: 16)),
      ),
      if (full)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(context.tr('sm_err_list_limit').replaceAll('{n}', '$kSmMaxLists'),
              key: const ValueKey('sm_weekly_limit'), style: TextStyle(fontSize: 14, color: c.ink2)),
        ),
    ];
  }
}

String _remindText(BuildContext context, SmRemind r) => context
    .tr('sm_remind_summary')
    .replaceAll('{day}', context.tr(smWeekdayKey(r.weekday)))
    .replaceAll('{time}', smHhMmOf(r.minute));

String smHhMmOf(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

class _BigChoice extends StatelessWidget {
  const _BigChoice({super.key, required this.icon, required this.title, required this.onTap, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: c.brandSoft, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: c.brandText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 14, color: c.ink2)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NeverOrdersNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      key: const ValueKey('sm_never_orders_note'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, color: c.ink2, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(context.tr('sm_weekly_never_orders'), style: TextStyle(fontSize: 14, color: c.ink))),
      ]),
    );
  }
}

/// Сақланган рўйхат: таркиб, «Жорий нархларда саватга қўшиш», таҳрирлаш, ўчириш.
class SmSavedListScreen extends StatefulWidget {
  const SmSavedListScreen({super.key, required this.controller, required this.store, required this.memo, required this.list});

  final SupermarketController controller;
  final SmListsStore store;
  final SmListPriceMemo memo;
  final SmList list;

  @override
  State<SmSavedListScreen> createState() => _SmSavedListScreenState();
}

class _SmSavedListScreenState extends State<SmSavedListScreen> {
  late SmList _list = widget.list;
  bool _busy = false;

  SupermarketController get _c => widget.controller;

  Future<void> _toCart() async {
    setState(() => _busy = true);
    try {
      final prices = await widget.memo.load(_list.id);
      if (!mounted) return;
      final n = await smCompareAndAddToCart(context, controller: _c, items: _list.items, previousPrices: prices, origin: smOriginWeekly);
      if (!mounted || n == 0) return;
      // Энди кўрилган нархлар — кейинги солиштириш учун асос.
      await widget.memo.save(_list.id, smPricesOf(_list.items, _c.offers));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          key: const ValueKey('sm_list_added_snack'),
          content: Text(context.tr('sm_list_added').replaceAll('{n}', '$n')),
          action: SnackBarAction(label: context.tr('sm_tab_cart'), onPressed: () => smOpenCart(context, _c)),
        ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<SmList>(MaterialPageRoute(
      builder: (_) => SmListEditorScreen(controller: _c, store: widget.store, memo: widget.memo, initial: _list),
    ));
    if (saved != null && mounted) setState(() => _list = saved);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('sm_list_delete')),
        content: Text(ctx.tr('sm_list_delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('sm_cancel'))),
          TextButton(key: const ValueKey('sm_list_delete_ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('sm_list_delete'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.store.delete(_list.id);
      await widget.memo.remove(_list.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[Supermarket] SM_LIST_DELETE_FAILED: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('sm_err_save'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(_list.name),
        actions: [
          IconButton(key: const ValueKey('sm_list_edit'), tooltip: context.tr('sm_list_edit'), onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
          IconButton(key: const ValueKey('sm_list_delete'), tooltip: context.tr('sm_list_delete'), onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          FilledButton.icon(
            key: const ValueKey('sm_list_to_cart'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy || _list.items.isEmpty ? null : _toCart,
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: Text(context.tr('sm_list_to_cart'), style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 8),
          _NeverOrdersNote(),
          if (_list.invalid.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('sm_list_invalid'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(12)),
              child: Text(context.tr('sm_list_invalid'), style: TextStyle(fontSize: 15, color: c.ink)),
            ),
          ],
          const SizedBox(height: 12),
          if (_list.remind.enabled)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(Icons.notifications_active_outlined, color: c.brandText, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(_remindText(context, _list.remind), key: const ValueKey('sm_list_remind_summary'), style: TextStyle(fontSize: 15, color: c.ink))),
              ]),
            ),
          for (final i in _list.items) _ItemLine(controller: _c, item: i, lang: lang),
        ],
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine({required this.controller, required this.item, required this.lang});

  final SupermarketController controller;
  final SmListItem item;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final g = controller.taxonomy.group(item.groupId);
    final o = controller.offers[item.offerId];
    final unit = smUnitLabel(context, o?.unit ?? g?.unit ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g?.name(lang) ?? item.groupId, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
            if (o != null) Text(o.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: c.ink2)),
          ]),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text('${smFormatQty(item.qtyMilli)} $unit'.trim(),
              textAlign: TextAlign.end, style: TextStyle(fontSize: 16, color: c.ink)),
        ),
      ]),
    );
  }
}

/// Рўйхат муҳаррири: ном, каталогдан қўшиш, миқдор, олиб ташлаш, эслатма (ҳафта куни + вақт).
class SmListEditorScreen extends StatefulWidget {
  const SmListEditorScreen({
    super.key,
    required this.controller,
    required this.store,
    required this.memo,
    required this.initial,
    this.existingCount,
    this.pickTime,
  });

  final SupermarketController controller;
  final SmListsStore store;
  final SmListPriceMemo memo;

  /// `id` бўш — янги рўйхат.
  final SmList initial;

  /// Янги рўйхатда маълум бўлса — сақлашда қайта ўқилмайди; йўқ — [SmListsStore.load] орқали.
  final int? existingCount;

  /// Тест учун; бўлмаса — [showTimePicker].
  final Future<TimeOfDay?> Function(BuildContext context, TimeOfDay initial)? pickTime;

  @override
  State<SmListEditorScreen> createState() => _SmListEditorScreenState();
}

class _SmListEditorScreenState extends State<SmListEditorScreen> {
  late SmList _list = widget.initial;
  late final TextEditingController _name = TextEditingController(text: widget.initial.name);
  bool _busy = false;
  String? _errorKey;

  SupermarketController get _c => widget.controller;
  bool get _isNew => widget.initial.id.isEmpty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addFromCatalog() async {
    final group = await showModalBottomSheet<SmGroup>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _GroupPicker(controller: _c),
    );
    if (group == null || !mounted) return;
    final r = await showSmOfferPickSheet(context, controller: _c, group: group);
    if (r == null || !mounted) return;
    setState(() => _list = _list.addItem(SmListItem(
          groupId: group.id,
          varietyId: r.offer.varietyId,
          offerId: r.offer.id,
          qtyMilli: r.qtyMilli,
        )));
  }

  Future<void> _pickTime() async {
    final init = TimeOfDay(hour: _list.remind.minute ~/ 60, minute: _list.remind.minute % 60);
    final t = await (widget.pickTime?.call(context, init) ?? showTimePicker(context: context, initialTime: init));
    if (t == null || !mounted) return;
    setState(() => _list = _list.copyWith(
        remind: SmRemind(enabled: _list.remind.enabled, weekday: _list.remind.weekday, minute: t.hour * 60 + t.minute)));
  }

  Future<void> _save() async {
    final draft = _list.copyWith(name: _name.text.trim());
    final problems = smListProblems(draft);
    if (problems.isNotEmpty) {
      setState(() => _errorKey = problems.first);
      return;
    }
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      SmList saved;
      if (_isNew) {
        final count = widget.existingCount ?? (await widget.store.load()).length;
        if (count >= kSmMaxLists) {
          if (mounted) setState(() => _errorKey = 'sm_err_list_limit');
          return;
        }
        final id = await widget.store.create(draft);
        saved = SmList(id: id, name: draft.name, items: draft.items, remind: draft.remind);
      } else {
        await widget.store.update(draft);
        saved = draft;
      }
      await widget.memo.save(saved.id, smPricesOf(saved.items, _c.offers));
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      debugPrint('[Supermarket] SM_LIST_SAVE_FAILED: $e');
      if (mounted) setState(() => _errorKey = 'sm_err_save');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final lang = context.contentLang;
    final r = _list.remind;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr(_isNew ? 'sm_list_new_title' : 'sm_list_edit'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          TextField(
            key: const ValueKey('sm_list_name'),
            controller: _name,
            maxLength: kSmListNameMax,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(labelText: context.tr('sm_list_name'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < _list.items.length; i++) _editRow(context, i, lang),
          if (_list.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(context.tr('sm_list_empty'), key: const ValueKey('sm_list_empty'), style: TextStyle(fontSize: 15, color: c.ink2)),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('sm_list_add_item'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _list.items.length >= kSmListItemsMax ? null : _addFromCatalog,
            icon: const Icon(Icons.add_rounded),
            label: Text(context.tr('sm_list_add_item'), style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  key: const ValueKey('sm_remind_toggle'),
                  contentPadding: EdgeInsets.zero,
                  value: r.enabled,
                  title: Text(context.tr('sm_remind_title'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                  onChanged: (v) => setState(() => _list = _list.copyWith(remind: SmRemind(enabled: v, weekday: r.weekday, minute: r.minute))),
                ),
                Text(context.tr('sm_remind_note'), key: const ValueKey('sm_remind_note'), style: TextStyle(fontSize: 14, color: c.ink2)),
                if (r.enabled) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    key: const ValueKey('sm_remind_weekday'),
                    initialValue: r.weekday,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: context.tr('sm_remind_day'), border: const OutlineInputBorder()),
                    items: [
                      for (var d = 1; d <= 7; d++) DropdownMenuItem(value: d, child: Text(context.tr(smWeekdayKey(d)))),
                    ],
                    onChanged: (d) => d == null
                        ? null
                        : setState(() => _list = _list.copyWith(remind: SmRemind(enabled: true, weekday: d, minute: r.minute))),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('sm_remind_time'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text('${context.tr('sm_remind_time')}: ${smHhMmOf(r.minute)}', style: const TextStyle(fontSize: 16)),
                  ),
                ],
              ],
            ),
          ),
          if (_errorKey != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(context.tr(_errorKey!).replaceAll('{n}', '$kSmMaxLists'),
                  key: const ValueKey('sm_list_error'), style: TextStyle(fontSize: 15, color: c.danger)),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('sm_list_save'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _save,
            child: Text(context.tr('sm_list_save'), style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _editRow(BuildContext context, int i, String lang) {
    final c = context.ava;
    final item = _list.items[i];
    final g = _c.taxonomy.group(item.groupId);
    final o = _c.offers[item.offerId];
    final step = o?.stepMilli ?? g?.stepMilli ?? 1000;
    return Container(
      key: ValueKey('sm_list_item_$i'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g?.name(lang) ?? item.groupId, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
                Text(o?.name ?? context.tr('sm_list_any_offer'), maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: c.ink2)),
              ]),
            ),
            IconButton(
              key: ValueKey('sm_list_remove_$i'),
              tooltip: context.tr('sm_remove'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => setState(() => _list = _list.removeAt(i)),
              icon: Icon(Icons.delete_outline_rounded, color: c.ink2),
            ),
          ]),
          SmQtyStepper(
            key: ValueKey('sm_list_qty_$i'),
            qtyMilli: smSnapQty(item.qtyMilli, step),
            stepMilli: step,
            unitLabel: smUnitLabel(context, o?.unit ?? g?.unit ?? ''),
            onChanged: (v) => setState(() => _list = _list.setQtyAt(i, v)),
          ),
        ],
      ),
    );
  }
}

/// Каталогдан гуруҳ танлаш (қидирув + рўйхат).
class _GroupPicker extends StatefulWidget {
  const _GroupPicker({required this.controller});

  final SupermarketController controller;

  @override
  State<_GroupPicker> createState() => _GroupPickerState();
}

class _GroupPickerState extends State<_GroupPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final lang = context.contentLang;
    final groups = _q.trim().isEmpty
        ? [for (final cat in c.taxonomy.categories) ...c.visibleGroups(cat)]
        : smSearchGroups(c.taxonomy, c.offersByGroup, _q);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        key: const ValueKey('sm_group_picker'),
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          TextField(
            key: const ValueKey('sm_group_picker_search'),
            onChanged: (v) => setState(() => _q = v),
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(hintText: context.tr('sm_search_hint'), prefixIcon: const Icon(Icons.search_rounded)),
          ),
          for (final g in groups)
            ListTile(
              key: ValueKey('sm_group_pick_${g.id}'),
              minTileHeight: 48,
              title: Text(g.name(lang), style: const TextStyle(fontSize: 16)),
              subtitle: _from(context, c.offersByGroup[g.id] ?? const [], g),
              onTap: () => Navigator.of(context).pop(g),
            ),
        ],
      ),
    );
  }

  Widget? _from(BuildContext context, List<SmOffer> offers, SmGroup g) {
    final p = smCheapestActivePrice(offers);
    return p == null ? null : Text(context.tr('sm_price_from').replaceAll('{price}', smPricePerUnit(context, p, g.unit)));
  }
}
