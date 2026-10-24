import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../../intercity_tap_target.dart';
import '../intercity_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../models/intercity_booking.dart';
import '../../../../models/sell_submission.dart';
import '../../../../models/user_address.dart';
import '../../../../repositories/intercity_bookings_repository.dart';
import '../../../../repositories/user_repository.dart';
import '../../../../services/location_service.dart';
import '../../../profile/screens/address_edit_screen.dart';

/// Шаҳарлараро брон учун олиб ketish manzilini kiritish.
///
/// Manba: profil [UserAddress] yoki joriy GPS ([LocationService]).
/// Saqlash: [IntercityBookingsRepository.updatePickup].
class IntercityPickupSheet extends StatefulWidget {
  const IntercityPickupSheet({super.key, required this.booking});

  final IntercityBooking booking;

  static Future<bool> show(
    BuildContext context, {
    required IntercityBooking booking,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IntercityPickupSheet(booking: booking),
    );
    return saved == true;
  }

  @override
  State<IntercityPickupSheet> createState() => _IntercityPickupSheetState();
}

class _IntercityPickupSheetState extends State<IntercityPickupSheet> {
  static const _green = AppColors.primaryText;

  final _mfyCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _houseCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  UserAddress _profileAddress = const UserAddress();
  double? _lat;
  double? _lng;
  double? _accuracy;
  bool _loadingProfile = true;
  bool _gpsLoading = false;
  bool _saving = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  @override
  void dispose() {
    _mfyCtrl.dispose();
    _streetCtrl.dispose();
    _houseCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final userRepo = context.read<UserRepository>();
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = phoneDigits(prefs.getString('user_phone') ?? '');
      UserAddress structured = const UserAddress();
      if (uid.length >= 9) {
        final user = await userRepo.getById(uid);
        if (user != null) structured = user.address;
      }
      if (!mounted) return;
      _applyAddress(structured);
      if (!_hasManualFields && (prefs.getString('user_address') ?? '').isNotEmpty) {
        _streetCtrl.text = prefs.getString('user_address') ?? '';
      }
    } catch (_) {
      // Profil o'qilmasa ham GPS va qo'lda kiritish mumkin.
    } finally {
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  void _applyAddress(UserAddress a) {
    _profileAddress = a;
    _mfyCtrl.text = a.mfy;
    _streetCtrl.text = a.street;
    _houseCtrl.text = a.house;
    _noteCtrl.text = a.note;
    _lat = a.lat;
    _lng = a.lng;
    _accuracy = a.accuracy;
  }

  bool get _hasManualFields =>
      _mfyCtrl.text.trim().isNotEmpty &&
      _streetCtrl.text.trim().isNotEmpty &&
      _houseCtrl.text.trim().isNotEmpty;

  bool get _hasGps =>
      _lat != null &&
      _lng != null &&
      !(_lat!.abs() < 1e-6 && _lng!.abs() < 1e-6);

  UserAddress get _draftAddress => UserAddress(
        mfy: _mfyCtrl.text.trim(),
        street: _streetCtrl.text.trim(),
        house: _houseCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
        lat: _lat,
        lng: _lng,
        accuracy: _accuracy,
        geoUpdatedAt: _hasGps ? DateTime.now() : null,
      );

  /// `UserAddress.validationError` модел ичида ҳардкод Кирилл матн қайтаради —
  /// бу ерда ўрнига 3 тилли калит.
  String? _validationKey(UserAddress a) {
    if (a.validationError == null) return null;
    return a.hasManualAddress ? 'gps_error' : 'addr_err_manual_required';
  }

  Future<void> _useProfileAddress() async {
    if (_saving) return;
    final key = _validationKey(_profileAddress);
    if (key != null) {
      setState(() => _err = key);
      return;
    }
    _applyAddress(_profileAddress);
    setState(() => _err = null);
    await _save();
  }

  Future<void> _fetchGps() async {
    setState(() {
      _gpsLoading = true;
      _err = null;
    });
    const svc = LocationService();
    try {
      final coords = await svc.getCurrentCoords(
        mediumTimeout: const Duration(seconds: 5),
        highTimeout: const Duration(seconds: 12),
      );
      _lat = coords.lat;
      _lng = coords.lng;
      _accuracy = coords.accuracy;
      if (_streetCtrl.text.trim().isEmpty) {
        final geo = await svc.addressFromCoords(
          coords.lat,
          coords.lng,
          timeout: const Duration(seconds: 5),
          fallbackToCoords: true,
        );
        if (geo != null && geo.trim().isNotEmpty) {
          _streetCtrl.text = geo.trim();
        }
      }
      if (!mounted) return;
      setState(() {});
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(() {
        _err = switch (e.kind) {
          LocationErrorKind.permissionDenied => 'gps_permission_denied_msg',
          LocationErrorKind.serviceDisabled => 'gps_service_disabled_msg',
          LocationErrorKind.timeout => 'gps_timeout_msg',
          LocationErrorKind.lookupFailed => 'gps_lookup_failed_msg',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _err = 'gps_error');
    } finally {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _openAddressEditor() async {
    final edited = await Navigator.of(context).push<UserAddress>(
      MaterialPageRoute(
        builder: (_) => AddressEditScreen(initial: _draftAddress),
      ),
    );
    if (edited == null || !mounted) return;
    setState(() {
      _applyAddress(edited);
      _err = null;
    });
  }

  Future<void> _save() async {
    // Қайта босишдан ҳимоя: биринчи await'дан ОЛДИН банд қиламиз.
    if (_saving) return;
    final draft = _draftAddress;
    final validationKey = _validationKey(draft);
    if (validationKey != null) {
      setState(() => _err = validationKey);
      return;
    }
    setState(() {
      _saving = true;
      _err = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = phoneDigits(prefs.getString('user_phone') ?? '');
      if (phone.length < 9) {
        if (mounted) setState(() => _err = 'addr_err_phone_first');
        return;
      }

      final fields = SellSubmission.pickupFieldsFromAddress(
        address: draft,
        legacy: prefs.getString('user_address') ?? '',
      );
      final addressText = (fields['pickupAddress'] as String?) ?? '';
      final lat = (fields['pickupLat'] as num?)?.toDouble();
      final lng = (fields['pickupLng'] as num?)?.toDouble();
      if (addressText.isEmpty || lat == null || lng == null) {
        if (mounted) setState(() => _err = 'gps_error');
        return;
      }

      if (!mounted) return;
      final repo = context.read<IntercityBookingsRepository>();
      await repo.updatePickup(
        bookingId: widget.booking.id,
        userPhone: phone,
        address: addressText,
        lat: lat,
        lng: lng,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final savedText = context.tr('intercity_pickup_saved');
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(content: Text(savedText)));
    } catch (e) {
      // Ички сабаб фақат логда; фойдаланувчига тушунарли хабар (CLAUDE.md §25).
      debugPrint('intercity updatePickup failed: $e');
      if (mounted) setState(() => _err = 'ic_ux_action_failed');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final errText = _err == null ? null : context.tr(_err!);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: IntercityColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: IntercityColors.textFaint,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('pickup_sheet_title'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _green,
                      ),
                    ),
                  ),
                  // Ёпиш йўли: фақат тортиш/фон босишга таянмаймиз.
                  IconButton(
                    tooltip: context.tr('close'),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('pickup_where_question'),
                style: const TextStyle(
                    fontSize: 14, color: IntercityColors.textMuted),
              ),
              if (_loadingProfile)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                const SizedBox(height: 16),
                if (_profileAddress.isComplete) ...[
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _useProfileAddress,
                    icon: const Icon(Icons.home_outlined),
                    label: Text(context.tr('intercity_pickup_use_profile')),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _profileAddress.formatted,
                    style: const TextStyle(
                      fontSize: 13,
                      color: IntercityColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: _gpsLoading || _saving ? null : _fetchGps,
                  icon: _gpsLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: Text(context.tr('ob_gps_get')),
                ),
                if (_hasGps) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryText,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // Белгилар профил манзили экрани билан бир хил (`addr_*`,
                // мажбурийлиги `*` билан кўрсатилган).
                TextField(
                  controller: _mfyCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr('addr_mfy_label'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _streetCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr('addr_street_label'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _houseCtrl,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: context.tr('addr_house_label'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                TextButton(
                  onPressed: _saving ? null : _openAddressEditor,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, IntercityTapTarget.minSize),
                  ),
                  child: Text(context.tr('edit')),
                ),
                if (errText != null) ...[
                  const SizedBox(height: 8),
                  // Хато майдонлар остида, иконка + матн (фақат ранг эмас),
                  // screen reader дарҳол ўқийди.
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: IntercityColors.dangerSoft,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: IntercityColors.danger),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ExcludeSemantics(
                            child: Icon(Icons.error_outline,
                                size: 18, color: IntercityColors.danger),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errText,
                              style: const TextStyle(
                                  color: IntercityColors.danger, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: IntercityColors.primary,
                    foregroundColor: IntercityColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: IntercityColors.onPrimary,
                          ),
                        )
                      : Text(context.tr('save_pickup_address')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
