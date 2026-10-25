import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/catalog_search.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/map_launcher.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../ads/screens/cheap_products_screen.dart';
import '../../business_map/data/business_repository.dart';
import '../../business_map/domain/business.dart';
import '../domain/shop_directions.dart';
import '../models/tv_clip.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_clips_repository.dart';
import '../repositories/tv_public_profiles_repository.dart';
import '../repositories/tv_shop_repository.dart';
import '../utils/tv_highlight_order.dart';
import '../widgets/shop_complaint_sheet.dart';
import '../widgets/shop_unavailable_view.dart';
import '../widgets/tv_channel_contact_bar.dart';
import '../widgets/tv_channel_header.dart';
import '../widgets/tv_shop_item_grid_card.dart';
import 'tv_shop_item_detail_screen.dart';

/// Харидор учун ЯГОНА онлайн дўкон саҳифаси (эга қарори 2026-10-25): сотувчининг битта онлайн дўкони ва унинг
/// таркибидаги йўналиш дўконлари (`businesses`). Маҳсулот, видео ёки харитадан келинганда айнан ТЕГИШЛИ йўналиш
/// танланган ҳолда очилади ([businessId] ёки [highlightItemId] маҳсулотининг йўналиши); бошқа йўналишлар — шу
/// саҳифадаги тугмалар. Юзлаб маҳсулот: дўкон ичида қидирув, тур фильтри, саҳифалаб юклаш.
class TvShopPublicScreen extends StatefulWidget {
  const TvShopPublicScreen({
    super.key,
    required this.ownerPhone,
    this.businessId = '',
    this.highlightItemId = '',
    this.ownerDisplayName = '',
    this.districtLabel = '',
    this.districtId = '',
    TvShopRepository? shopRepository,
    BusinessRepository? businessRepository,
    this.loadChannelInfo = true,
    this.pageSize = 100,
  })  : _shopRepo = shopRepository,
        _bizRepo = businessRepository;

  final String ownerPhone;

  /// Аниқ йўналиш (харита нуқтаси, ҳавола). Бўш — маҳсулотдан аниқланади ёки «Барчаси».
  final String businessId;
  final String highlightItemId;
  final String ownerDisplayName;
  final String districtLabel;

  /// Туман номини тилга қараб кўрсатиш учун (бўш бўлиши мумкин).
  final String districtId;

  final TvShopRepository? _shopRepo;
  final BusinessRepository? _bizRepo;

  /// Канал маълумоти (профил номи/расми, кўришлар, обуначилар) — тестда ўчирилади.
  final bool loadChannelInfo;
  final int pageSize;

  @override
  State<TvShopPublicScreen> createState() => _TvShopPublicScreenState();
}

class _TvShopPublicScreenState extends State<TvShopPublicScreen> {
  late final TvShopRepository _shopRepo = widget._shopRepo ?? TvShopRepository();
  late final BusinessRepository _bizRepo = widget._bizRepo ?? BusinessRepository();
  final _search = TextEditingController();

