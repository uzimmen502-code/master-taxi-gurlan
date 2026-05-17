import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/user_address.dart';
import '../../../repositories/user_repository.dart';
import '../../home/screens/home_screen.dart';
import '../../../services/location_service.dart';
import '../controllers/onboarding_controller.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<OnboardingController>(
      create: (ctx) => OnboardingController(
        userRepo: ctx.read<UserRepository>(),
        locationService: ctx.read<LocationService>(),
      ),
      child: const _OnboardingView(),
    );
  }
}

class _OnboardingView extends StatefulWidget {
  const _OnboardingView();

  @override
  State<_OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<_OnboardingView> {
  static const _green1 = Color(0xFF1B5E20);
  static const _green2 = Color(0xFF2E7D32);
  static const _green3 = Color(0xFF43A047);

  final _pageController = PageController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _birthDateCtrl = TextEditingController();

  // Manzil maydonlari — onboarding'ning 4-sahifasida shu yerda to'liq
  // to'ldiriladi. Profilga keyin qaytib to'ldirish KERAK EMAS.
  final _mfyCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _houseCtrl = TextEditingController();
  final _districtCtrl = TextEditingController(text: 'Гурлан');
  final _noteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _phoneCtrl.text = '+998 ';
    _phoneCtrl.addListener(_enforcePhonePrefix);

    // Controller'dagi maydonlarni text controller'lar bilan ikki tomonlama
    // sinxronlash.
    _mfyCtrl.addListener(
        () => context.read<OnboardingController>().setMfy(_mfyCtrl.text));
    _streetCtrl.addListener(
        () => context.read<OnboardingController>().setStreet(_streetCtrl.text));
    _houseCtrl.addListener(
        () => context.read<OnboardingController>().setHouse(_houseCtrl.text));
    _districtCtrl.addListener(() =>
        context.read<OnboardingController>().setDistrict(_districtCtrl.text));
    _noteCtrl.addListener(
        () => context.read<OnboardingController>().setNote(_noteCtrl.text));
  }

  void _enforcePhonePrefix() {
    if (!_phoneCtrl.text.startsWith('+998 ')) {
      _phoneCtrl.text = '+998 ';
      _phoneCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _phoneCtrl.text.length));
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _birthDateCtrl.dispose();
    _mfyCtrl.dispose();
    _streetCtrl.dispose();
    _houseCtrl.dispose();
    _districtCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _next() async {
    final c = context.read<OnboardingController>();

    // Sahifa 2 — telefon + OTP
    if (c.currentPage == 1) {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser != null && !c.otpInputVisible) {
        c.advance();
        await _pageController.nextPage(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut);
        return;
      }
      if (!c.otpInputVisible) {
        final d = phoneDigits(_phoneCtrl.text);
        if (d.length < 12) {
          _showError('Телефон рақамини тўлиқ киритинг');
          return;
        }
        await c.sendOtp(_phoneCtrl.text);
        return;
      } else {
        final code = _otpCtrl.text.trim();
        if (code.length < 6) {
          _showError('6 raqamli kodni kiriting');
          return;
        }
        final ok = await c.verifyOtp(code);
        if (!ok || !mounted) return;
        _otpCtrl.clear();
        c.advance();
        await _pageController.nextPage(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut);
        return;
      }
    }

