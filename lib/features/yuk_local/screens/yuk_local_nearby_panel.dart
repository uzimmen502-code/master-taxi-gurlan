import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_tier_bar.dart';
import '../../../core/geo/module_geo_policy.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/catalog_search.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../services/geo_math_service.dart';
import '../../../services/location_service.dart';
import '../models/yuk_local_driver.dart';
import '../repositories/yuk_local_drivers_repository.dart';
import '../yuk_accept_radius.dart';
import '../yuk_local_ranking.dart';
import '../yuk_local_schedule.dart';
import '../../yuk_shared/yuk_vehicle_types.dart';
import 'yuk_local_driver_sheet.dart';
import '../../../core/theme/ava_tokens.dart';

/// Туман ичида юк қатнови — жойлашув + иш вақти (онлайн йўқ).
class YukLocalNearbyPanel extends StatefulWidget {
  const YukLocalNearbyPanel({
    super.key,
    required this.ownerId,
    required this.ownerName,
    required this.ownerPhone,
    this.openPublishOnStart = false,
  });

  /// «＋» → «Юк ташувчи»: экран очилиши билан эълон варағи (эга, 2026-10-19 —
  /// экрандаги алоҳида «Эълон бериш» тугмаси олиб ташланди, функцияси «＋» га кўчган).
  /// Доим янги эълон (бир нечта эълон рухсат); GPS рухсат диалогидан кейин очилади.
  final bool openPublishOnStart;

  final String ownerId;
  final String ownerName;
  final String ownerPhone;

  @override
  State<YukLocalNearbyPanel> createState() => YukLocalNearbyPanelState();
}

