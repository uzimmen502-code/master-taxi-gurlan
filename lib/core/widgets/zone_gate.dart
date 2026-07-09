import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/user_repository.dart';
import '../service_config_holder.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'service_area_picker.dart';

/// Xizmat zonasi darvozasi — [child] (Home) ko'rsatilishidan oldin foydalanuvchi
/// `serviceAreaId` ega ekanini kafolatlaydi.
///
/// Mantiq:
///   1. Kesh'da serviceAreaId bo'lsa → to'g'ridan-to'g'ri Home (tez yo'l).
///   2. Bo'lmasa → user hujjatidan tekshiradi (boshqa qurilmada tanlagan bo'lishi
///      mumkin) va topilsa qo'llaydi.
///   3. Baribir bo'sh bo'lsa → bloklovchi [ZoneSelectScreen] (viloyat+tuman).
///
/// Bu `enforce` bayrog'iga bog'liq emas: zona hozir yig'iladi (baza to'lishi
/// uchun), keyin admin `enforce=true` qiladi.
class ZoneGate extends StatefulWidget {
  const ZoneGate({super.key, required this.child});

  final Widget child;

  @override
  State<ZoneGate> createState() => _ZoneGateState();
}

class _ZoneGateState extends State<ZoneGate> {
  bool _checking = true;
  bool _needsZone = false;
  String _uid = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    // Tez yo'l: kesh allaqachon zonaga ega.
    if (ServiceConfigHolder.serviceAreaId.trim().isNotEmpty) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _uid = (prefs.getString('userId') ?? '').trim();
      if (_uid.isEmpty) {
        _uid = phoneDigits(prefs.getString('user_phone') ?? '');
      }
      if (_uid.isNotEmpty) {
        final user = await UserRepository().getById(_uid);
        final areaId = (user?.serviceAreaId ?? '').trim();
        if (areaId.isNotEmpty) {
          await ServiceConfigHolder.applyServiceArea(areaId);
          if (mounted) setState(() => _checking = false);
          return;
        }
      }
    } catch (_) {
      // Tarmoq xatosi — keshda zona bo'lsa Home, aks holda bloklash.
      if (ServiceConfigHolder.serviceAreaId.trim().isNotEmpty) {
        if (mounted) setState(() => _checking = false);
        return;
      }
      if (mounted) {
        setState(() {
          _checking = false;
          _needsZone = true;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _checking = false;
        _needsZone = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_needsZone) {
      return ZoneSelectScreen(
        uid: _uid,
        onDone: () {
          if (mounted) setState(() => _needsZone = false);
        },
      );
    }
    return widget.child;
  }
}

/// Bir marталик bloklovchi zona tanlash ekrani (eski foydalanuvchilar uchun).
class ZoneSelectScreen extends StatefulWidget {
  const ZoneSelectScreen({
    super.key,
    required this.uid,
    required this.onDone,
  });

  final String uid;
  final VoidCallback onDone;

  @override
  State<ZoneSelectScreen> createState() => _ZoneSelectScreenState();
}

class _ZoneSelectScreenState extends State<ZoneSelectScreen> {
  String _regionId = '';
  String _districtId = '';
  String _areaId = '';
  bool _saving = false;
  String? _error;

  bool get _valid => _regionId.isNotEmpty && _districtId.isNotEmpty;

  Future<void> _save() async {
    if (!_valid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await UserRepository().saveServiceArea(
        uid: widget.uid,
        regionId: _regionId,
        districtId: _districtId,
        serviceAreaId: _areaId,
      );
      await ServiceConfigHolder.applyGeo(
        regionId: _regionId,
        districtId: _districtId,
        serviceAreaId: _areaId,
      );
      widget.onDone();
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Saqlab bo\'lmadi. Internet ulanishini tekshirib qayta urining.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.holiday_village,
                      size: 56, color: AppColors.primaryDark),
                  const SizedBox(height: 16),
                  const Text(
                    'Xizmat zonangizni tanlang',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Hududingizda qaysi xizmatlar mavjudligini aniqlash uchun '
                    'viloyat va tumaningizni tanlang. Bu bir marta so\'raladi.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 24),
                  ServiceAreaPicker(
                    showAreaDropdown: false,
                    onChanged: (r, d, a) {
                      setState(() {
                        _regionId = r;
                        _districtId = d;
                        _areaId = a;
                      });
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _valid && !_saving ? _save : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Davom etish',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