    final err = c.validate(name: _nameCtrl.text, phone: _phoneCtrl.text);
    if (err != null) {
      _showError(err);
      return;
    }
    c.advance();
    await _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut);
  }

  void _prev() {
    final c = context.read<OnboardingController>();
    c.back();
    _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut);
  }

  Future<void> _fetchGps() async {
    final c = context.read<OnboardingController>();
    final ok = await c.fetchGps();
    if (!mounted) return;
    if (!ok) {
      final err = c.consumeError();
      if (err != null) _showError(err);
      return;
    }
    // GPS auto-prefill — controller `street`ни оғизсиз ёзган бўлса, шу ердан
    // `_streetCtrl`га ҳам кўчирамиз (listener'lar бир-бирини overwrite этмасин
    // деб `text` бевосита set qilинади).
    if (_streetCtrl.text.isEmpty && c.street.isNotEmpty) {
      _streetCtrl.text = c.street;
    }
  }

  String _formatBirthDate(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  DateTime? _parseBirthDate(String value) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (m == null) return null;
    final y = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final d = int.tryParse(m.group(3)!);
    if (y == null || mo == null || d == null) return null;
    try {
      final parsed = DateTime(y, mo, d);
      if (parsed.year != y || parsed.month != mo || parsed.day != d) {
        return null;
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickBirthDate() async {
    final c = context.read<OnboardingController>();
    final now = DateTime.now();
    final initial = _parseBirthDate(c.birthDate) ?? DateTime(now.year - 25);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'Туғилган кунингизни танланг',
      cancelText: 'Бекор',
      confirmText: 'Танлаш',
    );
    if (picked == null) return;
    final formatted = _formatBirthDate(picked);
    _birthDateCtrl.text = formatted;
    c.setBirthDate(formatted);
  }

  Future<void> _finish() async {
    final c = context.read<OnboardingController>();
    final ok = await c.finish(
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
    );
    final err = c.consumeError();
    if (err != null && mounted) {
      _showError(err);
    }
    if (!ok || !mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<OnboardingController>();

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
            _progressBar(c.currentPage),
            const SizedBox(height: 8),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: c.goToPage,
                children: [
                  _page1(loc),
                  _page2(loc),
                  _page3(loc, c),
                  _pageBirthDate(c),
                  _pageAddress(c),
                ],
              ),
            ),
            _footerButtons(c, loc),
          ]),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // PROGRESS + FOOTER
  // ────────────────────────────────────────────────────────────────────
  Widget _progressBar(int currentPage) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: Row(
        children: List.generate(
          OnboardingController.totalPages,
          (i) => Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 4,
              decoration: BoxDecoration(
                color: i <= currentPage
                    ? Colors.white
                    : Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footerButtons(OnboardingController c, AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Row(children: [
        if (c.currentPage > 0)
          GestureDetector(
            onTap: _prev,
            child: Container(
              width: 50,
              height: 50,
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
              onPressed: c.isSubmitting || c.isVerifyingCode || c.isSendingCode
                  ? null
                  : (c.isLastPage ? _finish : _next),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _green2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: c.isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.green))
                  : Text(
                      c.isLastPage
                          ? loc.translate('start')
                          : loc.translate('continue'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ),
      ]),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // PAGES
  // ────────────────────────────────────────────────────────────────────
  Widget _page1(AppLocalizations loc) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('👋', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(loc.translate('onboarding_welcome'),
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 6),
            Text(loc.translate('onboarding_name'),
                style: TextStyle(
                    fontSize: 14, color: Colors.white.withOpacity(0.8))),
            const SizedBox(height: 28),
            _field(
              controller: _nameCtrl,
              hint: loc.translate('enter_name'),
              icon: Icons.person_outline,
              inputType: TextInputType.name,
            ),
            const SizedBox(height: 28),
            _duaBox(loc.translate('allah_protect')),
          ],
        ),
      );

  Widget _page2(AppLocalizations loc) {
    final c = context.watch<OnboardingController>();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📱', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            c.otpInputVisible ? 'SMS kodni kiriting' : loc.translate('onboarding_phone'),
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            c.otpInputVisible
                ? 'Telefoningizga SMS yuborildi. 6 raqamli kodni kiriting.'
                : 'Raqamingizga SMS kod yuboriladi.',
            style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8)),
          ),
          const SizedBox(height: 28),
          if (!c.otpInputVisible) ...[
            _field(
              controller: _phoneCtrl,
              hint: loc.translate('enter_phone'),
              icon: Icons.phone_outlined,
              inputType: TextInputType.phone,
              formatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d\+\s]')),
              ],
            ),
          ] else ...[
            _field(
              controller: _otpCtrl,
              hint: '6 raqamli kod',
              icon: Icons.lock_outline,
              inputType: TextInputType.number,
              formatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: c.isSendingCode
                      ? null
                      : () => c.resendOtp(_phoneCtrl.text),
                  icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                  label: const Text('Qayta yuborish',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ),
                TextButton.icon(
                  onPressed: () {
                    _otpCtrl.clear();
                    c.resetPhoneAuth();
                  },
                  icon: const Icon(Icons.edit, size: 16, color: Colors.white70),
                  label: const Text("Raqamni o'zgartirish",
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ),
              ],
            ),
          ],
          if (c.phoneAuthError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withOpacity(0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(c.phoneAuthError!,
                      style: const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ]),
            ),
          ],
          if (c.isSendingCode) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          ],
        ],
      ),
    );
  }

  Widget _page3(AppLocalizations loc, OnboardingController c) =>
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🙍', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(loc.translate('onboarding_gender'),
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 6),
            Text(loc.translate('onboarding_gender_sub'),
                style: TextStyle(
                    fontSize: 14, color: Colors.white.withOpacity(0.8))),
            const SizedBox(height: 28),
            Row(children: [
              Expanded(child: _genderCard(c, 'male', '👨', 'Эркак')),
              const SizedBox(width: 14),
              Expanded(child: _genderCard(c, 'female', '👩', 'Аёл')),
            ]),
          ],
        ),
      );

  Widget _pageBirthDate(OnboardingController c) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🎂', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('Туғилган кунингиз',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 6),
            Text(
              'Туғилган кунингизда бонус ва махсус табрик олиш учун санани тўғри киритинг. '
              'Бу маълумот кейинчалик ўзгартириш учун админ тасдиғини талаб қилиши мумкин.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Colors.white.withValues(alpha: 0.86),
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _pickBirthDate,
              child: AbsorbPointer(
                child: _field(
                  controller: _birthDateCtrl,
                  hint: 'YYYY-MM-DD (ихтиёрий)',
                  icon: Icons.cake_outlined,
                  inputType: TextInputType.datetime,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _pickBirthDate,
              icon: const Icon(Icons.calendar_month, color: Colors.white),
              label: const Text(
                'Календардан танлаш',
                style: TextStyle(color: Colors.white),
              ),
            ),
            if (c.birthDate.isEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Ҳозир киритмасангиз, кейин профилдан киритишингиз мумкин.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
            ],
          ],
        ),
      );

  /// **Manzil sahifasi** — onboarding'ning ГСП + qo'lda to'lдiriladigan toliq
  /// shakli. AddressEditScreen bilan bir xil maydonlar — buyurtmalardan keyin
  /// qayta to'ldirish KERAK EMAS.
  Widget _pageAddress(OnboardingController c) {
    final gpsRequired = c.isGpsRequiredForPhone(_phoneCtrl.text);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('📍', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          const Text('Манзилингизни киритинг',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 4),
          Text(
            gpsRequired
                ? 'GPS ва қўлда тўлдириш — иккаласи мажбурий'
                : 'Қўлда манзил тўлдириш мажбурий (GPS ихтиёрий)',
            style:
                TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.85)),
          ),
          const SizedBox(height: 14),

          // GPS блоки.
          if (gpsRequired) ...[
            _gpsCard(c),
            const SizedBox(height: 12),
          ],

          // Қўлдa тўлдириш — МФЙ, кўча, уй.
          _manualCard(),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // GPS CARD
  // ────────────────────────────────────────────────────────────────────
  Widget _gpsCard(OnboardingController c) {
    final hasGps = c.hasGps;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasGps
              ? _green2.withOpacity(0.4)
              : Colors.orange.shade300,
          width: 1.2,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.gps_fixed, color: _green2, size: 18),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('GPS координаталари (мажбурий)',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          _gpsStatusBadge(c),
        ]),
        const SizedBox(height: 8),
        if (hasGps) ...[
          Row(children: [
            const Icon(Icons.place, size: 14, color: _green2),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${c.lat!.toStringAsFixed(5)}, ${c.lng!.toStringAsFixed(5)}',
                style: const TextStyle(
                    fontSize: 12, color: _green2, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          if (c.accuracy != null) ...[
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.adjust, size: 11, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                'Аниқлик: ±${c.accuracy!.toStringAsFixed(0)} м',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ]),
          ],
          const SizedBox(height: 8),
        ] else
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '⚠️ GPS ҳали олинмаган. Қуйидаги тугмани босинг.',
              style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFFE65100),
                  fontWeight: FontWeight.w500),
            ),
          ),
        SizedBox(
          width: double.infinity,
          height: 38,
          child: ElevatedButton.icon(
            onPressed: c.isGpsLoading ? null : _fetchGps,
            icon: c.isGpsLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(hasGps ? Icons.refresh : Icons.my_location, size: 16),
            label: Text(hasGps ? 'GPS-ни янгилаш' : 'Жорий GPS манзилни олиш',
                style: const TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green2,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _gpsStatusBadge(OnboardingController c) {
    final addr = UserAddress(lat: c.lat, lng: c.lng, accuracy: c.accuracy);
    final q = addr.gpsQuality;
    final (label, bg, fg) = switch (q) {
      GpsQuality.high => ('Аъло', Colors.green.shade50, _green2),
      GpsQuality.medium =>
        ('Ўрта', Colors.amber.shade50, const Color(0xFFE65100)),
      GpsQuality.low => ('Паст', Colors.red.shade50, Colors.red.shade700),
      GpsQuality.unknown => ('OK', Colors.blue.shade50, Colors.blue.shade700),
      GpsQuality.none => ('Йўқ', Colors.grey.shade100, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: fg.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // MANUAL CARD (МФЙ, кўча, уй, туман, изоҳ)
  // ────────────────────────────────────────────────────────────────────
  Widget _manualCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.edit_location_alt, color: _green2, size: 18),
          SizedBox(width: 6),
          Text('Қўлда тўлдириш (мажбурий)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 10),
        _manualField(
          ctrl: _mfyCtrl,
          label: 'МФЙ *',
          icon: Icons.location_city,
          hint: 'Масалан: «Бахт» МФЙ',
        ),
        const SizedBox(height: 10),
        _manualField(
          ctrl: _streetCtrl,
          label: 'Кўча / гузар *',
          icon: Icons.signpost,
          hint: 'Кўча / гузар номи',
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: _manualField(
              ctrl: _houseCtrl,
              label: 'Уй № *',
              icon: Icons.home,
              hint: '12',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _manualField(
              ctrl: _districtCtrl,
              label: 'Туман',
              icon: Icons.map,
              hint: 'Гурлан',
            ),
          ),
        ]),
        const SizedBox(height: 10),
        _manualField(
          ctrl: _noteCtrl,
          label: 'Қўшимча (ихтиёрий)',
          icon: Icons.notes,
          hint: 'Подъезд, қават, ориентир...',
          maxLines: 2,
        ),
      ]),
    );
  }

  Widget _manualField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    String hint = '',
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
        prefixIcon: Icon(icon, size: 16, color: _green2),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _green2, width: 1.5)),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────
  // SMALL WIDGETS
  // ────────────────────────────────────────────────────────────────────
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
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontStyle: FontStyle.italic)),
          ),
        ]),
      );

  Widget _genderCard(
      OnboardingController c, String value, String emoji, String label) {
    final sel = c.gender == value;
    return GestureDetector(
      onTap: () => c.setGender(value),
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
          Text(label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
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
