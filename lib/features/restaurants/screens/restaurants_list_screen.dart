// «Барчаси» — ресторанлар рўйхати (§12.3): қидирув, тартиб (масофа /
// рейтинг), фильтр (очиқ, олиб кетиш). Карточкалар бош экрандагиси билан
// бир хил ([RestaurantRow]).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/location_service.dart';
import '../../home/widgets/ava_section.dart';
import '../data/restaurants_repository.dart';
import '../domain/restaurant_models.dart';
import '../widgets/restaurant_row.dart';
import 'restaurant_screen.dart';

class RestaurantsListScreen extends StatefulWidget {
  const RestaurantsListScreen({
    super.key,
    this.userLat,
    this.userLng,
    this.repository,
    this.cart,
    this.locate,
  });

  /// Профил манзили (захира) — GPS рухсати бўлса GPS устун (D-GEO-4).
  final double? userLat;
  final double? userLng;
  final RestaurantsRepository? repository;
  final RestaurantCart? cart;

  /// Тестда алмаштириш учун; стандарт — рухсат сўрамайдиган GPS.
  final Future<LocationCoords?> Function()? locate;

  /// Ном бўйича қидирув ҳовузи (бутун республика, D-GEO-4).
  static const searchPoolLimit = 300;

  @override
  State<RestaurantsListScreen> createState() => _RestaurantsListScreenState();
}

class _RestaurantsListScreenState extends State<RestaurantsListScreen> {
  late final RestaurantsRepository _repo = widget.repository ?? RestaurantsRepository();
  late final RestaurantCart _cart = widget.cart ?? RestaurantCart.instance;
  final _searchCtrl = TextEditingController();

  String _query = '';
  String _sort = 'distance';
  bool _openOnly = false;
  bool _pickupOnly = false;
  double? _lat;
  double? _lng;

  /// Координата GPS'дан олинган — профил манзили уни алмаштирмайди.
  bool _fromGps = false;

  /// Яқинда ресторан йўқ — фойдаланувчи «Бутун Ўзбекистон»ни танлади.
  bool _showAll = false;

  Stream<List<Restaurant>>? _stream;
  String _streamKey = '';

  @override
  void initState() {
    super.initState();
    _lat = widget.userLat;
    _lng = widget.userLng;
    if (_lat == null || _lng == null) _loadProfileCoords();
    _loadGps();
  }

  /// GPS биринчи (D-GEO-4): рухсат аллақачон бўлса — диалогсиз.
  Future<void> _loadGps() async {
    final locate = widget.locate ?? const LocationService().getCoordsIfAllowed;
    final c = await locate();
    if (!mounted || c == null) return;
    setState(() {
      _lat = c.lat;
      _lng = c.lng;
      _fromGps = true;
    });
  }

