import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../utils/intercity_places.dart';
import '../models/yuk_listing.dart';
import '../yuk_birja_store.dart';
import '../yuk_vehicle_types.dart';

/// Юк биржаси — MVP (қўнғироқ + ўз эълонни ёпиш).
class YukBirjaScreen extends StatefulWidget {
  const YukBirjaScreen({super.key});

  @override
  State<YukBirjaScreen> createState() => _YukBirjaScreenState();
}

class _YukBirjaScreenState extends State<YukBirjaScreen> {
  static const _bg = Color(0xFF0B0E14);
  static const _card = Color(0xFF131A22);
  static const _border = Color(0xFF252B36);
  static const _muted = Color(0xFF94A3B8);
  static const _accent = Color(0xFFFACC15);
  static const _blue = Color(0xFF3B82F6);
  static const _green = Color(0xFF22C55E);

  final _store = YukBirjaStore();
  final _listCtrl = ScrollController();
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();

  String _ownerId = '';
  String _ownerName = '';
  String _ownerPhone = '';
  String _tab = 'all';

  /// Драфт (ёзилмоқда) — «Қидируш»гача рўйхатга таъсир қилмайди.
  String _draftVehicle = '';

  /// Қўлланилган фильтр (фақат «Қидируш»дан кейин).
  String _appliedFrom = '';
  String _appliedTo = '';
  String _appliedVehicle = '';

  /// Пастга скроллда эълон/қидирув яширилади; юқорига — қайта очилади.
  bool _toolsExpanded = true;

  List<String> _fromSuggestions = [];
  List<String> _toSuggestions = [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _fromFocus.addListener(() {
      if (!_fromFocus.hasFocus) setState(() => _fromSuggestions = []);
    });
    _toFocus.addListener(() {
      if (!_toFocus.hasFocus) setState(() => _toSuggestions = []);
    });
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = phoneDigits(prefs.getString('user_phone') ?? '');
    final name = (prefs.getString('user_name') ?? '').trim();
    await _store.load();
    if (!mounted) return;
    setState(() {
      _ownerId = phone.length >= 9 ? phone : '';
      _ownerName = name.isEmpty ? context.tr('yuk_you') : name;
      _ownerPhone = phone.length >= 9 ? '+$phone' : '';
    });
  }

  @override
  void dispose() {
    _listCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    _store.dispose();
    super.dispose();
  }

