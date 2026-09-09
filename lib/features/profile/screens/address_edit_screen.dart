import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/brand_labels.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/widgets/service_area_picker.dart';
import '../../../models/user_address.dart';
import '../../../models/user_model.dart';
import '../../../repositories/user_repository.dart';
import '../controllers/profile_controller.dart';
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

  /// Зона бўлими default'да ёпиқ — фақат хулоса кўринади («Ўзгартириш»
  /// босилса очилади). Зона онбордингда аллақачон танланган.
  bool _editZone = false;

  /// Зона хулосаси — жорий туман номи (маълумот бўлмаса огоҳлантириш).
  String _zoneSummary(BuildContext context) {
    final district = ServiceConfigHolder.districtLabel.trim();
    return district.isEmpty ? context.tr('addr_zone_empty') : district;
  }

  /// Туман — хизмат зонасидан (қўлда киритилмайди: битта манба).
  /// Зона ҳали ўқилмаган бўлса — эски сақланган манзилдаги туман.
  String get _districtLabel {
    final fromZone = ServiceConfigHolder.districtLabel.trim();
    if (fromZone.isNotEmpty) return fromZone;
    return (widget.initial?.district ?? '').trim();
  }

  @override
  void initState() {
    super.initState();
    // Зона — `ServiceConfigHolder`дан СИНХРОН (у хотирада тайёр: ZoneGate
    // Home'дан олдин тўлдиради). Аввал бу Firestore'дан async ўқиларди ва
    // `ServiceAreaPicker` ўз `initState`ида бўш қийматни олиб улгурарди —
    // dropdown'лар доим бўш қоларди.
    _regionId = ServiceConfigHolder.regionId.trim();
    _districtId = ServiceConfigHolder.districtId.trim();
    _serviceAreaId = ServiceConfigHolder.serviceAreaId.trim();

    final a = widget.initial;
    if (a != null) {
      _mfyCtrl.text = a.mfy;
      _streetCtrl.text = a.street;
      _houseCtrl.text = a.house;
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
      setState(() => _err = context.tr('addr_err_manual_required'));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final uid = phoneDigits(prefs.getString('user_phone') ?? '');
    if (uid.length < 9) {
      setState(() => _err = context.tr('addr_err_phone_first'));
      return;
    }

    // GPS — тавсия этилади, лекин сақлашни бloкламайди: бино ичида /
    // GPS ўчиқ бўлса ҳам фойдаланувчи манзилини сақлай олсин (аввал
    // `validationError` GPS'ни мажбурий қилиб, сақлашга йўл бермасди).
    final address = UserAddress(
      mfy: mfy,
      street: street,
      house: house,
      district: _districtLabel,
      note: _noteCtrl.text.trim(),
      lat: _lat,
      lng: _lng,
      accuracy: _accuracy,
      geoUpdatedAt: _geoUpdatedAt,
      manualUpdatedAt: DateTime.now(),
    );

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
      setState(() => _err = '${context.tr('addr_err_save')}: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('addr_title')),
            Text(
              BrandLabels.districtContext == null
                  ? BrandLabels.brand
                  : '${BrandLabels.brand} · ${BrandLabels.districtContext}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
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
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('addr_intro_title'),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr('addr_intro_body'),
                      style: const TextStyle(
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
                Expanded(
                  child: Text(context.tr('addr_gps_title'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                ),
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    context.tr('addr_gps_missing_hint'),
                    style: const TextStyle(
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
                  label: Text(context.tr((_lat != null && _lng != null)
                      ? 'addr_gps_refresh'
                      : 'addr_gps_get')),
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
              Row(children: [
                const Icon(Icons.edit_location_alt, color: _green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.tr('addr_manual_title'),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ]),
              const SizedBox(height: 12),
              _field(
                ctrl: _mfyCtrl,
                label: context.tr('addr_mfy_label'),
                icon: Icons.location_city,
                hint: context.tr('addr_mfy_hint'),
              ),
              const SizedBox(height: 12),
              _field(
                ctrl: _streetCtrl,
                label: context.tr('addr_street_label'),
                icon: Icons.signpost,
                hint: context.tr('addr_street_hint'),
              ),
              const SizedBox(height: 12),
              // Туман энди қўлда киритилмайди — у хизмат зонасидан келади
              // (иккита манба зиддияти бартараф этилди), шу сабабли «Уй №»
              /// бутун кенгликни олади ва ёрлиғи қирқилмайди.
              _field(
                ctrl: _houseCtrl,
                label: context.tr('addr_house_label'),
                icon: Icons.home,
                hint: '12',
              ),
              if (_districtLabel.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.map_outlined, size: 15, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${context.tr('addr_district_label')}: $_districtLabel',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              _field(
                ctrl: _noteCtrl,
                label: context.tr('addr_note_label'),
                icon: Icons.notes,
                hint: context.tr('addr_note_hint'),
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
                  Row(children: [
                    const Icon(Icons.hub_outlined, color: _green, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(context.tr('addr_zone_title'),
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                    if (!_editZone)
                      TextButton(
                        onPressed: () => setState(() => _editZone = true),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(context.tr('addr_zone_change')),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  // Зона онбордингда танланган — одатда фақат хулоса
                  // кўрсатилади, «Ўзгартириш» босилгандагина танлов очилади.
                  if (!_editZone)
                    Text(
                      _zoneSummary(context),
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade700),
                    )
                  else
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
              label: Text(context.tr('save'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
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
        child: Text(context.tr('addr_gps_none'),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.primary)),
      );
    }

    final addr = UserAddress(lat: _lat, lng: _lng, accuracy: _accuracy);
    final quality = addr.gpsQuality;
    final (label, bg, fg) = switch (quality) {
      GpsQuality.high =>
        (context.tr('addr_gps_high'), AppColors.tickerShell, _green),
      GpsQuality.medium =>
        (context.tr('addr_gps_medium'), AppColors.scaffold, AppColors.primary),
      GpsQuality.low =>
        (context.tr('addr_gps_low'), Colors.red.shade50, Colors.red.shade700),
      GpsQuality.unknown =>
        ('OK', AppColors.tickerShell, AppColors.primaryDark),
      GpsQuality.none =>
        (context.tr('addr_gps_none'), Colors.grey.shade100, Colors.grey),
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
        context
            .tr('addr_gps_accuracy')
            .replaceAll('{m}', _accuracy!.toStringAsFixed(0)),
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
    if (diff.inMinutes < 1) return context.tr('addr_time_just_now');
    if (diff.inMinutes < 60) {
      return context.tr('addr_time_min').replaceAll('{n}', '${diff.inMinutes}');
    }
    if (diff.inHours < 24) {
      return context.tr('addr_time_hour').replaceAll('{n}', '${diff.inHours}');
    }
    return context.tr('addr_time_day').replaceAll('{n}', '${diff.inDays}');
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

  /// Профилдан манзилни таҳрирлаш — натижа [controller]га қўлланади.
  /// Профил экрани ва «Фойдаланувчи маълумотлари» экранида бир хил
  /// такрорланган мантиқ шу ерга йиғилди (битта манба).
  static Future<void> edit(
    BuildContext context,
    ProfileController controller,
  ) async {
    final result = await Navigator.push<UserAddress>(
      context,
      MaterialPageRoute(
        builder: (_) => AddressEditScreen(initial: controller.structuredAddress),
      ),
    );
    if (!context.mounted) return;
    if (result != null) {
      controller.applyAddress(result);
      return;
    }
    // Back босилди — манзил бошқа оқимда (AddressGate) сақланган бўлиши
    // мумкин, шу сабабли локал кешдан қайта ўқилади.
    await controller.reloadAddressFromPrefs();
  }
}