class YukLocalNearbyPanelState extends State<YukLocalNearbyPanel>
    with WidgetsBindingObserver {
  static const _muted = Color(0xFF94A3B8);
  static const _accent = Color(0xFFFACC15);
  static const _green = AvaLight.ok;

  final _repo = YukLocalDriversRepository();
  final _ranker = YukLocalRanking();
  final _searchCtrl = TextEditingController();

  StreamSubscription<List<YukLocalDriver>>? _sub;
  StreamSubscription<List<YukLocalDriver>>? _mineSub;
  List<YukLocalDriver> _raw = [];
  List<YukLocalDriverRanked> _ranked = [];

  /// Ўз эълонлари — бир рақам остида бир нечта.
  List<YukLocalDriver> _mine = const [];

  /// Биринчи GPS рухсат сўрови тугади (рухсат берилди/рад этилди/хато) —
  /// «＋» варағи тизим диалоги устига очилмаслиги учун.
  final _gpsPromptDone = Completer<void>();
  double? _userLat;
  double? _userLng;
  bool _loadingGps = true;
  bool _loadingList = true;
  String? _error;
  String _query = '';

  static const _geoModule = 'yuk_local';

  /// D-GEO-6: аввал туман, вилоят — тугма билан (танлов сақланади).
  GeoScope _scope = GeoContext.scopeFor(_geoModule);

  /// Очиқ каталог сўровининг калити — фақат доира ўзгарса қайта уланади.
  String _catalogKey = '';

  /// GPS бор — масофа/ETA бўйича саралаш; йўқ бўлса танланган ҳудуд
  /// эълонлари масофасиз (3а-босқич; аввал рўйхат умуман ёпиқ эди).
  bool get _hasSearcherGps => _userLat != null && _userLng != null;

  /// Сервер сўрови доираси. Туман даражасида GPS бўлса — вилоят туманлари:
  /// қўшни туман ҳайдовчиси радиуси етса кўринади
  /// ([YukLocalRanking.keepForDistrict]). GPS йўқ — фақат туман.
  GeoScope get _queryScope {
    if (_scope.level == GeoLevel.district &&
        _hasSearcherGps &&
        _scope.area.regionId.trim().isNotEmpty) {
      return _scope.copyWith(level: GeoLevel.region);
    }
    return _scope;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && _isGpsError(_error)) {
      ensureGps();
    }
  }

  Future<void> _bootstrap() async {
    // GPS рухсати диалоги рўйхат юкланишини блокламаслиги керак.
    unawaited(ensureGps());
    _subscribeCatalog();
    if (widget.ownerId.isNotEmpty) {
      _mineSub = _repo.watchMine(widget.ownerId).listen(
        (list) {
          if (!mounted) return;
          setState(() {
            _mine = list;
            _recompute();
          });
        },
        // Ўз эълонлари ўқилмаса ҳам оқим «unhandled» хато бермасин (рўйхат бўш қолади).
        onError: (Object e, StackTrace st) {
          debugPrint('[YukLocal] mine: $e');
        },
      );
    } else {
      _loadingList = false;
    }
    if (widget.openPublishOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_openPublish());
      });
    }
  }

  void _markGpsPromptDone() {
    if (!_gpsPromptDone.isCompleted) _gpsPromptDone.complete();
  }

  /// Каталог оқими — [_queryScope] ўзгарганда (даража тугмаси ёки GPS
  /// пайдо бўлди/йўқолди) қайта уланади. Эски рўйхат янгиси келгунча
  /// қолади — экран «милтилламайди».
  void _subscribeCatalog() {
    final q = _queryScope;
    if (_sub != null && q.key == _catalogKey) return;
    _catalogKey = q.key;
    _sub?.cancel();
    _sub = _repo.watchScoped(q).listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _raw = list;
          _loadingList = false;
          if (_error == 'yuk_load_error') _error = null;
          _recompute();
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _loadingList = false;
          _error = 'yuk_load_error';
        });
      },
    );
  }

  void _setScope(GeoScope s) {
    setState(() {
      _scope = s;
      _recompute();
    });
    _subscribeCatalog();
  }

  bool _isGpsError(String? key) =>
      _isGpsHardError(key) || key == 'yuk_local_gps_timeout';

  bool _isGpsHardError(String? key) =>
      key == 'yuk_local_need_gps' ||
      key == 'yuk_local_gps_settings' ||
      key == 'yuk_local_gps_disabled';

  /// Қидирувчи GPS — масофа бўйича саралаш учун. Йўқ бўлса рўйхат
  /// танланган ҳудуд бўйича масофасиз қолади.
  Future<void> ensureGps() async {
    if (!mounted) return;
    setState(() => _loadingGps = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        setState(() {
          _loadingGps = false;
          _userLat = null;
          _userLng = null;
          _error = 'yuk_local_gps_disabled';
          _recompute();
        });
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      // Рухсат диалоги ёпилди — координатани кутмасдан «＋» варағига йўл.
      _markGpsPromptDone();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _loadingGps = false;
          _userLat = null;
          _userLng = null;
          _error = perm == LocationPermission.deniedForever
              ? 'yuk_local_gps_settings'
              : 'yuk_local_need_gps';
          _recompute();
        });
        return;
      }
      final coords = await const LocationService().getCurrentCoords();
      if (!mounted) return;
      setState(() {
        _userLat = coords.lat;
        _userLng = coords.lng;
        _loadingGps = false;
        if (_isGpsError(_error)) {
          _error = null;
        }
        _recompute();
      });
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingGps = false;
        _userLat = null;
        _userLng = null;
        _error = switch (e.kind) {
          LocationErrorKind.permissionDenied => 'yuk_local_gps_settings',
          LocationErrorKind.serviceDisabled => 'yuk_local_gps_disabled',
          LocationErrorKind.timeout => 'yuk_local_gps_timeout',
          LocationErrorKind.lookupFailed => 'yuk_local_gps_timeout',
        };
        _recompute();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingGps = false;
        _userLat = null;
        _userLng = null;
        _error = 'yuk_local_gps_timeout';
        _recompute();
      });
    } finally {
      // Хизмат ўчиқ / хато — диалог бўлмади, варақ кутиб қолмасин.
      _markGpsPromptDone();
      // GPS пайдо бўлди/йўқолди — сўров доираси ўзгариши мумкин.
      if (mounted) _subscribeCatalog();
    }
  }

  Future<void> _enableGpsCta() async {
    final key = _error;
    if (key == 'yuk_local_gps_disabled') {
      await Geolocator.openLocationSettings();
    } else if (key == 'yuk_local_gps_settings') {
      await Geolocator.openAppSettings();
    }
    if (!mounted) return;
    await ensureGps();
  }

  void _recompute() {
    final lat = _userLat;
    final lng = _userLng;

    // GPS бор — масофа бўйича; йўқ — танланган ҳудуд эълонлари масофасиз.
    final all = lat != null && lng != null
        ? _ranker.rank(drivers: _raw, userLat: lat, userLng: lng)
        : _ranker.listWithoutGps(drivers: _raw);
    // Туман даражаси: шу туман + радиуси етадиган қўшни туман ҳайдовчиси.
    final others = _scope.level == GeoLevel.district
        ? YukLocalRanking.keepForDistrict(all, _scope.area.districtId)
        : all;

    if (_mine.isEmpty) {
      _ranked = others;
      return;
    }

    final withoutMine = others
        .where((r) => !phonesMatch(r.driver.ownerId, widget.ownerId))
        .toList();

    final activeMine = _mine.where((d) => !d.isExpired()).toList();
    _ranked = [
      for (final mine in activeMine) _rankMine(mine, lat, lng),
      ...withoutMine,
    ];
  }

  YukLocalDriverRanked _rankMine(
    YukLocalDriver mine,
    double? lat,
    double? lng,
  ) {
    double straight = 0;
    double road = 0;
    var eta = 0;
    var inRadius = true;
    final known = lat != null && lng != null && mine.hasGps;
    if (known) {
      straight =
          const GeoMathService().haversineKm(lat, lng, mine.lat!, mine.lng!);
      road = straight * YukLocalRanking.roadFactor;
      eta = (road / YukLocalRanking.avgSpeedKmh * 60).ceil().clamp(1, 999);
      inRadius = mine.coversDistance(straight);
    }
    return YukLocalDriverRanked(
      driver: mine,
      straightKm: straight,
      roadKm: road,
      etaMinutes: eta,
      inRadius: inRadius,
      distanceKnown: known,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _mineSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Фақат шу табдаги (Туман ичида) эълонлар ичидан.
  List<YukLocalDriverRanked> _filtered(BuildContext context) {
    final q = _query.trim();
    if (q.isEmpty) return _ranked;
    return _ranked
        .where((row) => _matchesLocalQuery(context, row.driver, q))
        .toList();
  }

  bool _matchesLocalQuery(
    BuildContext context,
    YukLocalDriver d,
    String query,
  ) {
    final vehicleLabel = context.tr(yukVehicleLabelKey(d.vehicleType));
    final fields = <String>[
      d.ownerName,
      d.phone,
      d.plateNumber,
      d.locationLabel,
      vehicleLabel,
      d.vehicleType,
      if (d.capacityKg > 0) '${d.capacityKg.round()}',
    ];
    if (CatalogSearch.matches(query, fields)) return true;
    // Табиий substring (рақам / қисқа сўз): CatalogSearch сўз/stem га қаттиқроқ.
    final hay = fields.join(' ').toLowerCase();
    final tokens =
        query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
    return tokens.every((t) => hay.contains(t));
  }

  /// «＋» → «Юк ташувчи»: ҲАР ДОИМ янги эълон (бир рақамда бир нечта эълон рухсат,
  /// янги эълон очишнинг ягона йўли — «＋»; мавжудлари рўйхатда таҳрирланади).
  /// GPS рухсат диалоги тугашини (вақт чегараси билан) кутади — тизим диалоги
  /// варақ устига тушмасин.
  Future<void> _openPublish() async {
    try {
      await _gpsPromptDone.future.timeout(_gpsPromptTimeout);
    } catch (_) {
      // Вақт тугади ёки хато — барибир варақ очилади (аввалги хатти-ҳаракат).
    }
    if (!mounted) return;
    await _openDriverSheet(null);
  }

  /// Фойдаланувчи GPS рухсат диалогида ўйлаб туриши мумкин.
  static const _gpsPromptTimeout = Duration(seconds: 30);

  /// Мавжуд эълонни таҳрирлаш (фақат шу эълон ўзгаради).
  Future<void> _editAd(YukLocalDriver driver) => _openDriverSheet(driver);

  Future<void> _openDriverSheet(YukLocalDriver? initial) async {
    if (widget.ownerId.isEmpty) {
      _snack(context.tr('yuk_need_phone'));
      return;
    }
    final ok = await showYukLocalDriverSheet(
      context: context,
      ownerId: widget.ownerId,
      ownerName: widget.ownerName,
      ownerPhone: widget.ownerPhone,
      initial: initial,
    );
    if (ok == true && mounted) {
      await ensureGps();
    }
  }

  Future<void> _deleteMine(YukLocalDriver mine) async {
    if (widget.ownerId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131A22),
        title: Text(
          context.tr('yuk_local_delete'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          context.tr('yuk_local_delete_confirm'),
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              context.tr('yuk_local_delete'),
              style: const TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteMine(mine.id);
      if (!mounted) return;
      _snack(context.tr('yuk_local_deleted_ok'));
    } catch (_) {
      if (!mounted) return;
      _snack(context.tr('yuk_local_publish_fail'));
    }
  }

  Future<void> _call(YukLocalDriver d) async {
    if (_isMine(d)) {
      _snack(context.tr('yuk_local_own_card'));
      return;
    }
    final ok = await callPhone(d.phone.isNotEmpty ? d.phone : d.ownerId);
    if (!ok && mounted) _snack(context.tr('yuk_call_fail'));
  }

  /// Картага босилганда — тўлиқ маълумот ва асосий амаллар.
  /// Рўйхат ихчам бўлиши учун кузов/қамров радиуси/тўғри масофа шу ерда.
  Future<void> _openDetails(YukLocalDriverRanked row) async {
    final d = row.driver;
    final mine = _isMine(d);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0B0E14),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        void run(VoidCallback action) {
          Navigator.of(sheetCtx).pop();
          action();
        }

        final vehicle = context.tr(yukVehicleLabelKey(d.vehicleType));
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  d.plateNumber.isEmpty ? vehicle : '$vehicle · ${d.plateNumber}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (d.ownerName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    d.ownerName,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                _detailRow(
                  context.tr('yuk_local_now'),
                  d.locationLabel.isEmpty ? '—' : d.locationLabel,
                ),
                if (row.distanceKnown) ...[
                  _detailRow(
                    context.tr('yuk_local_to_you'),
                    context
                        .tr('yuk_local_radius_km')
                        .replaceAll('{n}', _km(row.roadKm)),
                  ),
                  _detailRow(
                    context.tr('yuk_local_eta'),
                    context
                        .tr('yuk_local_eta_min')
                        .replaceAll('{n}', '${row.etaMinutes}'),
                  ),
                ],
                _detailRow(
                  context.tr('yuk_capacity'),
                  d.capacityKg > 0
                      ? '${formatPrice(d.capacityKg)}${context.tr('yuk_kg_short')}'
                      : '—',
                ),
                _detailRow(context.tr('yuk_local_body'), _body(d)),
                _detailRow(
                  context.tr('yuk_local_radius_title'),
                  _radiusLabel(d.acceptRadiusKm),
                ),
                _detailRow(
                  context.tr('yuk_local_work_hours'),
                  '${YukLocalSchedule.formatMinutes(d.workStartMinutes)}'
                  ' – ${YukLocalSchedule.formatMinutes(d.workEndMinutes)}',
                ),
                if (!d.isDemo && d.expiresAt != null)
                  _detailRow(
                    context.tr('yuk_local_expires'),
                    _expiresLabel(d.expiresAt!),
                  ),
                if (!row.inRadius)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 6),
                    child: Text(
                      context.tr('yuk_local_out_of_radius'),
                      style: const TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                if (!mine)
                  _MiniBtn(
                    label: context.tr('yuk_call'),
                    fg: Colors.black,
                    border: _green,
                    fill: _green,
                    onTap: () => run(() => _call(d)),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: _MiniBtn(
                          label: context.tr('yuk_edit'),
                          fg: Colors.white,
                          border: _accent,
                          fill: AvaLight.ink2,
                          onTap: () => run(() => _editAd(d)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MiniBtn(
                          label: context.tr('yuk_local_delete'),
                          fg: Colors.white,
                          border: const Color(0xFFEF4444),
                          fill: const Color(0xFF3F1D1D),
                          onTap: () => run(() => _deleteMine(d)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            // Узун ёзувлар («Грузоподъёмность») иккига бўлинмаслиги учун
            // ном қиймату қаторидан кўпроқ жой олади.
            flex: 3,
            child: Text(
              k,
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isMine(YukLocalDriver d) =>
      widget.ownerId.isNotEmpty &&
      phonesMatch(widget.ownerId, d.ownerId);

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _km(double v) {
    if (v < 10) return v.toStringAsFixed(1);
    return v.toStringAsFixed(0);
  }

  String _expiresLabel(DateTime exp) {
    final days = exp.difference(DateTime.now()).inDays;
    if (days <= 0) return context.tr('yuk_local_expires_soon');
    return context.tr('yuk_days_left').replaceAll('{n}', '$days');
  }

  /// Ихчам картадаги ЯККА факт қатори: «300 кг · 4.8 км · 11 дақ».
  /// Жой номи, кузов, қамров радиуси ва тўғри масофа — деталь варағида. Жой
  /// номи картага сиғмай кесилади («Гурлан марк…»), кесилган матн эса фойда
  /// бермайди; масофа ва ETA «қанча яқин» саволига аллақачон жавоб беради.
  ///
  /// GPS йўқ ([YukLocalDriverRanked.distanceKnown] = false) — масофа ўрнида
  /// жой номи (у ҳолда «қанча яқин»га бошқа жавоб йўқ).
  String _factsLine(YukLocalDriverRanked row) {
    final d = row.driver;
    return [
      if (d.capacityKg > 0)
        '${formatPrice(d.capacityKg)}${context.tr('yuk_kg_short')}',
      if (row.distanceKnown) ...[
        context.tr('yuk_local_radius_km').replaceAll('{n}', _km(row.roadKm)),
        context.tr('yuk_local_eta_short').replaceAll('{n}', '${row.etaMinutes}'),
      ] else if (d.locationLabel.trim().isNotEmpty)
        d.locationLabel.trim(),
    ].join(' · ');
  }

  String _body(YukLocalDriver d) {
    if (d.bodyLengthM <= 0 && d.bodyWidthM <= 0 && d.bodyHeightM <= 0) {
      return '—';
    }
    String f(double v) =>
        v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
    return '${f(d.bodyLengthM)} × ${f(d.bodyWidthM)} × ${f(d.bodyHeightM)} м';
  }

  String _radiusLabel(int km) {
    if (YukAcceptRadius.isCitywide(km)) {
      return context.tr('yuk_local_radius_city');
    }
    return context.tr('yuk_local_radius_km').replaceAll('{n}', '$km');
  }

  /// GPS йўқ — рўйхат ёпилмайди (3а), фақат «ёқсангиз яқинлари биринчи».
  Widget _gpsHintBlock(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          Text(
            context.tr('yuk_local_gps_hint'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.35, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _enableGpsCta,
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(context.tr('yuk_local_open_gps_settings')),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // GPS биринчи уриниши тугагунча кутамиз — рўйхат кейин қайта
    // сараланиб «сакрамасин».
    final loading = _loadingList || (_loadingGps && !_hasSearcherGps && _mine.isEmpty);
    final noGps = !_hasSearcherGps && !_loadingGps;
    final visible = _filtered(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: GeoTierBar(
            moduleId: _geoModule,
            scope: _scope,
            onChanged: _setScope,
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickySearchBar(
            child: _searchField(context),
          ),
        ),
        if (noGps) SliverToBoxAdapter(child: _gpsHintBlock(context)),
        SliverToBoxAdapter(child: _headerBlock(context, visible)),
        if (loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator(color: _accent)),
          )
        else if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _query.trim().isEmpty
                          ? context.tr('yuk_local_empty')
                          : context.tr('yuk_local_search_empty'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _muted),
                    ),
                    // Туманда йўқ — «Вилоят бўйича» таклифи (ўзи ўтмайди).
                    if (_query.trim().isEmpty)
                      GeoWiderHint(
                        moduleId: _geoModule,
                        scope: _scope,
                        onChanged: _setScope,
                      ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                childCount: visible.length,
                (_, i) {
                  final row = visible[i];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: i == visible.length - 1 ? 0 : 8,
                    ),
                    child: _LocalTruckCard(
                      row: row,
                      mine: _isMine(row.driver),
                      facts: _factsLine(row),
                      onCall: () => _call(row.driver),
                      onDetails: () => _openDetails(row),
                      onEdit: () => _editAd(row.driver),
                      onDelete: () => _deleteMine(row.driver),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  /// Қидирув майдони АТАЙЛАБ картадан бошқача: карта фони `_card`
  /// (0xFF131A22) ва 12px бурчак — майдон эса ундан ОЧРОҚ фон, ёрқин чегара
  /// ва тўлиқ юмалоқ шакл. Аввал иккиси бир хил эди, шу сабабли майдон «яна
  /// битта карта» бўлиб кўзга ташланмасди.
  Widget _searchField(BuildContext context) {
    return TextField(
      controller: _searchCtrl,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: _accent,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: context.tr('yuk_local_search_hint'),
        hintStyle: const TextStyle(color: Color(0xFF9FB0C4), fontSize: 13),
        prefixIcon: const Icon(
          Icons.search,
          color: Color(0xFFE2E8F0),
          size: 22,
        ),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: context.tr('yuk_local_search_clear'),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(
                  Icons.close,
                  color: Color(0xFFE2E8F0),
                  size: 20,
                ),
              ),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF1E2938),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: const BorderSide(color: Color(0xFF44566E)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: const BorderSide(color: Color(0xFF44566E)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(99),
          borderSide: const BorderSide(color: _accent, width: 2),
        ),
      ),
      onChanged: (v) => setState(() => _query = v),
    );
  }

  /// Саноқ / ўз эълонлари — қидирувдан пастда (GPS хатоси тўлиқ экранда).
  Widget _headerBlock(BuildContext context, List<YukLocalDriverRanked> visible) {
    return Column(
      children: [
        if (_mine.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context
                    .tr('yuk_local_my_ads_count')
                    .replaceAll('{n}', '${_mine.length}'),
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
          ),
        if (_error == 'yuk_load_error')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              context.tr('yuk_load_error'),
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              // GPS йўқ — «яқиндаги» дея олмаймиз (масофа номаълум).
              _query.trim().isEmpty && _hasSearcherGps
                  ? '${visible.length} ${context.tr('yuk_local_nearby_count')}'
                  : context
                      .tr('yuk_local_search_count')
                      .replaceAll('{n}', '${visible.length}'),
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

/// Қидирув қатори — рўйхат сурилганда тепада ёпишиб қолади.
/// Баландлик = майдон (~48) + вертикал паддинг (8+8). Фон экран фони билан
/// бир хил — остидан ўтаётган карталар «ёриб» кўринмаслиги учун.
class _StickySearchBar extends SliverPersistentHeaderDelegate {
  _StickySearchBar({required this.child});

  final Widget child;

  static const double _height = 64;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(
      color: const Color(0xFF0B0E14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: SizedBox(height: 56, child: child),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickySearchBar oldDelegate) =>
      child != oldDelegate.child;
}

/// Ихчам қатор: 2 матн қатори + ўнгда битта амал. Тўлиқ маълумот (кузов,
/// қамров радиуси, тўғри масофа) картага босилганда деталь варағида очилади.
class _LocalTruckCard extends StatelessWidget {
  const _LocalTruckCard({
    required this.row,
    required this.mine,
    required this.facts,
    required this.onCall,
    required this.onDetails,
    required this.onEdit,
    required this.onDelete,
  });

  final YukLocalDriverRanked row;
  final bool mine;

  /// «300 кг · 4.8 км · 11 дақ» — битта қаторда.
  final String facts;
  final VoidCallback onCall;
  final VoidCallback onDetails;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _card = Color(0xFF131A22);
  static const _border = Color(0xFF252B36);
  static const _muted = Color(0xFF94A3B8);
  static const _accent = Color(0xFFFACC15);
  static const _green = AvaLight.ok;
  static const _amber = Color(0xFFFBBF24);
  static const _demo = Color(0xFF93C5FD);

  /// Чап чизиқ: меники → намойиш → иш вақтида.
  Color get _stripeColor {
    if (mine) return _accent;
    if (row.driver.isDemo) return _demo;
    return row.driver.isWithinWorkHours() ? _green : _amber;
  }

  @override
  Widget build(BuildContext context) {
    final d = row.driver;
    final vehicle = context.tr(yukVehicleLabelKey(d.vehicleType));
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onDetails,
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: row.inRadius ? _border : AvaLight.ink2,
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: _stripeColor,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                vehicle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (d.plateNumber.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0B0E14),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: _border),
                                ),
                                child: Text(
                                  d.plateNumber,
                                  style: const TextStyle(
                                    color: Color(0xFFCBD5E1),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (mine || d.isDemo) ...[
                              _MiniPill(
                                text: mine
                                    ? context.tr('yuk_mine')
                                    : context.tr('yuk_demo_badge'),
                                fg: mine ? _accent : _demo,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                facts,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (mine)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: _muted),
                    color: _card,
                    onSelected: (value) {
                      if (value == 'edit') {
                        onEdit();
                      } else if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(
                          context.tr('yuk_edit'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          context.tr('yuk_local_delete'),
                          style: const TextStyle(color: Color(0xFFFCA5A5)),
                        ),
                      ),
                    ],
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message: context.tr('yuk_call'),
                      child: Material(
                        color: _green,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onCall,
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Icon(
                                Icons.phone,
                                color: AvaLight.ink,
                                size: 21,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.text, required this.fg});

  final String text;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({
    required this.label,
    required this.fg,
    required this.border,
    required this.fill,
    required this.onTap,
  });

  final String label;
  final Color fg;
  final Color border;
  final Color fill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border.withValues(alpha: 0.7)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
