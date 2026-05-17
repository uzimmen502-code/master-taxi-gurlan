import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/admin_auth_service.dart';

/// Админ web панели — логин экрани.
///
/// Phone + PIN билaн логин. Тaсдиқлaнгaндaн кейин `AdminShell`'гa йoнaлaди.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  static const _blue = Color(0xFF0D47A1);
  static const _green = Color(0xFF1B5E20);

  /// Релиз APK файл номи. Янгилaш керак бўлгaндa — шу йерда ҳaм.
  static const _driverApkPath = '/downloads/master-taxi-gurlan-driver.apk';
  static const _driverApkVersion = 'v1.0';

  final _phoneCtrl = TextEditingController(text: '+998');
  final _pinCtrl = TextEditingController();
  final _phoneFocus = FocusNode();
  final _pinFocus = FocusNode();

  bool _busy = false;
  String? _err;
  bool _obscurePin = true;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _phoneFocus.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _downloadDriverApk() async {
    final uri = Uri.parse(_driverApkPath);
    try {
      await launchUrl(uri, webOnlyWindowName: '_self');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('APK юклаб бўлмади: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    final result = await context.read<AdminAuthService>().signIn(
          rawPhone: _phoneCtrl.text,
          pin: _pinCtrl.text,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width > 720;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _logo(),
              const SizedBox(height: 20),
              _driverDownloadCard(),
              const SizedBox(height: 14),
              Container(
                padding: EdgeInsets.all(isWide ? 36 : 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Админ панелигa кириш',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                    'Илoвaдa Админ rolени активлaштириб бўлгaн рaқaм билaн киринг.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _phoneCtrl,
                    focusNode: _phoneFocus,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[+\d ]')),
                      LengthLimitingTextInputFormatter(20),
                    ],
                    onSubmitted: (_) => _pinFocus.requestFocus(),
                    decoration: InputDecoration(
                      labelText: 'Телефон рaқaми',
                      hintText: '+998 90 123 45 67',
                      prefixIcon: const Icon(Icons.phone, color: _blue),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _blue, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _pinCtrl,
                    focusNode: _pinFocus,
                    keyboardType: TextInputType.number,
                    obscureText: _obscurePin,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    onSubmitted: (_) => _busy ? null : _submit(),
                    style: const TextStyle(letterSpacing: 4, fontSize: 18),
                    decoration: InputDecoration(
                      labelText: 'PIN-код',
                      prefixIcon: const Icon(Icons.lock_outline, color: _blue),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePin
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () =>
                            setState(() => _obscurePin = !_obscurePin),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _blue, width: 2),
                      ),
                    ),
                  ),
                  if (_err != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_err!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13)),
                        ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _submit,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.login, size: 20),
                      label: Text(_busy ? 'Текширилмoқда...' : 'Кириш',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline,
                          color: Colors.blue.shade800, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Аввал mobil ilovada: Profil → '
                          '«🔒 Админ ролини faollashtirish» (PIN 2024).',
                          style: TextStyle(
                              fontSize: 11, color: Colors.blue.shade800),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Text(
                '© Master Taxi Gurlan — Admin Panel v1.0',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _logo() {
    return Column(children: [
      Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: _blue,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: _blue.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 4)),
          ],
        ),
        child: const Icon(Icons.admin_panel_settings,
            color: Colors.white, size: 42),
      ),
      const SizedBox(height: 12),
      const Text('Master Taxi Gurlan',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      Text('Админ панели',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
    ]);
  }

  /// Маҳаллий такси ҳaйдовчилaри иловaси — APK юклaб oлиш карточкaси.
  ///
  /// Ҳайдовчилaр Google Play'дa жойлaштирилмaгaн (хусусий иловa) — шу сабaбли
  /// веб сайтдан APK юклaб oлинaди. Фaйл `web/downloads/`'дa жойлaшгaн.
  Widget _driverDownloadCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_green, Color(0xFF2E7D32)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: _green.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.local_taxi,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Маҳаллий такси ҳайдовчилари иловаси',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  'Android учун APK — Google Play\'дa йўқ',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: _downloadDriverApk,
            icon: const Icon(Icons.download_rounded, size: 20),
            label: const Text('APK юклаб олиш',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.info_outline,
              size: 13, color: Colors.white.withOpacity(0.8)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Версия $_driverApkVersion · Android 7.0+ · 130 МБ. Юклагандан кейин '
              'телефон созламаларида "Номаълум манбалардан ўрнатиш"га рухсат '
              'беринг.',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 10.5,
                  height: 1.4),
            ),
          ),
        ]),
      ]),
    );
  }
}