  /// Координата берилмаган бўлса — профил манзилидан (GPS сўралмайди).
  Future<void> _loadProfileCoords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = phoneDigits(prefs.getString('user_phone') ?? '');
      if (uid.length < 9 || !mounted) return;
      final user = await context.read<UserRepository>().getById(uid);
      final a = user?.address;
      if (!mounted || _fromGps || a == null || a.lat == null || a.lng == null) {
        return;
      }
      setState(() {
        _lat = a.lat;
        _lng = a.lng;
      });
    } catch (_) {}
  }

  /// Оқим state'да кешланади — қидирув ёзилганда янги listener очилмасин
  /// (аввал ҳар `setState`да `watchApproved` қайта уланарди).
  ///
  /// - Ном бўйича қидирув — бутун республика (D-GEO-4): тасдиқланганлар
  ///   ҳовузи, филтр клиентда.
  /// - Координата бор — яқиндагилар (сервер, [RestaurantsRepository.watchNearby]).
  /// - Координата йўқ ёки «Бутун Ўзбекистон» — аввалги умумий рўйхат.
  Stream<List<Restaurant>> _listStream() {
    final searching = _query.trim().isNotEmpty;
    final lat = _lat;
    final lng = _lng;
    final nearby = !searching && !_showAll && lat != null && lng != null;
    final key = searching
        ? 'search'
        : nearby
            ? 'near:${lat.toStringAsFixed(3)}:${lng.toStringAsFixed(3)}'
            : 'all';
    if (_stream != null && key == _streamKey) return _stream!;
    _streamKey = key;
    return _stream = searching
        ? _repo.watchApproved(limit: RestaurantsListScreen.searchPoolLimit)
        : nearby
            ? _repo.watchNearby(lat: lat, lng: lng)
            : _repo.watchApproved(limit: 100);
  }

  bool get _nearbyMode =>
      _query.trim().isEmpty && !_showAll && _lat != null && _lng != null;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Restaurant> _apply(List<Restaurant> list) {
    final q = _query.trim().toLowerCase();
    final now = DateTime.now();
    final out = list.where((r) {
      if (_openOnly && !r.isOpenAt(now)) return false;
      if (_pickupOnly && !r.delivery.pickup) return false;
      if (q.isEmpty) return true;
      return r.name.toLowerCase().contains(q) ||
          r.cuisineTags.any((t) => t.toLowerCase().contains(q)) ||
          r.description.toLowerCase().contains(q);
    }).toList();
    out.sort((a, b) {
      if (_sort == 'rating') {
        final c = b.ratingAvg.compareTo(a.ratingAvg);
        if (c != 0) return c;
      }
      final da = a.distanceKmFrom(_lat, _lng);
      final db = b.distanceKmFrom(_lat, _lng);
      if (da != null && db != null && da != db) return da.compareTo(db);
      if (da == null && db != null) return 1;
      if (da != null && db == null) return -1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  void _open(Restaurant r) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RestaurantScreen(
          restaurant: r,
          userLat: _lat,
          userLng: _lng,
          repository: _repo,
          cart: _cart,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(
          context.tr('home_module_restaurants'),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: context.tr('restaurants_search_hint'),
                  prefixIcon: Icon(Icons.search_rounded, color: c.ink3),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: c.surface,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AvaRadius.search),
                    borderSide: BorderSide(color: c.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AvaRadius.search),
                    borderSide: BorderSide(color: c.line),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  ChoiceChip(
                    label: Text(context.tr('restaurants_sort_distance')),
                    selected: _sort == 'distance',
                    onSelected: (_) => setState(() => _sort = 'distance'),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text(context.tr('restaurants_sort_rating')),
                    selected: _sort == 'rating',
                    onSelected: (_) => setState(() => _sort = 'rating'),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: Text(context.tr('restaurants_filter_open')),
                    selected: _openOnly,
                    onSelected: (v) => setState(() => _openOnly = v),
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    label: Text(context.tr('restaurants_filter_pickup')),
                    selected: _pickupOnly,
                    onSelected: (v) => setState(() => _pickupOnly = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Restaurant>>(
                stream: _listStream(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: AvaNoticeRow(
                        text: context.tr('home_section_error'),
                        icon: Icons.cloud_off_rounded,
                        color: c.warn,
                      ),
                    );
                  }
                  final list = _apply(snap.data ?? const []);
                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AvaNoticeRow(
                            text: context.tr(_nearbyMode
                                ? 'restaurants_empty_nearby'
                                : 'restaurants_empty_list'),
                            icon: Icons.restaurant_outlined,
                            color: c.ink3,
                          ),
                          // Яқинда йўқ — кенгроқ ҳудуд (ўзи ўтмайди).
                          if (_nearbyMode && (snap.data ?? const []).isEmpty)
                            Align(
                              child: OutlinedButton.icon(
                                key: const ValueKey('restaurants_show_all'),
                                icon: const Icon(Icons.public, size: 16),
                                label: Text(context.tr('geo_show_nation')),
                                onPressed: () => setState(() => _showAll = true),
                              ),
                            ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => RestaurantRow(
                      restaurant: list[i],
                      distanceKm: list[i].distanceKmFrom(_lat, _lng),
                      onTap: () => _open(list[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
