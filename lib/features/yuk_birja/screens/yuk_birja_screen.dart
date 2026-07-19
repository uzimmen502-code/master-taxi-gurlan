import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
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
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  String _ownerId = '';
  String _ownerName = '';
  String _ownerPhone = '';
  String _tab = 'all';
  String _vehicleFilter = '';
  Set<String> _matchedIds = {};
  List<YukMatchPair> _pairs = [];
  bool _smartActive = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
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
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _weightCtrl.dispose();
    _store.dispose();
    super.dispose();
  }

  double? get _filterWeight {
    final t = _weightCtrl.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  List<YukListing> get _visible => _store.filtered(
        tab: _tab,
        from: _fromCtrl.text,
        to: _toCtrl.text,
        maxWeightTons: _filterWeight,
        vehicleType: _vehicleFilter,
        matchedIds: _matchedIds,
      );

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

  void _runSmartMatch() {
    final pairs = _store.smartMatch();
    final ids = <String>{};
    for (final p in pairs) {
      ids.add(p.cargo.id);
      ids.add(p.truck.id);
    }
    setState(() {
      _pairs = pairs;
      _matchedIds = ids;
      _smartActive = true;
      _tab = 'matched';
    });
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (_, scroll) {
          if (_pairs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(context.tr('yuk_match_empty'),
                  style: const TextStyle(color: _muted)),
            );
          }
          return ListView.separated(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            itemCount: _pairs.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              if (i == 0) {
                return Text(
                  context.tr('yuk_smart_match'),
                  style: const TextStyle(
                    color: _accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                );
              }
              final p = _pairs[i - 1];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p.cargo.from} → ${p.cargo.to}  ×  ${p.truck.from} → ${p.truck.to}',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${p.score}% · ${p.cargo.weight ?? 0}${context.tr('yuk_ton_short')} / ${(p.truck.freeSpace ?? 0)}${context.tr('yuk_ton_short')} · ${context.tr(yukVehicleLabelKey(p.cargo.vehicleType))}',
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _call(p.cargo);
                          },
                          icon: const Icon(Icons.phone, size: 16),
                          label: Text(context.tr('yuk_call_cargo')),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _call(p.truck);
                          },
                          icon: const Icon(Icons.phone, size: 16),
                          label: Text(context.tr('yuk_call_truck')),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
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
    setState(() {
      _tab = 'all';
      _smartActive = false;
      _matchedIds = {};
    });
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
          actions: [
            if (_smartActive)
              TextButton(
                onPressed: () => setState(() {
                  _smartActive = false;
                  _matchedIds = {};
                  _tab = 'all';
                }),
                child: Text(context.tr('yuk_clear_match'),
                    style: const TextStyle(color: _accent)),
              ),
          ],
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: _BigAction(
                                color: const Color(0xFF1E2A3A),
                                border: _blue,
                                icon: Icons.inventory_2_outlined,
                                label: context.tr('yuk_i_have_cargo'),
                                onTap: () => _openCreate(cargo: true),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _BigAction(
                                color: const Color(0xFF1E2A1E),
                                border: _green,
                                icon: Icons.local_shipping_outlined,
                                label: context.tr('yuk_i_have_truck'),
                                onTap: () => _openCreate(cargo: false),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _FiltersBar(
                        fromCtrl: _fromCtrl,
                        toCtrl: _toCtrl,
                        weightCtrl: _weightCtrl,
                        vehicleFilter: _vehicleFilter,
                        onVehicle: (v) => setState(() => _vehicleFilter = v),
                        onChanged: () => setState(() {}),
                        onReset: () {
                          _fromCtrl.clear();
                          _toCtrl.clear();
                          _weightCtrl.clear();
                          setState(() {
                            _vehicleFilter = '';
                            _tab = 'all';
                          });
                        },
                        onSmart: _runSmartMatch,
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            for (final t in [
                              ('all', 'yuk_tab_all'),
                              ('cargo', 'yuk_tab_cargo'),
                              ('truck', 'yuk_tab_truck'),
                              ('matched', 'yuk_tab_matched'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(context.tr(t.$2)),
                                  selected: _tab == t.$1,
                                  selectedColor: _accent.withValues(alpha: 0.25),
                                  labelStyle: TextStyle(
                                    color: _tab == t.$1 ? _accent : _muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  side: BorderSide(
                                    color: _tab == t.$1 ? _accent : _border,
                                  ),
                                  backgroundColor: _card,
                                  onSelected: (_) => setState(() => _tab = t.$1),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${items.length} ${context.tr('yuk_showing')} · $activeCount ${context.tr('yuk_active')}',
                            style: const TextStyle(color: _muted, fontSize: 13),
                          ),
                        ),
                      ),
                      Expanded(
                        child: items.isEmpty
                            ? Center(
                                child: Text(context.tr('yuk_empty'),
                                    style: const TextStyle(color: _muted)),
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (_, i) {
                                  final item = items[i];
                                  return _ListingCard(
                                    item: item,
                                    mine: _isMine(item),
                                    matched: _matchedIds.contains(item.id),
                                    onCall: () => _call(item),
                                    onClose: () => _close(item),
                                  );
                                },
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
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final Color border;
  final IconData icon;
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
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
          ),
          child: Column(
            children: [
              Icon(icon, color: border, size: 28),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
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
    required this.weightCtrl,
    required this.vehicleFilter,
    required this.onVehicle,
    required this.onChanged,
    required this.onReset,
    required this.onSmart,
  });

  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;
  final TextEditingController weightCtrl;
  final String vehicleFilter;
  final ValueChanged<String> onVehicle;
  final VoidCallback onChanged;
  final VoidCallback onReset;
  final VoidCallback onSmart;

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String hint) => InputDecoration(
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
        );

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
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: fromCtrl,
                  onChanged: (_) => onChanged(),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: deco(context.tr('yuk_from')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: toCtrl,
                  onChanged: (_) => onChanged(),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: deco(context.tr('yuk_to')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 88,
                child: TextField(
                  controller: weightCtrl,
                  onChanged: (_) => onChanged(),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: deco(context.tr('yuk_weight')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: vehicleFilter.isEmpty ? '' : vehicleFilter,
                  dropdownColor: const Color(0xFF1A232E),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: deco(context.tr('yuk_vehicle_type')),
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
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: onReset,
                child: Text(context.tr('yuk_reset')),
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFACC15),
                  foregroundColor: const Color(0xFF0B0E14),
                ),
                onPressed: onSmart,
                icon: const Icon(Icons.psychology_alt, size: 18),
                label: Text(context.tr('yuk_smart_match')),
              ),
            ],
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
    required this.matched,
    required this.onCall,
    required this.onClose,
  });

  final YukListing item;
  final bool mine;
  final bool matched;
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
          color: matched
              ? const Color(0xFF22C55E)
              : mine
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
              if (matched)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14532D),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(context.tr('yuk_match_pill'),
                      style: const TextStyle(
                          color: Color(0xFF4ADE80), fontSize: 11)),
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
  final _cargo = TextEditingController();
  final _weight = TextEditingController();
  final _capacity = TextEditingController();
  final _free = TextEditingController();
  final _price = TextEditingController();
  final _comment = TextEditingController();
  final _stopCtrls = <TextEditingController>[];
  String _vehicle = 'fura';

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
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

  List<String> get _stops => _stopCtrls
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: const Color(0xFF0B0E14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  void _submit() {
    final from = _from.text.trim();
    final to = _to.text.trim();
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
                  ? context.tr('yuk_create_cargo')
                  : context.tr('yuk_create_truck'),
              style: const TextStyle(
                  color: Color(0xFFFACC15),
                  fontSize: 18,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _from,
              style: const TextStyle(color: Colors.white),
              decoration: _deco(context.tr('yuk_from')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _to,
              style: const TextStyle(color: Colors.white),
              decoration: _deco(context.tr('yuk_to')),
            ),
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
                onPressed: () => setState(
                    () => _stopCtrls.add(TextEditingController())),
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
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
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
