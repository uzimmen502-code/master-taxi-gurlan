import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../realty_tabs.dart';
import '../widgets/realty_map_view.dart';
import '../widgets/realty_package_sheet.dart';
import 'add_realty_listing_screen.dart';
import 'realty_detail_screen.dart';

/// 🗺 Кўчмас мулк — ТЎЛИҚ ЭКРАНЛИ харита.
///
/// Нега алоҳида экран (эга қарори, 2026-09-28): аввал харита лента
/// экранининг пастида 260px тасма эди. Бош саҳифадаги харита расми
/// босилганда фойдаланувчи ХАРИТА кутади, лекин рўйхатга тушиб қолар,
/// харита эса пастда сиқилиб турар эди. EV бўлимида бу масала аллақачон
/// шундай ечилган: статик расм → тўлиқ экранли харита.
///
/// Очилмаган объектлар тахминий нуқтада, пакетдан очилганлари аниқ
/// жойида кўринади — иккови ҳам нарх ёрлиғи билан.
class RealtyMapScreen extends StatefulWidget {
  const RealtyMapScreen({super.key, this.deal});

  /// Лента экранидан келган филтр — харита ҳам шунга бўйсунсин.
  final RealtyDeal? deal;

  @override
  State<RealtyMapScreen> createState() => _RealtyMapScreenState();
}

class _RealtyMapScreenState extends State<RealtyMapScreen> {
  final _repo = RealtyRepository();
  final _mapKey = GlobalKey<RealtyMapViewState>();
  final _searchCtrl = TextEditingController();

  /// `listingId` → аниқ координата. Бир марта ўқилгач кешда қолади.
  final Map<String, LatLng> _exact = {};
  final Set<String> _requested = {};

  late RealtyDeal? _deal = widget.deal;

  /// Бўш бўлса — бутун ҳудуд. Фойдаланувчининг ўз тумани билан
  /// бошланади: бош саҳифа бўлимлари ҳам шундай ишлайди, ва бу
  /// сўровни 300 талик чегарага тиқилиб қолишдан сақлайди.
  late String _districtId = ServiceConfigHolder.districtId.trim();

  /// Камерани қайта мослаш белгиси — филтр ёки ҳудуд алмашганда ошади.
  int _fitToken = 0;

  /// Пастдаги карточка тасмасида турган объект.
  String? _selectedId;

  /// Харитадаги қидирув матни — юкланган эълонлар ичидан филтрлайди.
  ///
  /// Геокодер ИШЛАТИЛМАЙДИ: аниқ манзил пуллик ахборот, шунинг учун
  /// манзил бўйича жойга бориш пакетсиз фойдаланувчига ўша ахборотни
  /// текинга берган бўлар эди. Қидирув эълон матни ва нархи бўйича.
  String _query = '';

  bool get _hasDistrict => ServiceConfigHolder.districtId.trim().isNotEmpty;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Очилган объектларнинг аниқ нуқтасини ПАРАЛЛЕЛ ўқийди.
  Future<void> _loadExact(Iterable<String> ids) async {
    final missing = ids.where((id) => !_requested.contains(id)).toList();
    if (missing.isEmpty) return;
    _requested.addAll(missing);
    final details = await _repo.fetchDetails(missing);
    if (!mounted || details.isEmpty) return;
    setState(() {
      for (final e in details.entries) {
        _exact[e.key] = LatLng(e.value.lat, e.value.lng);
      }
    });
  }

