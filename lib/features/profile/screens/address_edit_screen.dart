import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/widgets/service_area_picker.dart';
import '../../../models/user_address.dart';
import '../../../models/user_model.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/location_service.dart';
import '../../../core/theme/app_theme.dart';

/// Фойдаланувчи яшаш манзилини таҳрирлаш экрани.
///
/// Икки манба: **GPS** (танап олиш) ва **қўлда** (МФЙ/кўча/уй/туман/изоҳ).
/// Сақлашда — Firestore'га `address` Map сифатида ёзилади.
///
/// Бу экран курьер ва модулларга яшаш манзилини беради.
class AddressEditScreen extends StatefulWidget {
  const AddressEditScreen({super.key, this.initial});

  /// Олдиндан мавжуд манзил (агар бўлса).
  final UserAddress? initial;

  @override
  State<AddressEditScreen> createState() => _AddressEditScreenState();
}

class _AddressEditScreenState extends State<AddressEditScreen> {
  static const _green = AppColors.primaryDark;

  final _mfyCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _houseCtrl = TextEditingController();
  final _districtCtrl = TextEditingController(text: 'Гурлан');
  final _noteCtrl = TextEditingController();

  double? _lat;
  double? _lng;
  double? _accuracy;
  DateTime? _geoUpdatedAt;
  bool _gpsLoading = false;
  bool _saving = false;
  String? _err;

