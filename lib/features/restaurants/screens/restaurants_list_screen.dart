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
import '../domain/restaurant_sections.dart';
import '../widgets/restaurant_row.dart';
import '../widgets/section_dishes_view.dart';
import '../../../core/geo/geo_context.dart';
import '../domain/seasons.dart';
import 'my_bookings_screen.dart';
import 'restaurant_screen.dart';

class RestaurantsListScreen extends StatefulWidget {
  const RestaurantsListScreen({
    super.key,
    this.userLat,
    this.userLng,
    this.repository,
    this.cart,
    this.locate,
    this.currentUid,
    this.onOpenRestaurant,
  });

  /// Тестда алмаштириш учун; стандарт — [RestaurantScreen] очилади.
  final void Function(Restaurant restaurant)? onOpenRestaurant;

  /// Бўлим дарвозаси учун фойдаланувчи (12 рақамли; `internal` босқич синовчиси). Бўш бўлса
  /// SharedPreferences'даги телефондан; тестда алмаштирилади.
  final String? currentUid;

  /// Профил манзили (захира) — GPS рухсати бўлса GPS устун (D-GEO-4).
  final double? userLat;
  final double? userLng;
  final RestaurantsRepository? repository;
  final RestaurantCart? cart;

  /// Тестда алмаштириш учун; стандарт — GPS (рухсат сўралади).
  final Future<LocationCoords?> Function()? locate;

  /// Ном бўйича қидирув ҳовузи (бутун республика, D-GEO-4).
  static const searchPoolLimit = 300;

  @override
  State<RestaurantsListScreen> createState() => _RestaurantsListScreenState();
}

class _RestaurantsListScreenState extends State<RestaurantsListScreen> {
  late final RestaurantsRepository _repo =
      widget.repository ?? RestaurantsRepository();
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

  /// Бўлимлар (S3): созлама ҳужжати йўқ/ўчиқ бўлса чиплар умуман кўринмайди — экран аввалгидек.
  RestaurantSectionsConfig _sections = RestaurantSectionsConfig.off;
  String? _uid;
  RestaurantSection? _section;

  /// «Менинг бронларим» (S5): бронь ёқилган бўлса AppBar'да тугма.
  bool _bookingsOn = false;

  /// Мавсумий бўлим (S7): ҳозир очиқ мавсум бўлмаса чип умуман кўринмайди; Рамазон жадвали — ифтор/саҳарлик учун.
  List<ActiveSeason> _activeSeasons = const [];
  RamadanConfig _ramadan = RamadanConfig.none;

  /// «Овқатлар» лентаси ёқилганми (D-REST-40): экран очилганда яқин атрофдаги ТАОМЛАР чиқади (ресторанлар рўйхати эмас).
  bool get _dishesOn => _sections.isVisible(RestaurantSection.all, _uid);

  /// Фойдаланувчи чипни ўзи босдими — шундан кейин лента ўзи алмаштирмайди.
  bool _pickedByUser = false;

  /// Чиплар: «Барчаси» (`all`) ва «Ресторанлар» тартибга алоҳида киради; «Болалар» чипи олиб ташланган (эга, 2026-10-19).
  List<RestaurantSection> get _visible => [
        for (final s in _sections.visibleFor(_uid))
          if (s != RestaurantSection.all && s != RestaurantSection.kids && (s != RestaurantSection.seasonal || _activeSeasons.isNotEmpty)) s,
      ];

  /// Чиплар тартиби (эга, 2026-10-19): Барчаси · Уй таомлари (фақат уй ошпази) · Офис буюртма · Фаст-фуд · Миллий таомлар · Дунё таомлари ·
  /// Ресторанлар · Нонушта · Тунги · Дастурхон буюртма · Парҳезли таомлар (· Мавсумий). `null` — «Ресторанлар» чипи.
  static const _chipOrder = <RestaurantSection?>[
    RestaurantSection.all,
    RestaurantSection.home,
    RestaurantSection.office,
    RestaurantSection.fast,
    RestaurantSection.national,
    RestaurantSection.world,
    null,
    RestaurantSection.breakfast,
    RestaurantSection.night,
    RestaurantSection.dastarxon,
    RestaurantSection.light,
    RestaurantSection.seasonal,
  ];

  /// Кўринадиган чиплар шу тартибда. «Барчаси» ўчиқ бўлса (лента ёқилмаган) — «Ресторанлар» биринчи (экран аввалгидек).
  List<RestaurantSection?> get _chips {
    final shown = <RestaurantSection?>[
      for (final s in _chipOrder)
        if (s == null || (s == RestaurantSection.all ? _dishesOn : _visible.contains(s))) s,
    ];
    if (!_dishesOn) {
      shown.remove(null);
      shown.insert(0, null);
    }
    return shown;
  }

  Widget _chip(BuildContext context, RestaurantSection? s) {
    if (s == null) {
      return ChoiceChip(
        key: const ValueKey('section-all'),
        avatar: const Icon(Icons.storefront_outlined, size: 16),
        label: Text(context.tr('restaurants_section_all')),
        selected: _section == null,
        onSelected: (_) => setState(() {
          _pickedByUser = true;
          _setSection(null);
        }),
      );
    }
    return ChoiceChip(
      key: ValueKey(s == RestaurantSection.all ? 'section-feed' : 'section-${s.key}'),
      avatar: Icon(sectionIcon(s), size: 16),
      label: Text(context.tr(s.l10nKey)),
      selected: _section == s,
      onSelected: (_) => setState(() {
        _pickedByUser = true;
        _setSection(s);
        // Бўлим таом бўйича; ресторан қидируви қолиб кетмасин.
        _searchCtrl.clear();
        _query = '';
      }),
    );
  }

