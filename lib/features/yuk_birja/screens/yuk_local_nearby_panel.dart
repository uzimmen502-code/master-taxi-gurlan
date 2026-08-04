import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../services/location_service.dart';
import '../../chat/screens/chat_screen.dart';
import '../models/yuk_local_driver.dart';
import '../repositories/yuk_local_drivers_repository.dart';
import '../yuk_accept_radius.dart';
import '../yuk_local_ranking.dart';
import '../yuk_vehicle_types.dart';
import 'yuk_local_driver_sheet.dart';

/// Туман ичида юк қатнови — яқиндаги машиналар.
class YukLocalNearbyPanel extends StatefulWidget {
  const YukLocalNearbyPanel({
    super.key,
    required this.ownerId,
    required this.ownerName,
    required this.ownerPhone,
  });

  final String ownerId;
  final String ownerName;
  final String ownerPhone;

  @override
  State<YukLocalNearbyPanel> createState() => YukLocalNearbyPanelState();
}

class YukLocalNearbyPanelState extends State<YukLocalNearbyPanel> {
  static const _muted = Color(0xFF94A3B8);
  static const _accent = Color(0xFFFACC15);
  static const _green = Color(0xFF22C55E);

  final _repo = YukLocalDriversRepository();
  final _ranker = YukLocalRanking();

  StreamSubscription<List<YukLocalDriver>>? _sub;
  List<YukLocalDriver> _raw = [];
  List<YukLocalDriverRanked> _ranked = [];
  YukLocalDriver? _mine;
  double? _userLat;
  double? _userLng;
  bool _loadingGps = true;
  bool _loadingList = true;
  String? _error;
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([ensureGps(), _loadMine()]);
    _sub = _repo.watchOnline().listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _raw = list;
          _loadingList = false;
          _error = null;
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

  Future<void> _loadMine() async {
    if (widget.ownerId.isEmpty) return;
    try {
      final mine = await _repo.getMine(widget.ownerId);
      if (!mounted) return;
      setState(() => _mine = mine);
      if (mine?.online == true) {
        _startHeartbeat();
      }
    } catch (_) {}
  }