  void _onTabTap(String tab) {
    setState(() {
      _tab = tab;
      _toolsExpanded = true;
    });
    if (_listCtrl.hasClients) {
      _listCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Locale get _locale => Localizations.localeOf(context);

  List<YukListing> get _visible => _store.filtered(
        tab: _tab,
        from: _appliedFrom,
        to: _appliedTo,
        vehicleType: _appliedVehicle,
      );

  void _refreshFromSuggestions(String q) {
    setState(() {
      _fromSuggestions = IntercityPlaces.search(q, locale: _locale);
    });
  }

  void _refreshToSuggestions(String q) {
    setState(() {
      _toSuggestions = IntercityPlaces.search(q, locale: _locale);
    });
  }

  void _pickFrom(String display) {
    final canonical = IntercityPlaces.normalizeLocation(display);
    _fromCtrl.text = IntercityPlaces.displayForLocale(canonical, _locale);
    setState(() => _fromSuggestions = []);
    _fromFocus.unfocus();
  }

  void _pickTo(String display) {
    final canonical = IntercityPlaces.normalizeLocation(display);
    _toCtrl.text = IntercityPlaces.displayForLocale(canonical, _locale);
    setState(() => _toSuggestions = []);
    _toFocus.unfocus();
  }

  void _runSearch() {
    setState(() {
      _appliedFrom = IntercityPlaces.normalizeLocation(_fromCtrl.text);
      _appliedTo = IntercityPlaces.normalizeLocation(_toCtrl.text);
      _appliedVehicle = _draftVehicle;
      _fromSuggestions = [];
      _toSuggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  bool _onListScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is! ScrollUpdateNotification) return false;
    final delta = n.scrollDelta ?? 0;
    final pixels = n.metrics.pixels;
    if (pixels <= 8) {
      if (!_toolsExpanded) setState(() => _toolsExpanded = true);
      return false;
    }
    if (delta > 6 && _toolsExpanded) {
      setState(() {
        _toolsExpanded = false;
        _fromSuggestions = [];
        _toSuggestions = [];
      });
      FocusScope.of(context).unfocus();
    } else if (delta < -6 && !_toolsExpanded) {
      setState(() => _toolsExpanded = true);
    }
    return false;
  }

  bool _isMine(YukListing item) =>
      _ownerId.isNotEmpty && item.ownerId == _ownerId;

  Future<void> _call(YukListing item) async {
    if (_isMine(item)) {
      _snack(context.tr('yuk_own_listing_call'));
      return;
    }
    final ok = await callPhone(item.phone);
    if (!ok && mounted) _snack(context.tr('yuk_call_fail'));
  }

  Future<void> _close(YukListing item) async {
    if (!_isMine(item)) {
      _snack(context.tr('yuk_close_only_own'));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(context.tr('yuk_close_title'),
            style: const TextStyle(color: Colors.white)),
        content: Text(
          '${item.from} → ${item.to}\n${context.tr('yuk_close_confirm')}',
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('yuk_close_btn'),
                style: const TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final closed = await _store.closeListing(
      id: item.id,
      currentOwnerId: _ownerId,
    );
    if (!mounted) return;
    _snack(closed
        ? context.tr('yuk_closed_ok')
        : context.tr('yuk_close_only_own'));
    setState(() {});
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openCreate({required bool cargo}) async {
    if (_ownerId.isEmpty) {
      _snack(context.tr('yuk_need_phone'));
      return;
    }
    final created = await showModalBottomSheet<YukListing>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CreateListingSheet(
        isCargo: cargo,
        ownerId: _ownerId,
        ownerName: _ownerName,
        ownerPhone: _ownerPhone,
      ),
    );
    if (created == null) return;
    await _store.addListing(created);
    if (!mounted) return;
    setState(() => _tab = 'all');
    _snack(context.tr('yuk_posted_ok'));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          secondary: _blue,
          surface: _card,
        ),
      ),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          title: Text(context.tr('home_module_yuk_birja')),
        ),
        body: !_store.ready
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : ListenableBuilder(
                listenable: _store,
                builder: (context, _) {
                  final items = _visible;
                  final activeCount =
                      _store.listings.where((e) => e.isActive).length;
                  return Column(
                    children: [
                      ClipRect(
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _toolsExpanded
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          16, 0, 16, 8),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: _BigAction(
                                              color: const Color(0xFF1E2A3A),
                                              border: _blue,
                                              label: context
                                                  .tr('yuk_send_cargo'),
                                              onTap: () =>
                                                  _openCreate(cargo: true),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: _BigAction(
                                              color: const Color(0xFF1E2A1E),
                                              border: _green,
                                              label: context
                                                  .tr('yuk_take_cargo'),
                                              onTap: () =>
                                                  _openCreate(cargo: false),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    _FiltersBar(
                                      fromCtrl: _fromCtrl,
                                      toCtrl: _toCtrl,
                                      fromFocus: _fromFocus,
                                      toFocus: _toFocus,
                                      fromSuggestions: _fromSuggestions,
                                      toSuggestions: _toSuggestions,
                                      vehicleFilter: _draftVehicle,
                                      onVehicle: (v) =>
                                          setState(() => _draftVehicle = v),
                                      onFromChanged: _refreshFromSuggestions,
                                      onToChanged: _refreshToSuggestions,
                                      onPickFrom: _pickFrom,
                                      onPickTo: _pickTo,
                                      onSearch: _runSearch,
                                    ),
                                  ],
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ),
                      Material(
                        color: _bg,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                          child: Row(
                            children: [
                              for (final t in [
                                ('all', 'yuk_tab_all'),
                                ('cargo', 'yuk_tab_cargo'),
                                ('truck', 'yuk_tab_truck'),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ChoiceChip(
                                    label: Text(context.tr(t.$2)),
                                    selected: _tab == t.$1,
                                    selectedColor:
                                        _accent.withValues(alpha: 0.25),
                                    labelStyle: TextStyle(
                                      color: _tab == t.$1 ? _accent : _muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    side: BorderSide(
                                      color: _tab == t.$1 ? _accent : _border,
                                    ),
                                    backgroundColor: _card,
                                    onSelected: (_) => _onTabTap(t.$1),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_toolsExpanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${items.length} ${context.tr('yuk_showing')} · $activeCount ${context.tr('yuk_active')}',
                              style:
                                  const TextStyle(color: _muted, fontSize: 13),
                            ),
                          ),
                        ),
                      Expanded(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _onListScroll,
                          child: items.isEmpty
                              ? Center(
                                  child: Text(context.tr('yuk_empty'),
                                      style: const TextStyle(color: _muted)),
                                )
                              : ListView.separated(
                                  controller: _listCtrl,
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 4, 16, 24),
                                  itemCount: items.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (_, i) {
                                    final item = items[i];
                                    return _ListingCard(
                                      item: item,
                                      mine: _isMine(item),
                                      onCall: () => _call(item),
                                      onClose: () => _close(item),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _BigAction extends StatelessWidget {
  const _BigAction({
    required this.color,
    required this.border,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final Color border;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
          ),
          alignment: Alignment.center,
          child: Text(
            '＋ $label',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.fromCtrl,
    required this.toCtrl,
    required this.fromFocus,
    required this.toFocus,
    required this.fromSuggestions,
    required this.toSuggestions,
    required this.vehicleFilter,
    required this.onVehicle,
    required this.onFromChanged,
    required this.onToChanged,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onSearch,
  });

  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;
  final FocusNode fromFocus;
  final FocusNode toFocus;
  final List<String> fromSuggestions;
  final List<String> toSuggestions;
  final String vehicleFilter;
  final ValueChanged<String> onVehicle;
  final ValueChanged<String> onFromChanged;
  final ValueChanged<String> onToChanged;
  final ValueChanged<String> onPickFrom;
  final ValueChanged<String> onPickTo;
  final VoidCallback onSearch;

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: const Color(0xFF0B0E14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFF2D3748)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFF2D3748)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFFACC15)),
        ),
      );

  Widget _suggestions(List<String> items, ValueChanged<String> onPick) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2D3748)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0xFF252B36)),
        itemBuilder: (_, i) {
          final label = items[i];
          return InkWell(
            onTap: () => onPick(label),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 16, color: Color(0xFFFACC15)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF131A22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF252B36)),
      ),
      child: Column(
        children: [
          TextField(
            controller: fromCtrl,
            focusNode: fromFocus,
            onChanged: onFromChanged,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _deco(context.tr('yuk_from')),
          ),
          _suggestions(fromSuggestions, onPickFrom),
          const SizedBox(height: 8),
          TextField(
            controller: toCtrl,
            focusNode: toFocus,
            onChanged: onToChanged,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _deco(context.tr('yuk_to')),
          ),
          _suggestions(toSuggestions, onPickTo),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use
            value: vehicleFilter.isEmpty ? '' : vehicleFilter,
            dropdownColor: const Color(0xFF1A232E),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _deco(context.tr('yuk_vehicle_type')),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(context.tr('yuk_vehicle_all')),
              ),
              ...kYukVehicleTypes.map(
                (t) => DropdownMenuItem(
                  value: t.value,
                  child: Text(context.tr(t.labelKey)),
                ),
              ),
            ],
            onChanged: (v) => onVehicle(v ?? ''),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFACC15),
                foregroundColor: const Color(0xFF0B0E14),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: onSearch,
              icon: const Icon(Icons.search, size: 20),
              label: Text(
                context.tr('yuk_search'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.item,
    required this.mine,
    required this.onCall,
    required this.onClose,
  });

  final YukListing item;
  final bool mine;
  final VoidCallback onCall;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final route = item.routeCities.join(' → ');
    final vLabel = context.tr(yukVehicleLabelKey(item.vehicleType));
    final ton = context.tr('yuk_ton_short');
    final details = item.isCargo
        ? '${item.weight ?? 0}$ton · ${item.cargo ?? ''} · $vLabel'
        : '${context.tr('yuk_capacity')}: ${item.capacity ?? 0}$ton · ${context.tr('yuk_free')}: ${item.freeSpace ?? 0}$ton · $vLabel';
    final price = item.price > 0
        ? '${item.price.toStringAsFixed(0)} ${context.tr('sum')}'
        : context.tr('yuk_negotiable');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF131A22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: mine
              ? const Color(0xFFFACC15).withValues(alpha: 0.45)
              : const Color(0xFF252B36),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (mine)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF422006),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(context.tr('yuk_mine'),
                      style: const TextStyle(
                          color: Color(0xFFFACC15), fontSize: 11)),
                ),
              const Spacer(),
              Text(
                item.isCargo
                    ? context.tr('yuk_badge_cargo')
                    : context.tr('yuk_badge_truck'),
                style: TextStyle(
                  color: item.isCargo
                      ? const Color(0xFF60A5FA)
                      : const Color(0xFF4ADE80),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(route,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          if (item.stops.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: item.stops
                  .map(
                    (s) => Chip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: const Color(0xFF0B0E14),
                      side: const BorderSide(color: Color(0xFF2D3748)),
                      label: Text(s,
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 11)),
                      avatar: const Icon(Icons.place,
                          size: 14, color: Color(0xFFFACC15)),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 6),
          Text(details,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
          const SizedBox(height: 6),
          Text(price,
              style: const TextStyle(
                  color: Color(0xFFFACC15),
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          Text(context.tr('yuk_price_hint'),
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.person, size: 16, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Expanded(
                child: Text(item.ownerName,
                    style: const TextStyle(color: Color(0xFF94A3B8))),
              ),
              Text('★ ${item.stars}',
                  style: const TextStyle(color: Color(0xFFFACC15))),
              const SizedBox(width: 8),
              if (mine)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF3F1D1D),
                    foregroundColor: const Color(0xFFFCA5A5),
                  ),
                  onPressed: onClose,
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: Text(context.tr('yuk_close_btn')),
                )
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFACC15),
                    foregroundColor: const Color(0xFF0B0E14),
                  ),
                  onPressed: onCall,
                  icon: const Icon(Icons.phone, size: 16),
                  label: Text(context.tr('yuk_call')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreateListingSheet extends StatefulWidget {
  const _CreateListingSheet({
    required this.isCargo,
    required this.ownerId,
    required this.ownerName,
    required this.ownerPhone,
  });

  final bool isCargo;
  final String ownerId;
  final String ownerName;
  final String ownerPhone;

  @override
  State<_CreateListingSheet> createState() => _CreateListingSheetState();
}

class _CreateListingSheetState extends State<_CreateListingSheet> {
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();
  final _cargo = TextEditingController();
  final _weight = TextEditingController();
  final _capacity = TextEditingController();
  final _free = TextEditingController();
  final _price = TextEditingController();
  final _comment = TextEditingController();
  final _stopCtrls = <TextEditingController>[];
  String _vehicle = 'fura';
  List<String> _fromSuggestions = [];
  List<String> _toSuggestions = [];

  @override
  void initState() {
    super.initState();
    _fromFocus.addListener(() {
      if (!_fromFocus.hasFocus) setState(() => _fromSuggestions = []);
    });
    _toFocus.addListener(() {
      if (!_toFocus.hasFocus) setState(() => _toSuggestions = []);
    });
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    _cargo.dispose();
    _weight.dispose();
    _capacity.dispose();
    _free.dispose();
    _price.dispose();
    _comment.dispose();
    for (final c in _stopCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Locale get _locale => Localizations.localeOf(context);

  List<String> get _stops => _stopCtrls
      .map((c) => IntercityPlaces.normalizeLocation(c.text))
      .where((s) => s.isNotEmpty)
      .toList();

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: const Color(0xFF0B0E14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  Widget _placeSuggestions(List<String> items, ValueChanged<String> onPick) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      constraints: const BoxConstraints(maxHeight: 160),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2D3748)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0xFF252B36)),
        itemBuilder: (_, i) => ListTile(
          dense: true,
          leading: const Icon(Icons.location_on_outlined,
              size: 16, color: Color(0xFFFACC15)),
          title: Text(items[i],
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          onTap: () => onPick(items[i]),
        ),
      ),
    );
  }

  void _submit() {
    final from = IntercityPlaces.normalizeLocation(_from.text);
    final to = IntercityPlaces.normalizeLocation(_to.text);
    if (from.isEmpty || to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('yuk_need_route'))),
      );
      return;
    }

    if (widget.isCargo) {
      final w = double.tryParse(_weight.text.trim()) ?? 0;
      if (w <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('yuk_need_weight'))),
        );
        return;
      }
      Navigator.pop(
        context,
        YukListing(
          id: 'u_${DateTime.now().microsecondsSinceEpoch}',
          type: YukListingType.cargo,
          from: from,
          to: to,
          stops: _stops,
          vehicleType: normalizeYukVehicleType(_vehicle),
          ownerId: widget.ownerId,
          ownerName: widget.ownerName,
          phone: widget.ownerPhone,
          status: YukListingStatus.active,
          cargo: _cargo.text.trim().isEmpty
              ? context.tr('yuk_badge_cargo')
              : _cargo.text.trim(),
          weight: w,
          price: double.tryParse(_price.text.trim()) ?? 0,
          comment: _comment.text.trim(),
        ),
      );
      return;
    }