  void _openDetail(RealtyListing listing) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RealtyDetailScreen(listing: listing)),
    );
  }

  /// Пин босилганда — ҳимоя шу ерда ишлайди (эга қарори, 2026-09-29).
  ///
  /// Очилмаган объектда фойдаланувчи ТЎҒРИДАН-ТЎҒРИ карточкага тушмайди:
  /// аввал харитадаги нуқта тахминий экани айтилади ва пакет таклиф
  /// қилинади. Аввал пин ҳам, босилиши ҳам очилган объект билан бир хил
  /// эди — харидор пинни аниқ манзил деб ўйлар, ҳолбуки у ≈1.2 км
  /// силкитилган.
  Future<void> _onPinTap(RealtyListing listing, Set<String> unlocked) async {
    if (unlocked.contains(listing.id)) {
      _openDetail(listing);
      return;
    }
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ApproxPinSheet(listing: listing),
    );
    if (!mounted || action == null) return;
    if (action == 'detail') {
      _openDetail(listing);
      return;
    }
    // 'package' — пакет варағи. Олингач харитадаги оқим узилмасин:
    // фойдаланувчи ўша объект карточкасида очишни давом эттиради.
    final bought = await showRealtyPackageSheet(context);
    if (bought && mounted) _openDetail(listing);
  }

  /// Қидирувга мос эълонлар. Бўш сўровда ҳаммаси.
  List<RealtyListing> _filtered(List<RealtyListing> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((r) {
      return r.titleOrText.toLowerCase().contains(q) ||
          r.priceText.toLowerCase().contains(q) ||
          r.specsLabel.toLowerCase().contains(q) ||
          r.addressText.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  void _setDeal(RealtyDeal? d) => setState(() {
        _deal = d;
        _selectedId = null;
        _fitToken++;
      });

  void _setDistrict(String id) => setState(() {
        _districtId = id;
        _selectedId = null;
        _fitToken++;
      });

  void _selectFromStrip(RealtyListing r) {
    setState(() => _selectedId = r.id);
    _mapKey.currentState?.focusOn(r);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('realty_map_title')),
        actions: [
          _UnlocksLeftChip(stream: _repo.watchUnlocksLeft()),
          RealtyAddButton(onTap: _openAdd),
        ],
      ),
      body: Column(
        children: [
          RealtyDealFilter(deal: _deal, onChanged: _setDeal),
          _SearchBar(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            onClear: () {
              _searchCtrl.clear();
              setState(() => _query = '');
            },
          ),
          if (_hasDistrict)
            _ScopeSwitch(
              districtOnly: _districtId.isNotEmpty,
              onChanged: (districtOnly) => _setDistrict(
                districtOnly ? ServiceConfigHolder.districtId.trim() : '',
              ),
            ),
          const RealtyMapLegend(),
          Expanded(
            child: StreamBuilder<Set<String>>(
              stream: _repo.watchUnlockedIds(),
              builder: (context, unlockedSnap) {
                final unlocked = unlockedSnap.data ?? const <String>{};
                return StreamBuilder<List<RealtyListing>>(
                  stream: _repo.watchForMap(
                    deal: _deal,
                    districtId: _districtId,
                  ),
                  builder: (context, snap) {
                    final all = snap.data ?? const <RealtyListing>[];
                    final listings = _filtered(all);
                    final visibleUnlocked = listings
                        .map((r) => r.id)
                        .where(unlocked.contains)
                        .toList();
                    if (visibleUnlocked.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _loadExact(visibleUnlocked),
                      );
                    }
                    return Stack(
                      children: [
                        RealtyMapView(
                          key: _mapKey,
                          listings: listings,
                          exactPoints: _exact,
                          selectedId: _selectedId,
                          fitToken: _fitToken,
                          onSelectionChanged: (r) =>
                              setState(() => _selectedId = r.id),
                          onListingTap: (r) => _onPinTap(r, unlocked),
                        ),
                        if (listings.isEmpty && snap.hasData)
                          Center(
                            child: Container(
                              margin: const EdgeInsets.all(24),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: c.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                context.tr('realty_map_empty'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: c.ink2),
                              ),
                            ),
                          ),
                        // Пастдаги карточка тасмаси: пин босилганда шу
                        // ерга сурилади, тасма сурилганда камера жойига
                        // боради — рўйхатга қайтмасдан объектларни
                        // кўриб чиқиш мумкин.
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _ListingStrip(
                            listings: listings,
                            selectedId: _selectedId,
                            unlocked: unlocked,
                            onSelected: _selectFromStrip,
                            onOpen: (r) => _onPinTap(r, unlocked),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAdd() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddRealtyListingScreen()),
    );
  }
}

/// Харитадаги қидирув — юкланган эълонлар ичидан.
class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: c.ink, fontSize: AppText.bodyMedium),
        decoration: InputDecoration(
          hintText: context.tr('realty_map_search_hint'),
          prefixIcon: Icon(Icons.search, size: 20, color: c.ink3),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, size: 18, color: c.ink3),
                  onPressed: onClear,
                ),
          filled: true,
          fillColor: c.surface,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.line),
          ),
        ),
      ),
    );
  }
}

