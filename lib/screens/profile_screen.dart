import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../l10n/app_localizations.dart';
import 'onboarding_screen.dart';
import 'home_screen.dart';
import 'admin_screen.dart';
import 'courier_screen.dart';
import '../services/fcm_service.dart';
import 'chat_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _green  = Color(0xFF2E7D32);
  static const _blue   = Color(0xFF1565C0);

  // Асосий маълумотлар
  String _name     = '';
  String _phone    = '';
  String _gender   = 'male';
  String _role     = 'user';
  String _address  = '';
  String? _imagePath;

  // Машина маълумотлари (фақат ҳайдовчи)
  String _carModel   = '';
  String _carColor   = '';
  String _carPlate   = '';
  String _taxiType   = 'alone'; // alone | marshrut | intercity
  double _driverRating    = 0.0;
  int    _driverTripCount = 0;

  final TextEditingController _nameCtrl     = TextEditingController();
  final TextEditingController _phoneCtrl    = TextEditingController();
  final TextEditingController _addressCtrl  = TextEditingController();
  final TextEditingController _carModelCtrl = TextEditingController();
  final TextEditingController _carColorCtrl = TextEditingController();
  final TextEditingController _carPlateCtrl = TextEditingController();

  bool _isEditing     = false;
  bool _isSaving      = false;
  bool _isGpsLoading  = false;
  bool _ordersLoading = true;
  bool _tripsLoading  = true;
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _trips  = []; // Сафар тарихи
  int    _driverEarnings = 0;             // Ҳайдовчи жами даромад
  final _db = FirebaseFirestore.instance;

  String _digits(String v) => v.replaceAll(RegExp(r'[^\d]'), '');

  List<String> _phoneAliases(String raw) {
    final t = raw.trim();
    final d = _digits(raw);
    final aliases = <String>{};
    if (t.isNotEmpty) aliases.add(t);
    final compact = t.replaceAll(' ', '');
    if (compact.isNotEmpty) aliases.add(compact);
    if (d.isNotEmpty) {
      aliases.add(d);
      aliases.add('+$d');
    }
    return aliases.take(10).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _name      = prefs.getString('user_name')    ?? '';
      _phone     = prefs.getString('user_phone')   ?? '';
      _gender    = prefs.getString('user_gender')  ?? 'male';
      _role      = prefs.getString('user_role')    ?? 'user';
      _address   = prefs.getString('user_address') ?? '';
      _imagePath = prefs.getString('profile_image');
      _carModel  = prefs.getString('car_model')    ?? '';
      _carColor  = prefs.getString('car_color')    ?? '';
      _carPlate  = prefs.getString('car_plate')    ?? '';
      _taxiType  = prefs.getString('taxi_type')    ?? 'alone';
    });
    _nameCtrl.text     = _name;
    _phoneCtrl.text    = _phone;
    _addressCtrl.text  = _address;
    _carModelCtrl.text = _carModel;
    _carColorCtrl.text = _carColor;
    _carPlateCtrl.text = _carPlate;

    if (_role == 'driver' && _phone.isNotEmpty) {
      await _loadDriverStats();
      await _loadDriverTrips();
    } else {
      await _loadOrders();
      await _loadUserTrips();
    }
  }

  Future<void> _loadDriverStats() async {
    try {
      final uid = _phone.replaceAll(RegExp(r'[^\d]'), '');
      final doc = await _db.collection('drivers').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
        if (!mounted) return;
        setState(() {
          _driverRating    = (data['rating']      ?? 0.0).toDouble();
          _driverTripCount = (data['ratingCount'] ?? 0) as int;
        });
      }
    } catch (_) {}
  }

  // ── Ҳайдовчи сафар тарихи ──
  Future<void> _loadDriverTrips() async {
    if (_phone.isEmpty) {
      if (mounted) setState(() => _tripsLoading = false);
      return;
    }
    try {
      final uid  = _phone.replaceAll(RegExp(r'[^\d]'), '');
      final snap = await _db
          .collection('trips')
          .where('acceptedDriverId', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .limit(20)
          .get();

      int totalEarnings = 0;
      final list = snap.docs.map((d) {
        final data = d.data();
        final fare = (data['fare'] ?? 0) as int;
        totalEarnings += fare;
        return {
          'id':          d.id,
          'from':        data['from']       ?? '',
          'to':          data['to']         ?? '',
          'fare':        fare,
          'userPhone':   data['userPhone']  ?? '',
          'taxiType':    data['taxiType']   ?? 'alone',
          'completedAt': data['completedAt'],
        };
      }).toList();

      // Dart томонида сортировка
      list.sort((a, b) {
        final at = a['completedAt'] as Timestamp?;
        final bt = b['completedAt'] as Timestamp?;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

      if (mounted) setState(() {
        _trips          = list;
        _driverEarnings = totalEarnings;
        _tripsLoading   = false;
      });
    } catch (e) {
      if (mounted) setState(() => _tripsLoading = false);
    }
  }

  // ── Фойдаланувчи сафар тарихи ──
  Future<void> _loadUserTrips() async {
    if (_phone.isEmpty) {
      if (mounted) setState(() => _tripsLoading = false);
      return;
    }
    try {
      final aliases = _phoneAliases(_phone);
      final snap = await _db
          .collection('trips')
          .where('userPhone', whereIn: aliases)
          .where('status', isEqualTo: 'completed')
          .limit(20)
          .get();

      final list = snap.docs.map((d) {
        final data = d.data();
        return {
          'id':          d.id,
          'from':        data['from']                ?? '',
          'to':          data['to']                  ?? '',
          'fare':        (data['fare']               ?? 0) as int,
          'driverName':  data['acceptedDriverName']  ?? '',
          'driverCar':   data['acceptedDriverCar']   ?? '',
          'taxiType':    data['taxiType']             ?? 'alone',
          'completedAt': data['completedAt'],
        };
      }).toList();

      // Dart томонида сортировка
      list.sort((a, b) {
        final at = a['completedAt'] as Timestamp?;
        final bt = b['completedAt'] as Timestamp?;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

      if (mounted) setState(() {
        _trips        = list;
        _tripsLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _tripsLoading = false);
    }
  }

  // ── GPS орқали манзил ──
  Future<void> _getAddressFromGps() async {
    if (!mounted) return;
    setState(() => _isGpsLoading = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _showError('GPS рухсати берилмади');
        if (mounted) setState(() => _isGpsLoading = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      final marks = await placemarkFromCoordinates(
          pos.latitude, pos.longitude);
      final addr = marks.isNotEmpty
          ? '${marks.first.street ?? ''} ${marks.first.subLocality ?? ''}, ${marks.first.locality ?? ''}'.trim()
          : '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      if (!mounted) return;
      setState(() {
        _address = addr;
        _addressCtrl.text = addr;
        _isGpsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isGpsLoading = false);
      _showError('GPS аниқланмади');
    }
  }

  Future<void> _loadOrders() async {
    if (_phone.isEmpty) {
      if (mounted) setState(() => _ordersLoading = false);
      return;
    }
    try {
      final aliases = _phoneAliases(_phone);
      final snap = await _db
          .collection('orders')
          .where('userPhone', whereIn: aliases)
          .limit(20)
          .get();

      final list = snap.docs.map((d) {
        final data = d.data();
        return {
          'id':           d.id,
          'type':         data['type']         ?? 'bread',
          'total':        data['total']         ?? 0,
          'status':       data['status']        ?? 'new',
          'items':        data['items']         ?? [],
          'address':      data['address']       ?? '',
          'deliveryTime': data['deliveryTime']  ?? '',
          'rejectReason': data['rejectReason']  ?? '',
          'createdAt':    data['createdAt'],
        };
      }).toList();

      // Dart сортировка
      list.sort((a, b) {
        final at = a['createdAt'] as Timestamp?;
        final bt = b['createdAt'] as Timestamp?;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

      if (mounted) setState(() {
        _orders        = list;
        _ordersLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _ordersLoading = false);
    }
  }

  // Сақлашдан олдин эски ролни сақлаб оламиз
  String _oldRole = '';

  Future<void> _saveData() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _showError('Исмни киритинг'); return;
    }
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();

    // Эски ролни эслаб қоламиз
    _oldRole = prefs.getString('user_role') ?? 'user';

    await prefs.setString('user_name',    _nameCtrl.text.trim());
    await prefs.setString('user_phone',   _phoneCtrl.text.trim());
    await prefs.setString('user_gender',  _gender);
    await prefs.setString('user_role',    _role);
    await prefs.setString('user_address', _addressCtrl.text.trim());
    // Машина маълумотлари

    if (!mounted) return;
    setState(() {
      _name      = _nameCtrl.text.trim();
      _phone     = _phoneCtrl.text.trim();
      _isEditing = false;
      _isSaving  = false;
    });

    _showSuccess('Маълумотлар сақланди');

    // FCM token yangilash
    try {
      await FCMService().refreshToken();
      FCMService().stopListeners();
      await FCMService().startListeners();
    } catch (_) {}

    // Роль ўзгарди — мос экранга ўтиш
    if (_role != _oldRole) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
      );
    } else {
      if (Navigator.canPop(context)) Navigator.pop(context);
    }
  }

  void _cancelEdit() {
    _nameCtrl.text  = _name;
    _phoneCtrl.text = _phone;
    setState(() => _isEditing = false);
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 80);
    if (file == null) return;
    final dir   = await getApplicationDocumentsDirectory();
    final saved = await File(file.path).copy('${dir.path}/profile.jpg');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_image', saved.path);
    setState(() => _imagePath = saved.path);
  }

  Future<void> _deleteImage() async {
    if (_imagePath != null) {
      final f = File(_imagePath!);
      if (await f.exists()) await f.delete();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('profile_image');
    setState(() => _imagePath = null);
  }

  void _showImagePicker(AppLocalizations loc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text(loc.translate('photo_source'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.photo_library, color: _green),
            title: Text(loc.translate('gallery')),
            onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: _green),
            title: Text(loc.translate('camera')),
            onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
          ),
          if (_imagePath != null)
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(loc.translate('delete_photo'), style: const TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(context); _deleteImage(); },
            ),
        ]),
      ),
    );
  }

  void _showLogoutDialog(AppLocalizations loc) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(loc.translate('logout_confirm')),
        content: Text(loc.translate('logout_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                    (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(loc.translate('logout'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating));
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating));
  }

  String _honorific(AppLocalizations loc) => _gender == 'female' ? loc.translate('madam') : loc.translate('mister');
  String _roleLabel(AppLocalizations loc) {
    switch (_role) {
      case 'driver':  return loc.translate('driver_role');
      case 'courier': return '🛵 Курьер';
      case 'admin':   return '🔧 Админ';
      default:       return loc.translate('user_role');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: Text(loc.translate('profile')),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_isEditing)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onSelected: (val) {
                if (val == 'edit')   setState(() => _isEditing = true);
                if (val == 'logout') _showLogoutDialog(loc);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    const Icon(Icons.edit, size: 18, color: Colors.black87),
                    const SizedBox(width: 10),
                    Text(loc.translate('edit')),
                  ]),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'logout',
                  child: Row(children: [
                    const Icon(Icons.logout, size: 18, color: Colors.red),
                    const SizedBox(width: 10),
                    Text(loc.translate('logout'), style: const TextStyle(color: Colors.red)),
                  ]),
                ),
              ],
            )
          else ...[
            TextButton(
              onPressed: _cancelEdit,
              child: Text(loc.translate('cancel'), style: const TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: _isSaving ? null : _saveData,
              child: Text(loc.translate('save'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              color: _green,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
              child: Center(
                child: Column(children: [
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _showImagePicker(loc),
                    child: Stack(children: [
                      Container(
                        width: 90, height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: ClipOval(
                          child: _imagePath != null
                              ? Image.file(File(_imagePath!), fit: BoxFit.cover)
                              : Center(
                            child: Text(
                              _name.isNotEmpty ? _name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: _green),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          width: 26, height: 26,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt, size: 15, color: _green),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Text('${_honorific(loc)} $_name',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_roleLabel(loc), style: const TextStyle(fontSize: 12, color: Colors.white)),
                  ),
                ]),
              ),
            ),

            Transform.translate(
              offset: const Offset(0, -20),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: Column(children: [
                  // Исм
                  _fieldRow(
                    icon: Icons.person_outline,
                    label: loc.translate('name'),
                    child: _isEditing
                        ? _editField(_nameCtrl, loc.translate('enter_name'), TextInputType.name)
                        : Text(_name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                  const Divider(height: 24),

                  // Телефон
                  _fieldRow(
                    icon: Icons.phone_outlined,
                    label: loc.translate('phone'),
                    child: _isEditing
                        ? _editField(_phoneCtrl, loc.translate('enter_phone'), TextInputType.phone,
                        formatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\+\s]'))])
                        : Text(_phone, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                  const Divider(height: 24),

                  // Жинс
                  _fieldRow(
                    icon: Icons.person,
                    label: loc.translate('gender'),
                    child: _isEditing
                        ? Row(children: [
                      _genderChip('male',   loc.translate('male')),
                      const SizedBox(width: 8),
                      _genderChip('female', loc.translate('female')),
                    ])
                        : Text(_gender == 'female' ? loc.translate('female') : loc.translate('male'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                  ),
                  const Divider(height: 24),

                  // Роль
                  _fieldRow(
                    icon: Icons.badge_outlined,
                    label: loc.translate('role'),
                    child: _isEditing
                        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const SizedBox(height: 6),
                      _roleChip('user',    '👤', loc.translate('user_role').replaceAll('👤 ', '')),
                      const SizedBox(height: 6),
                      _roleChip('courier', '🛵', 'Курьер'),
                      const SizedBox(height: 6),
                      _roleChip('admin',   '🔧', 'Админ'),
                    ])
                        : GestureDetector(
                      onTap: () => setState(() => _isEditing = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: _green.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _green.withOpacity(0.3)),
                        ),
                        child: Row(children: [
                          Text(_roleLabel(loc),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _green)),
                          const Spacer(),
                          const Icon(Icons.swap_horiz, color: _green, size: 16),
                          const SizedBox(width: 3),
                          Text(loc.translate('change_role'),
                              style: const TextStyle(fontSize: 11, color: _green)),
                        ]),
                      ),
                    ),
                  ),

                  const Divider(height: 24),

                  // Манзил
                  _fieldRow(
                    icon: Icons.location_on_outlined,
                    label: '📍 Асосий манзил',
                    child: _isEditing
                        ? Row(children: [
                      Expanded(child: _editField(
                        _addressCtrl,
                        'Гурлан, МФЙ, уй рақами',
                        TextInputType.streetAddress,
                      )),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _getAddressFromGps,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _green.withOpacity(0.3)),
                          ),
                          child: _isGpsLoading
                              ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _green))
                              : const Icon(Icons.gps_fixed,
                              size: 16, color: _green),
                        ),
                      ),
                    ])
                        : Text(
                      _address.isEmpty ? 'Манзил киритилмаган' : _address,
                      style: TextStyle(
                        fontSize: 14,
                        color: _address.isEmpty ? Colors.grey : Colors.black87,
                        fontStyle: _address.isEmpty
                            ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                  ),
                ]),
              ),
            ),

            const SizedBox(height: 32),

            // ── Машина маълумотлари (фақат ҳайдовчи) ──

            if (_role == 'admin')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AdminScreen())),
                    icon: const Icon(Icons.admin_panel_settings),
                    label: const Text('АДМИН ПАНЕЛИ',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D47A1),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),

            if (_role == 'courier')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CourierScreen())),
                    icon: const Icon(Icons.delivery_dining),
                    label: const Text('КУРЬЕР ПАНЕЛИ',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE65100),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(targetPhone: _digits(_phone)),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _green.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, color: _green, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '💬 Админ билан чат',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),

            // ── Сафар тарихи ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                        _role == 'driver' ? Icons.directions_car : Icons.route,
                        color: _blue, size: 18),
                    const SizedBox(width: 8),
                    Text(
                        _role == 'driver'
                            ? '🚕 Сафарлар тарихи'
                            : '🗺️ Сафарлар тарихи',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (_role == 'driver' && _driverEarnings > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _green.withOpacity(0.3)),
                        ),
                        child: Text(
                            '💰 ${_fmtPrice(_driverEarnings)} сўм',
                            style: const TextStyle(
                                fontSize: 11,
                                color: _green,
                                fontWeight: FontWeight.w700)),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  if (_tripsLoading)
                    const Center(child: CircularProgressIndicator(
                        color: _blue, strokeWidth: 2))
                  else if (_trips.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Center(child: Column(children: [
                        Icon(Icons.route_outlined,
                            size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text('Сафарлар тарихи йўқ',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade400)),
                      ])),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _trips.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _tripCard(_trips[i]),
                    ),
                ],
              ),
            ),

            // ── Буюртмалар тарихи ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.receipt_long, color: _green, size: 18),
                  const SizedBox(width: 8),
                  Text('📋 Буюртмалар тарихи',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (!_ordersLoading)
                    GestureDetector(
                      onTap: _loadOrders,
                      child: const Icon(Icons.refresh, color: _green, size: 18),
                    ),
                ]),
                const SizedBox(height: 12),

                if (_ordersLoading)
                  const Center(child: CircularProgressIndicator(color: _green, strokeWidth: 2))
                else if (_orders.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Center(child: Column(children: [
                      Icon(Icons.receipt_outlined, size: 40, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Text('Буюртмалар йўқ',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                    ])),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _orderCard(_orders[i]),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final type         = order['type']         as String;
    final total        = order['total']        as int;
    final status       = order['status']       as String;
    final items        = order['items']        as List;
    final ts           = order['createdAt'];
    final deliveryTime = order['deliveryTime'] as String? ?? '';
    final rejectReason = order['rejectReason'] as String? ?? '';

    final isFood = type == 'food';
    final emoji  = isFood ? '🍽️' : '🫓';
    final title  = isFood ? 'Овқат буюртма' : 'Нон буюртма';
    final color  = isFood ? Colors.green : const Color(0xFFE65100);

    String dateStr = '';
    if (ts != null && ts is Timestamp) {
      final dt = ts.toDate();
      dateStr = '${dt.day}-${_monthName(dt.month)}';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (dateStr.isNotEmpty)
            Text(dateStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          const SizedBox(width: 8),
          _statusChip(status),
        ]),
        const SizedBox(height: 8),

        ...items.take(3).map((item) {
          final name   = item['name']  as String? ?? '';
          final count  = item['count'] as int?    ?? 1;
          final qty    = item['qty'];
          final unit   = item['unit']  as String? ?? '';
          final qtyStr = qty != null ? '${qty.toString()} $unit' : '× $count';
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('• $name  $qtyStr',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          );
        }),
        if (items.length > 3)
          Text('... ва яна ${items.length - 3} та',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        const SizedBox(height: 8),

        // Қабул вақти
        if (deliveryTime.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.3)),
            ),
            child: Text('🕐 Тахминий вақт: $deliveryTime',
                style: const TextStyle(fontSize: 12,
                    color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
          ),

        // Рад сабаби
        if (rejectReason.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: Text('❌ $rejectReason',
                style: const TextStyle(fontSize: 12,
                    color: Colors.red, fontWeight: FontWeight.w600)),
          ),

        Row(children: [
          Text(_fmtPrice(total),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          Text(' сўм', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ]),
      ]),
    );
  }

  Widget _statusChip(String status) {
    final map = {
      'new':       {'label': '🔵 Янги',        'color': Colors.blue},
      'accepted':  {'label': '🟡 Қабул',       'color': Colors.orange},
      'ready':     {'label': '🟠 Тайёр',       'color': Colors.deepOrange},
      'delivered': {'label': '🟢 Етказилди',   'color': Colors.green},
    };
    final info = map[status] ?? {'label': status, 'color': Colors.grey};
    final color = info['color'] as MaterialColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(info['label'] as String,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color.shade700)),
    );
  }

  String _monthName(int m) {
    const months = ['', 'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
    return months[m];
  }

  String _fmtPrice(int p) {
    final s = p.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  Widget _taxiChip(String value, String emoji, String label) {
    final sel = _taxiType == value;
    return GestureDetector(
      onTap: () => setState(() => _taxiType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? _blue.withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: sel ? _blue : Colors.grey.shade300,
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w600,
            color: sel ? _blue : Colors.black87,
          )),
          const Spacer(),
          if (sel) Icon(Icons.check_circle, color: _blue, size: 18),
        ]),
      ),
    );
  }

  String _taxiTypeLabel(String t) {
    switch (t) {
      case 'alone':     return '🚕 Маҳаллий такси';
      case 'marshrut':  return '🚐 Маршрут такси';
      case 'intercity': return '🚌 Шаҳарлараро такси';
      default: return '🚕 Маҳаллий такси';
    }
  }

  Widget _tripCard(Map<String, dynamic> trip) {
    final fare       = trip['fare'] as int;
    final from       = trip['from'] as String;
    final to         = trip['to']   as String;
    final taxiType   = trip['taxiType'] as String;
    final ts         = trip['completedAt'] as Timestamp?;
    final isDriver   = _role == 'driver';
    final personName = isDriver
        ? (trip['userPhone']  as String? ?? '')
        : (trip['driverName'] as String? ?? '');
    final carInfo    = isDriver ? '' : (trip['driverCar'] as String? ?? '');

    String dateStr = '';
    if (ts != null) {
      final d = ts.toDate();
      dateStr = '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
    }

    final emoji = taxiType == 'marshrut'  ? '🚐'
        : taxiType == 'intercity' ? '🚌' : '🚕';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6)],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 1-қатор: эмодзи + йўналиш + нарх
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                from.isEmpty ? 'Йўналиш' : '$from → $to',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              if (personName.isNotEmpty)
                Text(
                  isDriver ? '📞 $personName' : '🚗 $personName ${carInfo.isNotEmpty ? "· $carInfo" : ""}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          )),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${_fmtPrice(fare)} сўм',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDriver ? _green : _blue),
            ),
            if (dateStr.isNotEmpty)
              Text(dateStr, style: TextStyle(
                  fontSize: 10, color: Colors.grey.shade400)),
          ]),
        ]),
      ]),
    );
  }

  Widget _fieldRow({required IconData icon, required String label, required Widget child}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: _green, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        child,
      ])),
    ]);
  }

  Widget _editField(TextEditingController ctrl, String hint, TextInputType type,
      {List<TextInputFormatter>? formatters}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      inputFormatters: formatters,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _green)),
      ),
    );
  }

  Widget _genderChip(String value, String label) {
    final sel = _gender == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _gender = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            color: sel ? _green : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: sel ? _green : Colors.grey.shade300),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  color: sel ? Colors.white : Colors.black87,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
        ),
      ),
    );
  }

  Widget _roleChip(String value, String emoji, String label) {
    final sel = _role == value;
    return GestureDetector(
      onTap: () async {
        setState(() => _role = value);
        // Роль ўзгарганда автоматик сақлаш
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_role', value);
        // FCM listeners янгилаш
        try {
          FCMService().stopListeners();
          await FCMService().startListeners();
        } catch (_) {}
        // Мос экранга ўтиш
        if (!mounted) return;
        await Future.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;

      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? _green : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: sel ? _green : Colors.grey.shade300),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 5),
          Flexible(child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold,
                  color: sel ? Colors.white : Colors.black87))),
          if (sel) ...[
            const SizedBox(width: 4),
            const Icon(Icons.check, color: Colors.white, size: 14)],
        ]),
      ),
    );
  }
}