  String _regionId = '';
  String _districtId = '';
  String _serviceAreaId = '';

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    if (a != null) {
      _mfyCtrl.text = a.mfy;
      _streetCtrl.text = a.street;
      _houseCtrl.text = a.house;
      if (a.district.isNotEmpty) _districtCtrl.text = a.district;
      _noteCtrl.text = a.note;
      _lat = a.lat;
      _lng = a.lng;
      _accuracy = a.accuracy;
      _geoUpdatedAt = a.geoUpdatedAt;
      // Агар initial манзил бор-у, лекин manual бўш бўлса (faqat GPS qoldi yoki
      // legacy migrating), legacy strok prefill qilинасин.
      if (!a.hasManualAddress) {
        _hydrateFromLegacy();
      }
    } else {
      _hydrateFromLegacy();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_hydrateGeoFromUser());
    });
  }

  Future<void> _hydrateGeoFromUser() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = phoneDigits(prefs.getString('user_phone') ?? '');
    if (uid.length < 9 || !mounted) return;
    try {
      final user = await context.read<UserRepository>().getById(uid);
      if (user == null || !mounted) return;
      setState(() {
        if (_regionId.isEmpty && user.regionId.isNotEmpty) {
          _regionId = user.regionId;
        }
        if (_districtId.isEmpty && user.districtId.isNotEmpty) {
          _districtId = user.districtId;
        }
        if (_serviceAreaId.isEmpty && user.serviceAreaId.isNotEmpty) {
          _serviceAreaId = user.serviceAreaId;
        }
      });
    } catch (_) {}
  }

  Future<void> _hydrateFromLegacy() async {
    // Эски (string) манзилни prefill сифатида street'га қўямиз.
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString('user_address') ?? '';
    if (legacy.isNotEmpty && _streetCtrl.text.isEmpty && mounted) {
      // TextEditingController.text setter автоматик rebuild qiladi —
      // setState shart emas, лекин _err/header'ни қайта чизиш учун зарур.
      setState(() {
        _streetCtrl.text = legacy;
      });
    }
  }

  @override
  void dispose() {
    _mfyCtrl.dispose();
    _streetCtrl.dispose();
    _houseCtrl.dispose();
    _districtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _useGps() async {
    final svc = context.read<LocationService>();
    setState(() {
      _gpsLoading = true;
      _err = null;
    });
    try {
      final coords = await svc.getCurrentCoords();
      if (!mounted) return;
      setState(() {
        _lat = coords.lat;
        _lng = coords.lng;
        _accuracy = coords.accuracy;
        _geoUpdatedAt = DateTime.now();
        _gpsLoading = false;
      });
      final acc = coords.accuracy;
      final accText = acc != null ? ' (±${acc.toStringAsFixed(0)}m)' : '';
      final lowAcc = coords.isLowAccuracy;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: _green,
        content: Text(
          lowAcc
              ? '📍 GPS олинди (паст аниқлик ±${acc!.toStringAsFixed(0)} м). Очиқ жойда қайта урининг.'
              : '📍 GPS олинди: ${coords.lat.toStringAsFixed(5)}, ${coords.lng.toStringAsFixed(5)}$accText',
        ),
      ));
      if (_streetCtrl.text.trim().isEmpty) {
        unawaited(_fillStreetFromGeocode(svc, coords.lat, coords.lng));
      }
    } on LocationException catch (e) {
      if (mounted) {
        setState(() {
          _err = LocationException.userMessage(e.kind);
          _gpsLoading = false;
        });
      }
    }
  }

  Future<void> _fillStreetFromGeocode(
    LocationService svc,
    double lat,
    double lng,
  ) async {
    try {
      final geoAddr = await svc.addressFromCoords(
        lat,
        lng,
        timeout: const Duration(seconds: 5),
        fallbackToCoords: false,
      );
      if (!mounted) return;
      if (geoAddr != null &&
          geoAddr.trim().isNotEmpty &&
          _streetCtrl.text.trim().isEmpty) {
        setState(() => _streetCtrl.text = geoAddr.trim());
      }
    } catch (_) {
      // Geocoding ixtiyoriy.
    }
  }

  Future<void> _save() async {
    final mfy = _mfyCtrl.text.trim();
    final street = _streetCtrl.text.trim();
    final house = _houseCtrl.text.trim();
    if (mfy.isEmpty || street.isEmpty || house.isEmpty) {
      setState(() => _err =
          'МФЙ, кўча ва уй рақами — мажбурий майдонлар. Илтимос, тўлдиринг.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final uid = phoneDigits(prefs.getString('user_phone') ?? '');
    if (uid.length < 9) {
      setState(() => _err = 'Аввал телефонни тасдиқланг');
      return;
    }

    final address = UserAddress(
      mfy: mfy,
      street: street,
      house: house,
      district: _districtCtrl.text.trim().isEmpty
          ? 'Гурлан'
          : _districtCtrl.text.trim(),
      note: _noteCtrl.text.trim(),
      lat: _lat,
      lng: _lng,
      accuracy: _accuracy,
      geoUpdatedAt: _geoUpdatedAt,
      manualUpdatedAt: DateTime.now(),
    );
    final validation = address.validationError;
    if (validation != null) {
      setState(() => _err = validation);
      return;
    }

    if (!mounted) return;
    final userRepo = context.read<UserRepository>();
    setState(() => _saving = true);
    try {
      await userRepo.saveAddress(
            uid: uid,
            address: address,
            legacyFromString: prefs.getString('user_address'),
          );
      // Каш — SharedPreferences ҳам янгилaнади.
      await prefs.setString('user_address', address.formatted);

      // Xizmat zonasi tanlangan bo'lsa — saqlash + config override yangilash.
      // Ixtiyoriy: tanlanmagan bo'lsa manzil baribir saqlanadi.
      if (_serviceAreaId.isNotEmpty) {
        try {
          await userRepo.saveServiceArea(
                uid: uid,
                regionId: _regionId,
                districtId: _districtId,
                serviceAreaId: _serviceAreaId,
              );
        } catch (_) {
          // Zona saqlanmasa ham manzil saqlangan — bloklamaymiz.
        }
      }
      if (_regionId.isNotEmpty ||
          _districtId.isNotEmpty ||
          _serviceAreaId.isNotEmpty) {
        try {
          await ServiceConfigHolder.applyGeo(
                regionId: _regionId,
                districtId: _districtId,
                serviceAreaId: _serviceAreaId,
              );
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.pop(context, address);
    } catch (e) {
      setState(() => _err = 'Сақлашда хатолик: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: const Text('Яшаш манзили'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Изоҳ — иккаласи ҳам мажбурий.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.tickerShell,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, color: AppColors.primary),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Икки манба мажбурий:',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '📍  GPS — карта ва ҳайдовчи учун аниқ нуқта\n✍️  Қўлда (МФЙ, кўча, уй, туман) — курьер мўлжал қилади',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // GPS блок (мажбурий).
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
              border: Border.all(
                color: (_lat != null && _lng != null)
                    ? _green.withValues(alpha: 0.3)
                    : Colors.orange.shade300,
                width: 1.2,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.gps_fixed, color: _green, size: 18),
                const SizedBox(width: 8),
                const Text('GPS координаталари (мажбурий)',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const Spacer(),
                _gpsStatusBadge(),
              ]),
              const SizedBox(height: 10),
              if (_lat != null && _lng != null) ...[
                _gpsCoordsRow(),
                if (_accuracy != null) ...[
                  const SizedBox(height: 4),
                  _accuracyRow(),
                ],
                const SizedBox(height: 10),
              ] else
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text(
                    '⚠️ GPS ҳали олинмаган. Қуйидаги тугмани босинг.',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton.icon(
                  onPressed: _gpsLoading ? null : _useGps,
                  icon: _gpsLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Icon(
                          (_lat != null && _lng != null)
                              ? Icons.refresh
                              : Icons.my_location,
                          size: 18),
                  label: Text((_lat != null && _lng != null)
                      ? 'GPS-ни янгилаш'
                      : 'Жорий GPS манзилни олиш'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Қўлдаги манзил.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.edit_location_alt, color: _green, size: 18),
                SizedBox(width: 8),
                Text('Қўлда тўлдириш (мажбурий)',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              _field(
                ctrl: _mfyCtrl,
                label: 'МФЙ (Маҳалла фуқаролар йиғини) *',
                icon: Icons.location_city,
                hint: 'Масалан: «Бахт» МФЙ',
              ),
              const SizedBox(height: 12),
              _field(
                ctrl: _streetCtrl,
                label: 'Кўча / гузар *',
                icon: Icons.signpost,
                hint: 'Кўча/гузар номи',
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: _field(
                    ctrl: _houseCtrl,
                    label: 'Уй № *',
                    icon: Icons.home,
                    hint: '12',
                    keyboard: TextInputType.text,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _field(
                    ctrl: _districtCtrl,
                    label: 'Туман',
                    icon: Icons.map,
                    hint: 'Гурлан',
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _field(
                ctrl: _noteCtrl,
                label: 'Қўшимча (ихтиёрий)',
                icon: Icons.notes,
                hint: 'Подъезд, қават, ориентир...',
                maxLines: 2,
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Xizmat zonasi (configuration-driven) — ixtiyoriy, saqlashni bloklamaydi.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.hub_outlined, color: _green, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Xizmat zonasi (qaysi xizmatlar mavjudligi)',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  ServiceAreaPicker(
                    initialRegionId: _regionId,
                    initialDistrictId: _districtId,
                    initialServiceAreaId: _serviceAreaId,
                    onChanged: (region, district, area) {
                      _regionId = region;
                      _districtId = district;
                      _serviceAreaId = area;
                    },
                  ),
                ]),
          ),

          if (_err != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_err!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 13))),
              ]),
            ),
          ],

          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 20),
              label: const Text('Сақлаш',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _gpsStatusBadge() {
    final has = _lat != null && _lng != null;
    if (!has) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: const Text('Йўқ',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
      );
    }

    final addr = UserAddress(lat: _lat, lng: _lng, accuracy: _accuracy);
    final quality = addr.gpsQuality;
    final (label, bg, fg) = switch (quality) {
      GpsQuality.high => ('Аъло', AppColors.tickerShell, _green),
      GpsQuality.medium => ('Ўрта', AppColors.scaffold, AppColors.primary),
      GpsQuality.low => ('Паст', Colors.red.shade50, Colors.red.shade700),
      GpsQuality.unknown => ('OK', AppColors.tickerShell, AppColors.primaryDark),
      GpsQuality.none => ('Йўқ', Colors.grey.shade100, Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle, size: 11, color: fg),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
      ]),
    );
  }

  Widget _gpsCoordsRow() {
    return Row(children: [
      const Icon(Icons.place, size: 14, color: _green),
      const SizedBox(width: 4),
      Expanded(
        child: Text(
          '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
          style: const TextStyle(
              fontSize: 13, color: _green, fontWeight: FontWeight.w600),
        ),
      ),
    ]);
  }

  Widget _accuracyRow() {
    return Row(children: [
      const Icon(Icons.adjust, size: 12, color: Colors.grey),
      const SizedBox(width: 4),
      Text(
        'Аниқлик: ±${_accuracy!.toStringAsFixed(0)} метр',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      if (_geoUpdatedAt != null) ...[
        const SizedBox(width: 8),
        Icon(Icons.schedule, size: 11, color: Colors.grey.shade500),
        const SizedBox(width: 3),
        Text(
          _relativeTime(_geoUpdatedAt!),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    ]);
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'ҳозиргина';
    if (diff.inMinutes < 60) return '${diff.inMinutes} дақ. олдин';
    if (diff.inHours < 24) return '${diff.inHours} соат олдин';
    return '${diff.inDays} кун олдин';
  }

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    String hint = '',
    int maxLines = 1,
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: _green),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _green, width: 1.5)),
      ),
    );
  }
}

/// Helper: ProfileScreen ёки Bread/Food/Courier'дан мажбурий манзил
/// текширилади. Манзил `isComplete` (manual + GPS) бўлмаса — Edit экранига
/// юбориб, тўлдирилгандан кейин `UserAddress` qaytarилади.
///
/// Каллер ушбу `UserAddress`ни ProfileController.applyAddress'га узатиши
/// мумкин — шу ҳолда профил controller'и Firestore'дан қайта ўқимай туриб
/// ҳолатни darhol янгилaйди.
class AddressGate {
  static Future<UserAddress?> ensureFilled(
    BuildContext context, {
    UserAddress? current,
    UserModel? user,
  }) async {
    final initial = current ?? user?.address;
    if (initial != null && initial.isComplete) return initial;
    return await Navigator.push<UserAddress>(
      context,
      MaterialPageRoute(
          builder: (_) => AddressEditScreen(initial: initial)),
    );
  }
}