  @override
  void initState() {
    super.initState();
    _lat = widget.userLat;
    _lng = widget.userLng;
    if (_lat == null || _lng == null) _loadProfileCoords();
    _loadGps();
    _loadSections();
  }

  Future<void> _loadSections() async {
    String? uid = widget.currentUid;
    if (uid == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final d = phoneDigits(prefs.getString('user_phone') ?? '');
        uid = d.length == 9 ? '998$d' : d;
      } catch (_) {}
    }
    final cfg = await _repo.getSectionsConfig();
    var bookingsOn = false;
    try {
      bookingsOn = (await _repo.getBookingsConfig()).visibleFor(uid);
    } catch (_) {}
    var seasons = const <ActiveSeason>[];
    var ramadan = RamadanConfig.none;
    if (cfg.isVisible(RestaurantSection.seasonal, uid)) {
      try {
        seasons = (await _repo.getSeasonsConfig()).activeAt(DateTime.now());
        if (seasons.any((s) => s.key == SeasonKey.ramadan)) ramadan = await _repo.getRamadanConfig();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _sections = cfg;
      _uid = uid;
      _bookingsOn = bookingsOn;
      _activeSeasons = seasons;
      _ramadan = ramadan;
      // Танланган бўлим созламада ёпилган бўлса (кеш янгиланди) — умумий рўйхатга қайтамиз.
      if (_section != null && !cfg.isVisible(_section!, uid)) _setSection(null);
      // «Овқатлар» ёқилган бўлса экран таомлар лентаси билан очилади (фойдаланувчи ўзи алмаштирмаган бўлса).
      if (cfg.isVisible(RestaurantSection.all, uid) && !_pickedByUser && _section == null) _setSection(RestaurantSection.all);
    });
  }

  /// Бўлимни алмаштириш. Ресторанлар оқими ҲАР САФАР қайта яратилади: бўлимга ўтилганда рўйхат
  /// дарахтдан чиқади, қайтганда эски (битта obuna'ли) оқимга қайта уланиб бўлмайди.
  void _setSection(RestaurantSection? s) {
    _section = s;
    _stream = null;
    _streamKey = '';
  }

  /// GPS биринчи (D-GEO-4). Рухсат сўралади (эга, 2026-10-11) — модул
  /// экрани очилганда; рад этилса профил манзили қолади. Бош саҳифа блоки
  /// эса диалог очмайди (илова очилишида сўров чиқмасин).
  Future<void> _loadGps() async {
    final locate = widget.locate ?? _askGps;
    final c = await locate();
    if (!mounted || c == null) return;
    setState(() {
      _lat = c.lat;
      _lng = c.lng;
      _fromGps = true;
    });
  }

  static Future<LocationCoords?> _askGps() async {
    try {
      return await const LocationService().getCurrentCoords();
    } catch (_) {
      return null; // рад / ўчиқ / вақт тугади — профил манзили
    }
  }

  /// Координата берилмаган бўлса — профил манзилидан.
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

  /// Бўлимдаги таом босилди: ресторан ҳужжати олинади ва ресторан экрани очилади.
  Future<void> _openById(String restaurantId) async {
    try {
      final r = await _repo.getRestaurant(restaurantId);
      if (!mounted) return;
      if (r != null) {
        _open(r);
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('restaurants_dish_open_failed'))));
  }

  void _open(Restaurant r) {
    final hook = widget.onOpenRestaurant;
    if (hook != null) {
      hook(r);
      return;
    }
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
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
        ),
        actions: [
          if (_bookingsOn && _uid != null)
            IconButton(
              key: const ValueKey('my-bookings'),
              tooltip: context.tr('restaurants_booking_my'),
              icon: const Icon(Icons.event_seat_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => MyBookingsScreen(uid: _uid!, repository: _repo),
              )),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() {
                  _query = v;
                  // Қидирув — ресторанлар бўйича: ёзила бошласа бўлимдан умумий рўйхатга қайтамиз.
                  if (v.trim().isNotEmpty && _section != null) {
                    _setSection(null);
                  }
                }),
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            if (_chips.length > 1)
              SizedBox(
                height: 44,
                child: ListView(
                  key: const ValueKey('section-chips'),
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  children: [
                    for (var i = 0; i < _chips.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      _chip(context, _chips[i]),
                    ],                  ],
                ),
              ),
            if (_section == null)
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
              child: _section != null
                  ? SectionDishesView(
                      key: ValueKey('section-view-${_section!.key}'),
                      section: _section!,
                      config: _sections,
                      repository: _repo,
                      lat: _lat,
                      lng: _lng,
                      onOpenRestaurant: _openById,
                      seasons: _activeSeasons,
                      ramadan: _ramadan,
                      regionId: GeoContext.active.regionId,
                      onShowNation: () => setState(() {
                        _pickedByUser = true;
                        _showAll = true;
                        _setSection(null);
                      }),
                    )
                  : StreamBuilder<List<Restaurant>>(
                      stream: _listStream(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting &&
                            !snap.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
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
                                if (_nearbyMode &&
                                    (snap.data ?? const []).isEmpty)
                                  Align(
                                    child: OutlinedButton.icon(
                                      key: const ValueKey('rest_list_show_all'),
                                      icon: const Icon(Icons.public, size: 16),
                                      label:
                                          Text(context.tr('geo_show_nation')),
                                      onPressed: () =>
                                          setState(() => _showAll = true),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
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