  TvShop? _shop;
  ShopDirections? _directions;
  ShopSelection _selection = const ShopSelection.all();
  List<TvShopItem> _items = const [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = false;
  bool _loadingMore = false;
  String _query = '';
  String? _kind;

  String _displayName = '';
  String _district = '';
  String _districtId = '';
  String _photoUrl = '';
  int _totalViewCount = 0;
  int _clipCount = 0;
  String _viewerPhone = '';
  int _followerCount = 0;
  bool _isFollowing = false;
  bool _followBusy = false;
  bool _loading = true;

  /// Админ бутун онлайн дўконни блоклаган (`tv_shops.status`): ҳеч қандай маълумот кўрсатилмайди.
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _displayName = tvOwnerDisplayName(widget.ownerDisplayName);
    _district = widget.districtLabel.trim();
    _districtId = widget.districtId.trim();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<Business>?> _businesses() async {
    try {
      return await _bizRepo.fetchByOwner(canonicalPhoneId(widget.ownerPhone));
    } catch (e) {
      // Меҳмон (телефонсиз) `businesses`ни ўқий олмайди — йўналишсиз, барча маҳсулот билан очилади.
      debugPrint('[TvShopPublic] businesses: $e');
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final shop = await _shopRepo.fetchShop(widget.ownerPhone);
      if (shop?.isBlocked ?? false) {
        if (mounted) {
          setState(() {
            _blocked = true;
            _displayName = '';
            _loading = false;
          });
        }
        return;
      }
      final results = await Future.wait<Object?>([
        _shopRepo.fetchOwnerPage(widget.ownerPhone, limit: widget.pageSize),
        _businesses(),
      ]);
      final page = results[0] as ShopItemsPage;
      final businesses = results[1] as List<Business>?;
      final items = page.items;

      String? highlightBiz;
      if (widget.highlightItemId.isNotEmpty) {
        final hit = items.where((i) => i.id == widget.highlightItemId);
        if (hit.isNotEmpty) {
          highlightBiz = hit.first.businessId;
        } else {
          try {
            final it = await _shopRepo.fetchItem(widget.highlightItemId);
            if (it != null && canonicalPhoneId(it.ownerPhone) == canonicalPhoneId(widget.ownerPhone)) {
              highlightBiz = it.businessId;
            }
          } catch (e) {
            debugPrint('[TvShopPublic] highlight: $e');
          }
        }
      }

      final shopName = tvOwnerDisplayName(shop?.name ?? '');
      final directions = ShopDirections.build(
        ownerPhone: widget.ownerPhone,
        shopName: shopName.isNotEmpty ? shopName : _displayName,
        businesses: businesses ?? const [],
        hasOwnItems: items.any((i) => i.isActive && i.businessId.isEmpty) || highlightBiz == '',
        businessesKnown: businesses != null,
      );
      final selection = directions.initial(businessId: widget.businessId, highlightBusinessId: highlightBiz);

      if (!mounted) return;
      setState(() {
        _shop = shop;
        _directions = directions;
        _selection = selection;
        _items = items;
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loading = false;
        if (_district.isEmpty) {
          final first = items.where((i) => i.isActive);
          if (first.isNotEmpty) {
            _district = first.first.districtLabel.trim();
            _districtId = first.first.districtId.trim();
          }
        }
      });
      if (widget.loadChannelInfo) await _loadChannel(shop);
    } catch (e) {
      debugPrint('[TvShopPublic] $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Канал маълумоти (профил, кўришлар, обуначилар) — каталог кўрингандан кейин, хатоси каталогни бузмайди.
  Future<void> _loadChannel(TvShop? shop) async {
    try {
      final profiles = TvPublicProfilesRepository();
      final clipsRepo = TvClipsRepository();
      final id = canonicalPhoneId(widget.ownerPhone);
      var displayName = _displayName;
      if (displayName.isEmpty) {
        final names = await profiles.fetchMany([widget.ownerPhone]);
        final fromProfile = tvOwnerDisplayName(names[id] ?? '');
        final fromShop = tvOwnerDisplayName(shop?.name ?? '');
        displayName = fromProfile.isNotEmpty ? fromProfile : fromShop;
      }
      final photos = await profiles.fetchPhotos([widget.ownerPhone]);
      final totalViews = await profiles.fetchTotalViewCount(widget.ownerPhone);
      final List<TvClip> ownerClips = await clipsRepo.fetchByOwner(widget.ownerPhone);
      final followerCount = await profiles.fetchFollowerCount(widget.ownerPhone);
      final prefs = await SharedPreferences.getInstance();
      final viewerPhone = phoneDigits(prefs.getString('user_phone') ?? '');
      var isFollowing = false;
      if (viewerPhone.isNotEmpty) {
        isFollowing = await profiles.isFollowing(viewerId: viewerPhone, targetId: widget.ownerPhone);
      }
      if (!mounted) return;
      setState(() {
        _displayName = displayName;
        _photoUrl = photos[id] ?? '';
        _totalViewCount = totalViews;
        _clipCount = ownerClips.where((c) => c.isActive).length;
        _followerCount = followerCount;
        _viewerPhone = viewerPhone;
        _isFollowing = isFollowing;
      });
    } catch (e) {
      debugPrint('[TvShopPublic] channel: $e');
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _shopRepo.fetchOwnerPage(widget.ownerPhone, limit: widget.pageSize, after: _cursor);
      if (!mounted) return;
      final seen = {for (final i in _items) i.id};
      setState(() {
        _items = [..._items, for (final i in page.items) if (!seen.contains(i.id)) i];
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('[TvShopPublic] more: $e');
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('bizprod_err_generic'))));
    }
  }

  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    if (_viewerPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_channel_follow_need_auth'))),
      );
      return;
    }
    _followBusy = true;
    final was = _isFollowing;
    setState(() {
      _isFollowing = !was;
      _followerCount += was ? -1 : 1;
    });
    try {
      final following = await TvPublicProfilesRepository().toggleFollow(
        viewerId: _viewerPhone,
        targetId: widget.ownerPhone,
      );
      if (mounted) setState(() => _isFollowing = following);
    } catch (e) {
      debugPrint('[TvShopPublic] follow $e');
      if (mounted) {
        setState(() {
          _isFollowing = was;
          _followerCount += was ? 1 : -1;
        });
      }
    } finally {
      _followBusy = false;
    }
  }

  Business? get _selectedBusiness {
    final id = _selection.businessId;
    if (id == null || id.isEmpty) return null;
    return _directions?.byId(id)?.business;
  }

  /// Қўнғироқ: танланган йўналишнинг ўз телефони (харитадаги объект), бўлмаса — сотувчи.
  Future<void> _call() async {
    final bizPhone = _selectedBusiness?.phone ?? '';
    final ok = await callPhone(bizPhone.isNotEmpty ? bizPhone : widget.ownerPhone);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('tv_market_call_failed'))),
      );
    }
  }

  Future<void> _openItem(TvShopItem item) async {
    await Navigator.push(
      context,
      // Дўкон ичида: дўкон тугмаси керак эмас; ўхшашлар — шу дўконнинг юкланган каталогидан.
      MaterialPageRoute(builder: (_) => TvShopItemDetailScreen(item: item, similarPool: _items)),
    );
  }

  void _select(ShopSelection s) => setState(() {
        _selection = s;
        _kind = null;
      });

  String get _appBarTitle {
    final shopName = tvOwnerDisplayName(_shop?.name ?? '');
    if (shopName.isNotEmpty) return shopName;
    if (_displayName.isNotEmpty) return _displayName;
    return context.tr('tv_shop_mine');
  }

  List<TvShopItem> get _visible {
    final d = _directions;
    if (d == null) return const [];
    final inDirection = d.itemsFor(_selection, _items, ownerPhone: widget.ownerPhone);
    final filtered = ShopDirections.filter(inDirection, query: _query, kind: _kind);
    return CatalogSearch.normalize(_query).isNotEmpty
        ? filtered
        : tvOrderHighlightFirst(filtered, (i) => i.id == widget.highlightItemId);
  }

  /// Танланган йўналиш тугмаси — экрандан ташқарида бўлса кўринадиган жойга айлантирилади (маҳсулотдан кирилганда
  /// харидор қайси йўналишда эканини дарҳол кўрсин).
  final _selectedChipKey = GlobalKey();
  bool _chipScrolled = false;

  Widget _directionChips(ShopDirections d) {
    Widget chip(String key, String label, ShopSelection s) {
      final selected = _selection == s;
      return Padding(
        key: selected ? _selectedChipKey : null,
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          key: ValueKey('shop_dir_$key'),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          selected: selected,
          onSelected: (_) => _select(s),
        ),
      );
    }

    if (!_chipScrolled) {
      _chipScrolled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Фақат тугмалар қатори айланади (саҳифанинг ўзи тепада қолади).
        final ctx = _selectedChipKey.currentContext;
        final box = ctx?.findRenderObject();
        if (ctx != null && box != null) Scrollable.of(ctx).position.ensureVisible(box, alignment: 0.5);
      });
    }
    // Барча тугмалар қурилади (бир неча йўналиш), горизонтал айланади.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          chip('all', context.tr('shop_dir_all'), const ShopSelection.all()),
          for (final x in d.directions)
            chip(x.isOwn ? 'own' : x.businessId, x.name.isEmpty ? context.tr('tv_shop_mine') : x.name,
                ShopSelection.direction(x.businessId)),
        ],
      ),
    );
  }

  Widget _directionCard(Business b) {
    Widget line(IconData icon, String text, {VoidCallback? onTap}) {
      final row = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                    fontSize: 14,
                    color: onTap == null ? null : AppColors.primaryDark,
                    decoration: onTap == null ? null : TextDecoration.underline,
                  )),
            ),
          ],
        ),
      );
      return onTap == null ? row : InkWell(onTap: onTap, child: row);
    }

    return Card(
      key: const ValueKey('shop_dir_card'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(b.category.icon, size: 18, color: AppColors.primaryDark),
              const SizedBox(width: 6),
              Expanded(
                child: Text(context.tr(b.category.labelKey),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 4),
            Text(b.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (b.description.isNotEmpty) line(Icons.notes_rounded, b.description),
            if (b.address.isNotEmpty) line(Icons.place_outlined, b.address),
            if (b.openingHours.isNotEmpty) line(Icons.schedule_rounded, b.openingHours),
            if (b.phone.isNotEmpty) line(Icons.phone_outlined, b.phone, onTap: _call),
            if (b.online)
              line(Icons.language_rounded, context.tr('bizmap_online_badge'))
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('shop_dir_route'),
                  onPressed: () => openMapsNavigation(lat: b.lat, lng: b.lng, label: b.name),
                  icon: const Icon(Icons.directions_rounded, size: 18),
                  label: Text(context.tr('bizmap_route')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filters(List<TvShopItem> inDirection) {
    final kinds = {for (final i in inDirection) i.kind};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('shop_search'),
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: context.tr('shop_search_hint'),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: context.tr('cancel'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        if (kinds.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, children: [
              for (final k in const ['product', 'service'])
                FilterChip(
                  key: ValueKey('shop_kind_$k'),
                  label: Text(context.tr(k == 'service' ? 'bizprod_kind_service' : 'bizprod_kind_product')),
                  selected: _kind == k,
                  onSelected: (on) => setState(() => _kind = on ? k : null),
                ),
            ]),
          ),
        const SizedBox(height: 10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _directions;
    final business = _selectedBusiness;
    final inDirection = d == null ? const <TvShopItem>[] : d.itemsFor(_selection, _items, ownerPhone: widget.ownerPhone);
    final visible = _visible;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        leading: const BackButton(color: Colors.black87),
        title: Text(_blocked ? '' : _appBarTitle),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.black87),
        actionsIconTheme: const IconThemeData(color: Colors.black87),
        elevation: 0.4,
        actions: [
          if (!_loading && !_blocked)
            IconButton(
              key: const ValueKey('shop_report'),
              tooltip: context.tr('ad_report_title'),
              icon: const Icon(Icons.flag_outlined),
              onPressed: () => showShopComplaintSheet(context, targetType: 'shop', targetId: widget.ownerPhone),
            ),
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CheapProductsScreen()),
              );
            },
            icon: const Icon(Icons.storefront_outlined),
            label: Text(context.tr('tv_shop_to_market')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _blocked
              ? const ShopUnavailableView(textKey: 'shop_unavailable')
              : CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.loadChannelInfo)
                              TvChannelHeader(
                                displayName: _displayName,
                                districtLabel: _district,
                                districtId: _districtId,
                                clipCount: _clipCount > 0 ? _clipCount : null,
                                totalViewCount: _totalViewCount,
                                photoUrl: _photoUrl,
                                followerCount: _followerCount,
                                isFollowing: _isFollowing,
                                onToggleFollow: _toggleFollow,
                              ),
                            if (d != null && d.hasChoice) _directionChips(d),
                            if (business != null) _directionCard(business),
                            Text(
                              context.tr('tv_shop_vitrine'),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                            const SizedBox(height: 10),
                            if (inDirection.isNotEmpty || _query.isNotEmpty) _filters(inDirection),
                          ],
                        ),
                      ),
                    ),
                    if (visible.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  context.tr(CatalogSearch.normalize(_query).isNotEmpty ? 'shop_search_none' : 'tv_shop_empty'),
                                  key: const ValueKey('shop_empty'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                                ),
                                if (_hasMore) ...[
                                  const SizedBox(height: 12),
                                  _loadMoreButton(),
                                ],
                              ],
                            ),
                          ),
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.72,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              final item = visible[i];
                              return TvShopItemGridCard(
                                item: item,
                                highlight: item.id == widget.highlightItemId,
                                onTap: () => _openItem(item),
                              );
                            },
                            childCount: visible.length,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 96),
                          child: _hasMore ? Center(child: _loadMoreButton()) : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ],
                ),
      bottomNavigationBar: _blocked || _loading ? null : TvChannelContactBar(onCall: _call),
    );
  }

  Widget _loadMoreButton() => OutlinedButton.icon(
        key: const ValueKey('shop_load_more'),
        onPressed: _loadingMore ? null : _loadMore,
        icon: _loadingMore
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.expand_more_rounded),
        label: Text(context.tr('shop_load_more')),
      );
}