/// «Туманимда» ↔ «Бутун ҳудуд». Сўров 300 та билан чекланган, шунинг
/// учун ҳудудни торайтириш — фойдаланувчи учун ҳам, сўров учун ҳам
/// фойда.
class _ScopeSwitch extends StatelessWidget {
  const _ScopeSwitch({required this.districtOnly, required this.onChanged});

  final bool districtOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    Widget chip(String labelKey, bool value) {
      final selected = districtOnly == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? c.brand : c.surface,
              border: Border.all(color: selected ? c.brand : c.line),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              context.tr(labelKey),
              style: TextStyle(
                fontSize: AppText.labelLarge,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : c.ink2,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          chip('realty_map_scope_district', true),
          chip('realty_map_scope_all', false),
        ],
      ),
    );
  }
}

/// Харита остидаги сурилувчи карточка тасмаси.
class _ListingStrip extends StatefulWidget {
  const _ListingStrip({
    required this.listings,
    required this.selectedId,
    required this.unlocked,
    required this.onSelected,
    required this.onOpen,
  });

  final List<RealtyListing> listings;
  final String? selectedId;
  final Set<String> unlocked;

  /// Тасма сурилганда — камера шу объектга борсин.
  final ValueChanged<RealtyListing> onSelected;

  /// Карточка босилганда — тафсилот ёки пакет таклифи.
  final ValueChanged<RealtyListing> onOpen;

  @override
  State<_ListingStrip> createState() => _ListingStripState();
}

class _ListingStripState extends State<_ListingStrip> {
  static const double _cardWidth = 246;
  late final PageController _ctrl =
      PageController(viewportFraction: 0.82, initialPage: _indexOfSelected());