    final cap = double.tryParse(_capacity.text.trim()) ?? 0;
    final free = double.tryParse(_free.text.trim()) ?? 0;
    if (cap <= 0 || free <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('yuk_need_capacity'))),
      );
      return;
    }
    if (free > cap) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('yuk_free_gt_cap'))),
      );
      return;
    }
    Navigator.pop(
      context,
      YukListing(
        id: 'u_${DateTime.now().microsecondsSinceEpoch}',
        type: YukListingType.truck,
        from: from,
        to: to,
        stops: _stops,
        vehicleType: normalizeYukVehicleType(_vehicle),
        ownerId: widget.ownerId,
        ownerName: widget.ownerName,
        phone: widget.ownerPhone,
        status: YukListingStatus.active,
        capacity: cap,
        freeSpace: free,
        price: double.tryParse(_price.text.trim()) ?? 0,
        comment: _comment.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.isCargo
                  ? context.tr('yuk_send_cargo')
                  : context.tr('yuk_take_cargo'),
              style: const TextStyle(
                  color: Color(0xFFFACC15),
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _from,
              focusNode: _fromFocus,
              onChanged: (q) => setState(() {
                _fromSuggestions = IntercityPlaces.search(q, locale: _locale);
              }),
              style: const TextStyle(color: Colors.white),
              decoration: _deco(context.tr('yuk_from')),
            ),
            _placeSuggestions(_fromSuggestions, (s) {
              final c = IntercityPlaces.normalizeLocation(s);
              _from.text = IntercityPlaces.displayForLocale(c, _locale);
              setState(() => _fromSuggestions = []);
              _fromFocus.unfocus();
            }),
            const SizedBox(height: 10),
            TextField(
              controller: _to,
              focusNode: _toFocus,
              onChanged: (q) => setState(() {
                _toSuggestions = IntercityPlaces.search(q, locale: _locale);
              }),
              style: const TextStyle(color: Colors.white),
              decoration: _deco(context.tr('yuk_to')),
            ),
            _placeSuggestions(_toSuggestions, (s) {
              final c = IntercityPlaces.normalizeLocation(s);
              _to.text = IntercityPlaces.displayForLocale(c, _locale);
              setState(() => _toSuggestions = []);
              _toFocus.unfocus();
            }),
            const SizedBox(height: 10),
            Text(context.tr('yuk_stops'),
                style: const TextStyle(color: Color(0xFF94A3B8))),
            const SizedBox(height: 6),
            ..._stopCtrls.asMap().entries.map((e) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: e.value,
                        style: const TextStyle(color: Colors.white),
                        decoration: _deco(context.tr('yuk_stop_hint')),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        _stopCtrls.removeAt(e.key).dispose();
                      }),
                      icon: const Icon(Icons.close, color: Colors.white54),
                    ),
                  ],
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _stopCtrls.add(TextEditingController())),
                icon: const Icon(Icons.add),
                label: Text(context.tr('yuk_add_stop')),
              ),
            ),
            if (widget.isCargo) ...[
              TextField(
                controller: _cargo,
                style: const TextStyle(color: Colors.white),
                decoration: _deco(context.tr('yuk_cargo_type')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _weight,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: const TextStyle(color: Colors.white),
                decoration: _deco(context.tr('yuk_weight_tons')),
              ),
            ] else ...[
              TextField(
                controller: _capacity,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: const TextStyle(color: Colors.white),
                decoration: _deco(context.tr('yuk_capacity_tons')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _free,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: const TextStyle(color: Colors.white),
                decoration: _deco(context.tr('yuk_free_tons')),
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _vehicle,
              dropdownColor: const Color(0xFF1A232E),
              style: const TextStyle(color: Colors.white),
              decoration: _deco(context.tr('yuk_vehicle_type')),
              items: kYukVehicleTypes
                  .map(
                    (t) => DropdownMenuItem(
                      value: t.value,
                      child: Text(context.tr(t.labelKey)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _vehicle = v ?? _vehicle),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white),
              decoration: _deco(context.tr('yuk_price_optional')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _comment,
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              decoration: _deco(context.tr('yuk_comment')),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _submit,
              child: Text(context.tr('yuk_post')),
            ),
          ],
        ),
      ),
    );
  }
}