  /// «Туман ичида» таб: GPS рухсати + хизматни ёқиш + жойлашувни янгилаш.
  Future<void> ensureGps() async {
    if (!mounted) return;
    setState(() => _loadingGps = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        await Geolocator.openLocationSettings();
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        perm = await Geolocator.checkPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          _loadingGps = false;
          _error = 'yuk_local_need_gps';
        });
        return;
      }
      final coords = await const LocationService().getCurrentCoords();
      if (!mounted) return;
      setState(() {
        _userLat = coords.lat;
        _userLng = coords.lng;
        _loadingGps = false;
        if (_error == 'yuk_local_need_gps') _error = null;
        _recompute();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingGps = false;
        _error ??= 'yuk_local_need_gps';
      });
    }
  }

  void _recompute() {
    final lat = _userLat;
    final lng = _userLng;
    if (lat == null || lng == null) {
      _ranked = [];
      return;
    }
    _ranked = _ranker.rank(drivers: _raw, userLat: lat, userLng: lng);
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 45), (_) async {
      if (widget.ownerId.isEmpty || _mine?.online != true) return;
      try {
        final coords =
            await const LocationService().getCurrentCoords();
        await _repo.heartbeat(
          ownerId: widget.ownerId,
          lat: coords.lat,
          lng: coords.lng,
        );
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _heartbeat?.cancel();
    super.dispose();
  }

  Future<void> _openPublish() async {
    if (widget.ownerId.isEmpty) {
      _snack(context.tr('yuk_need_phone'));
      return;
    }
    final ok = await showYukLocalDriverSheet(
      context: context,
      ownerId: widget.ownerId,
      ownerName: widget.ownerName,
      ownerPhone: widget.ownerPhone,
      initial: _mine,
    );
    if (ok == true) {
      await _loadMine();
      await ensureGps();
      if (_mine?.online == true) {
        _startHeartbeat();
      } else {
        _heartbeat?.cancel();
      }
    }
  }

  Future<void> _goOffline() async {
    if (widget.ownerId.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131A22),
        title: Text(
          context.tr('yuk_close_title'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          context.tr('yuk_local_offline_confirm'),
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
              context.tr('yuk_local_go_offline'),
              style: const TextStyle(color: Color(0xFFFACC15)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.setOffline(widget.ownerId);
      _heartbeat?.cancel();
      if (!mounted) return;
      await _loadMine();
      if (!mounted) return;
      _snack(context.tr('yuk_local_offline_ok'));
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

  void _chat(YukLocalDriver d) {
    if (_isMine(d)) {
      _snack(context.tr('yuk_local_own_card'));
      return;
    }
    final phone = d.phone.isNotEmpty ? d.phone : d.ownerId;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(targetPhone: phone)),
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

  String _onlineAgo(DateTime? t) {
    if (t == null) return '—';
    final m = DateTime.now().difference(t).inMinutes;
    if (m <= 0) return context.tr('yuk_local_online_now');
    if (m < 60) {
      return context.tr('yuk_local_online_min').replaceAll('{n}', '$m');
    }
    final h = m ~/ 60;
    return context.tr('yuk_local_online_hour').replaceAll('{n}', '$h');
  }

  String _stars(double rating) {
    final full = rating.round().clamp(0, 5);
    return '${'★' * full}${'☆' * (5 - full)} ${rating.toStringAsFixed(1)}';
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

  @override
  Widget build(BuildContext context) {
    final loading = _loadingList || _loadingGps;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: _ActionBtn(
              color: const Color(0xFF1E2A1E),
              border: _green,
              label: context.tr('yuk_local_publish_btn'),
              onTap: _openPublish,
            ),
          ),
        ),
        if (_mine?.online == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.tr('yuk_local_you_online'),
                style: const TextStyle(color: _green, fontSize: 12),
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _error == 'yuk_local_need_gps' || _error == 'yuk_load_error'
                  ? context.tr(_error!)
                  : _error!,
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _userLat == null
                  ? context.tr('yuk_local_waiting_gps')
                  : '${_ranked.length} ${context.tr('yuk_local_nearby_count')}',
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(color: _accent),
                )
              : _ranked.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          context.tr('yuk_local_empty'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _muted),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: _ranked.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final row = _ranked[i];
                        return _LocalTruckCard(
                          row: row,
                          mine: _isMine(row.driver),
                          km: _km,
                          stars: _stars(row.driver.rating),
                          body: _body(row.driver),
                          radius: _radiusLabel(row.driver.acceptRadiusKm),
                          onlineAgo: _onlineAgo(row.driver.lastOnlineAt),
                          onCall: () => _call(row.driver),
                          onChat: () => _chat(row.driver),
                          onEdit: _openPublish,
                          onOffline: _goOffline,
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
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
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border.withValues(alpha: 0.85)),
            color: color,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalTruckCard extends StatelessWidget {
  const _LocalTruckCard({
    required this.row,
    required this.mine,
    required this.km,
    required this.stars,
    required this.body,
    required this.radius,
    required this.onlineAgo,
    required this.onCall,
    required this.onChat,
    required this.onEdit,
    required this.onOffline,
  });

  final YukLocalDriverRanked row;
  final bool mine;
  final String Function(double) km;
  final String stars;
  final String body;
  final String radius;
  final String onlineAgo;
  final VoidCallback onCall;
  final VoidCallback onChat;
  final VoidCallback onEdit;
  final VoidCallback onOffline;

  static const _card = Color(0xFF131A22);
  static const _border = Color(0xFF252B36);
  static const _muted = Color(0xFF94A3B8);
  static const _accent = Color(0xFFFACC15);
  static const _blue = Color(0xFF3B82F6);
  static const _green = Color(0xFF22C55E);

  @override
  Widget build(BuildContext context) {
    final d = row.driver;
    final vehicle = context.tr(yukVehicleLabelKey(d.vehicleType));
    final title = d.plateNumber.isEmpty
        ? vehicle
        : '$vehicle · ${d.plateNumber}';
    final loads = context
        .tr('yuk_local_loads_count')
        .replaceAll('{n}', '${d.completedLoads}');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: row.inRadius
              ? _border
              : const Color(0xFF3F3F1D),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              if (mine)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    context.tr('yuk_mine'),
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$stars  ·  $loads',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _line(
            context.tr('yuk_local_now'),
            d.locationLabel.isEmpty ? '—' : d.locationLabel,
          ),
          _line(
            context.tr('yuk_local_to_you'),
            '🛣 ${km(row.roadKm)} км  (📏 ${km(row.straightKm)} км)',
          ),
          _line(
            context.tr('yuk_local_eta'),
            context
                .tr('yuk_local_eta_min')
                .replaceAll('{n}', '${row.etaMinutes}'),
          ),
          _line(
            context.tr('yuk_capacity'),
            d.capacityTons > 0
                ? '${d.capacityTons == d.capacityTons.roundToDouble() ? d.capacityTons.round() : d.capacityTons.toStringAsFixed(1)} ${context.tr('yuk_ton_short').trim()}'
                : '—',
          ),
          _line(context.tr('yuk_local_body'), body),
          _line(context.tr('yuk_local_radius_title'), radius),
          _line(context.tr('yuk_local_online'), onlineAgo),
          if (!row.inRadius) ...[
            const SizedBox(height: 4),
            Text(
              context.tr('yuk_local_out_of_radius'),
              style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11),
            ),
          ],
          const SizedBox(height: 10),
          if (mine)
            Row(
              children: [
                Expanded(
                  child: _MiniBtn(
                    label: context.tr('yuk_edit'),
                    fg: Colors.white,
                    border: _accent,
                    fill: const Color(0xFF3F3F1D),
                    onTap: onEdit,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniBtn(
                    label: context.tr('yuk_local_go_offline'),
                    fg: Colors.white,
                    border: const Color(0xFFEF4444),
                    fill: const Color(0xFF3F1D1D),
                    onTap: onOffline,
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                Expanded(
                  child: _MiniBtn(
                    label: context.tr('yuk_call'),
                    fg: Colors.white,
                    border: _green,
                    fill: const Color(0xFF14532D),
                    onTap: onCall,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniBtn(
                    label: context.tr('yuk_local_chat'),
                    fg: Colors.white,
                    border: _blue,
                    fill: const Color(0xFF1E3A5F),
                    onTap: onChat,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _line(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$k: ',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            TextSpan(
              text: v,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
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