  int _indexOfSelected() {
    final id = widget.selectedId;
    if (id == null) return 0;
    final i = widget.listings.indexWhere((r) => r.id == id);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(_ListingStrip old) {
    super.didUpdateWidget(old);
    // Пин босилганда тасма ўша карточкага сурилсин.
    if (widget.selectedId != old.selectedId && widget.selectedId != null) {
      final i = _indexOfSelected();
      if (_ctrl.hasClients && i != _ctrl.page?.round()) {
        _ctrl.animateToPage(
          i,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.listings.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 118,
      child: PageView.builder(
        controller: _ctrl,
        padEnds: false,
        itemCount: widget.listings.length,
        onPageChanged: (i) => widget.onSelected(widget.listings[i]),
        itemBuilder: (_, i) {
          final r = widget.listings[i];
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 12),
            child: SizedBox(
              width: _cardWidth,
              child: _StripCard(
                listing: r,
                unlocked: widget.unlocked.contains(r.id),
                onTap: () => widget.onOpen(r),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StripCard extends StatelessWidget {
  const _StripCard({
    required this.listing,
    required this.unlocked,
    required this.onTap,
  });

  final RealtyListing listing;
  final bool unlocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final tierColor = RealtyTabs.colorFor(listing.tier);
    final image =
        listing.imageUrls.isNotEmpty ? listing.imageUrls.first : null;
    return Material(
      color: c.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 84,
              height: double.infinity,
              child: image == null
                  ? Container(
                      color: c.surface2,
                      child: Icon(Icons.home_outlined, color: c.ink3),
                    )
                  : CachedNetworkImage(
                      imageUrl: image,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => ColoredBox(color: c.surface2),
                      errorWidget: (_, __, ___) => Container(
                        color: c.surface2,
                        child: Icon(Icons.home_outlined, color: c.ink3),
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: tierColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            listing.priceText.trim().isEmpty
                                ? context.tr('realty_price_unset')
                                : listing.priceText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: AppText.bodyMedium,
                              color: c.ink,
                            ),
                          ),
                        ),
                        if (!unlocked)
                          Icon(Icons.lock_outline, size: 14, color: c.ink3),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      listing.titleOrText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppText.labelLarge,
                        color: c.ink2,
                        height: 1.25,
                      ),
                    ),
                    if (listing.specsLabel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        listing.specsLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppText.labelTiny,
                          color: c.ink3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Эълон қўшиш» — матнсиз, доира ичида, сарлавҳа қаторининг ўнг
/// бурчагида (эга қарори, 2026-09-28). Икки экранда ҳам бир хил
/// бўлиши учун алоҳида виджет.
class RealtyAddButton extends StatelessWidget {
  const RealtyAddButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.only(right: 8, left: 4),
      child: Tooltip(
        message: context.tr('realty_add_cta'),
        child: Material(
          color: c.brandInk,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.add_home_outlined, size: 20, color: c.brand),
            ),
          ),
        ),
      ),
    );
  }
}

/// Сотиш / Ижара филтри — лента ва харита экранларида бир хил.
class RealtyDealFilter extends StatelessWidget {
  const RealtyDealFilter({
    super.key,
    required this.deal,
    required this.onChanged,
  });

  final RealtyDeal? deal;
  final ValueChanged<RealtyDeal?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    Widget chip(String labelKey, RealtyDeal? value) {
      final selected = deal == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(context.tr(labelKey)),
          selected: selected,
          onSelected: (_) => onChanged(value),
          labelStyle: TextStyle(
            fontSize: AppText.bodySmall,
            fontWeight: FontWeight.w600,
            color: selected ? c.brandInk : c.ink2,
          ),
          selectedColor: c.brand,
          backgroundColor: c.chip,
          side: BorderSide(color: c.line),
          showCheckmark: false,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      color: c.bg,
      child: Row(
        children: [
          chip('realty_deal_all', null),
          chip('realty_deal_sale', RealtyDeal.sale),
          chip('realty_deal_rent', RealtyDeal.rent),
        ],
      ),
    );
  }
}

/// Харита легендаси — ранг маъноси ва «нуқталар тахминий» огоҳлантириши.
class RealtyMapLegend extends StatelessWidget {
  const RealtyMapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      // `Wrap` — аввал бу `Row` эди ва ичида `Spacer` билан бирга
      // `Expanded` турар эди: тор экранда доимий оверфлоу хавфи бор
      // қурилиш. Энди элементлар керак бўлса кейинги қаторга ўтади.
      child: Wrap(
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final tier in RealtyTabs.order)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: RealtyTabs.colorFor(tier),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  context.tr(RealtyTabs.labelKey(tier)),
                  style: TextStyle(
                    fontSize: AppText.labelTiny,
                    color: c.ink2,
                  ),
                ),
              ],
            ),
          Text(
            context.tr('realty_map_approx_hint'),
            style: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
          ),
        ],
      ),
    );
  }
}

/// Очилмаган пин босилганда чиқадиган варақ: нуқта тахминий экани ва
/// аниқ манзилни очиш таклифи.
class _ApproxPinSheet extends StatelessWidget {
  const _ApproxPinSheet({required this.listing});

  final RealtyListing listing;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5, right: 8),
                  decoration: BoxDecoration(
                    color: RealtyTabs.colorFor(listing.tier),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    listing.titleOrText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: AppText.bodyLarge,
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 18, color: c.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('realty_map_locked_body'),
                    style: TextStyle(
                      fontSize: AppText.labelLarge,
                      color: c.ink2,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop('package'),
              icon: const Icon(Icons.lock_open_outlined, size: 18),
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              label: Text(context.tr('realty_map_locked_cta')),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop('detail'),
              child: Text(context.tr('realty_map_locked_open_card')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Пакетда қолган объект сони — сарлавҳа қаторида.
/// Пакети йўқ фойдаланувчида умуман кўринмайди.
class _UnlocksLeftChip extends StatelessWidget {
  const _UnlocksLeftChip({required this.stream});

  final Stream<int> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snap) {
        final left = snap.data ?? 0;
        if (left <= 0) return const SizedBox.shrink();
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_open_outlined,
                    size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  '$left',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: AppText.labelLarge,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
