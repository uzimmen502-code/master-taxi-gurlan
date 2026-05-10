import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../l10n/app_localizations.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _gender = 'male';

  bool _isLoading    = false;
  bool _isGpsLoading = false;

  static const _totalPages = 4;
  static const _green1 = Color(0xFF1B5E20);
  static const _green2 = Color(0xFF2E7D32);
  static const _green3 = Color(0xFF43A047);

  @override
  void initState() {
    super.initState();
    _phoneCtrl.text = '+998 ';
    _phoneCtrl.addListener(() {
      if (!_phoneCtrl.text.startsWith('+998 ')) {
        _phoneCtrl.text = '+998 ';
        _phoneCtrl.selection = TextSelection.fromPosition(
            TextPosition(offset: _phoneCtrl.text.length));
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage == 0 && _nameCtrl.text.trim().isEmpty) {
      _error('Исмингизни киритинг'); return;
    }
    if (_currentPage == 1) {
      final d = _phoneCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
      if (d.length < 12) { _error('Телефон рақамини тўлиқ киритинг'); return; }
    }
    if (_currentPage == 3 && _addressCtrl.text.trim().isEmpty) {
      _error('Манзилингизни киритинг'); return;
    }
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut);
    }
  }

  void _prev() {
    if (_currentPage > 0) {
      _pageController.previousPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut);
    }
  }

  Future<void> _getAddressFromGps() async {
    setState(() => _isGpsLoading = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied)
        perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _error('GPS рухсати берилмади');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8));
      final places = await placemarkFromCoordinates(
          pos.latitude, pos.longitude);
      if (places.isNotEmpty) {
        final p = places.first;
        final addr = [p.street, p.subLocality, p.locality]
            .where((s) => s != null && s!.isNotEmpty)
            .join(', ');
        _addressCtrl.text = addr.isNotEmpty ? addr : 'Гурлан, Хоразм';
      }
    } catch (_) {
      _addressCtrl.text = 'Гурлан, Хоразм';
    } finally {
      if (mounted) setState(() => _isGpsLoading = false);
    }
  }

  Future<void> _finish() async {
    if (_addressCtrl.text.trim().isEmpty) {
      _error('Манзилингизни киритинг'); return;
    }
    setState(() => _isLoading = true);
    final phone = _phoneCtrl.text.replaceAll(RegExp(r'[^\d]'), '');

    await FirebaseFirestore.instance
        .collection('users').doc(phone).set({
      'phone':     _phoneCtrl.text.trim(),
      'name':      _nameCtrl.text.trim(),
      'gender':    _gender,
      'address':   _addressCtrl.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId',    phone);
    await prefs.setString('userName',  _nameCtrl.text.trim());
    await prefs.setString('user_name',    _nameCtrl.text.trim());
    await prefs.setString('user_phone',   _phoneCtrl.text.trim());
    await prefs.setString('user_gender',  _gender);
    await prefs.setString('user_address', _addressCtrl.text.trim());
    await prefs.setBool('onboarding_done', true);

    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  void _error(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  bool get _isLastPage => _currentPage == _totalPages - 1;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_green1, _green2, _green3],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            // Progress bar
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: Row(
                children: List.generate(_totalPages, (i) => Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= _currentPage
                          ? Colors.white
                          : Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                )),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  _page1(loc),
                  _page2(loc),
                  _page3(loc),
                  _pageAddress(loc),
                ],
              ),
            ),
            // Tugmalar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(children: [
                if (_currentPage > 0)
                  GestureDetector(
                    onTap: _prev,
                    child: Container(
                      width: 50, height: 50,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : (_isLastPage ? _finish : _next),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _green2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _isLoading
                          ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.green))
                          : Text(
                        _isLastPage
                            ? loc.translate('start')
                            : loc.translate('continue'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Саҳифалар ──

  Widget _page1(AppLocalizations loc) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('👋', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 12),
      Text(loc.translate('onboarding_welcome'),
          style: const TextStyle(fontSize: 26,
              fontWeight: FontWeight.bold, color: Colors.white)),
      const SizedBox(height: 6),
      Text(loc.translate('onboarding_name'),
          style: TextStyle(fontSize: 14,
              color: Colors.white.withOpacity(0.8))),
      const SizedBox(height: 28),
      _field(controller: _nameCtrl,
          hint: loc.translate('enter_name'),
          icon: Icons.person_outline,
          inputType: TextInputType.name),
      const SizedBox(height: 28),
      _duaBox(loc.translate('allah_protect')),
    ]),
  );

  Widget _page2(AppLocalizations loc) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('📱', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 12),
      Text(loc.translate('onboarding_phone'),
          style: const TextStyle(fontSize: 26,
              fontWeight: FontWeight.bold, color: Colors.white)),
      const SizedBox(height: 6),
      Text(loc.translate('onboarding_phone_sub'),
          style: TextStyle(fontSize: 14,
              color: Colors.white.withOpacity(0.8))),
      const SizedBox(height: 28),
      _field(
        controller: _phoneCtrl,
        hint: loc.translate('enter_phone'),
        icon: Icons.phone_outlined,
        inputType: TextInputType.phone,
        formatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d\+\s]'))
        ],
      ),
    ]),
  );

  Widget _page3(AppLocalizations loc) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('🙍', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 12),
      Text(loc.translate('onboarding_gender'),
          style: const TextStyle(fontSize: 26,
              fontWeight: FontWeight.bold, color: Colors.white)),
      const SizedBox(height: 6),
      Text(loc.translate('onboarding_gender_sub'),
          style: TextStyle(fontSize: 14,
              color: Colors.white.withOpacity(0.8))),
      const SizedBox(height: 28),
      Row(children: [
        Expanded(child: _genderCard('male',   '👨', 'Эркак')),
        const SizedBox(width: 14),
        Expanded(child: _genderCard('female', '👩', 'Аёл')),
      ]),
    ]),
  );

  Widget _pageAddress(AppLocalizations loc) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('📍', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 12),
      const Text('Манзилингизни киритинг',
          style: TextStyle(fontSize: 22,
              fontWeight: FontWeight.bold, color: Colors.white)),
      const SizedBox(height: 6),
      Text('Буюртма ва хизматлар учун манзилингиз сақланади',
          style: TextStyle(fontSize: 13,
              color: Colors.white.withOpacity(0.7))),
      const SizedBox(height: 24),
      // GPS tugmasi
      GestureDetector(
        onTap: _getAddressFromGps,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: Row(children: [
            _isGpsLoading
                ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.gps_fixed,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            const Text('GPS орқали аниқлаш',
                style: TextStyle(fontSize: 14,
                    color: Colors.white, fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white54, size: 14),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _addressCtrl,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Масалан: Гурлан, Ёрқишлоқ МФЙ, 12-уй',
          hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.5), fontSize: 13),
          prefixIcon: Icon(Icons.location_on,
              color: Colors.white.withOpacity(0.7), size: 18),
          filled: true,
          fillColor: Colors.white.withOpacity(0.15),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: Colors.white, width: 1.5)),
        ),
      ),
      const SizedBox(height: 10),
      Text('Кейинчалик профилдан ўзгартириш мумкин',
          style: TextStyle(fontSize: 11,
              color: Colors.white.withOpacity(0.5))),
    ]),
  );

  // ── Ёрдамчи виджетлар ──

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required TextInputType inputType,
    List<TextInputFormatter>? formatters,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: TextField(
        controller: controller,
        keyboardType: inputType,
        inputFormatters: formatters,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(icon, color: _green2),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _duaBox(String text) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(children: [
      const Text('🤲', style: TextStyle(fontSize: 18)),
      const SizedBox(width: 10),
      Expanded(child: Text(text,
          style: const TextStyle(fontSize: 13,
              color: Colors.white, fontStyle: FontStyle.italic))),
    ]),
  );

  Widget _genderCard(String value, String emoji, String label) {
    final sel = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: sel ? Colors.white : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: sel ? Colors.white : Colors.transparent, width: 2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 38)),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.bold,
            color: sel ? _green2 : Colors.white,
          )),
          if (sel) ...[
            const SizedBox(height: 4),
            const Icon(Icons.check_circle, color: _green2, size: 18),
          ],
        ]),
      ),
    );
  }
}