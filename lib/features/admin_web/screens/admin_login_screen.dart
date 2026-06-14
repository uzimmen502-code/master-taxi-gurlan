import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../services/admin_auth_service.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _showOtp = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _phoneCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoLogin());
  }

  Future<void> _tryAutoLogin() async {
    final auth = context.read<AdminAuthService>();
    if (auth.isLoggedIn) return;
    await auth.restoreSession();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  bool get _isTrustedPhone =>
      AdminAuthService.isTrustedAdminPhone(_phoneCtrl.text);

  Future<void> _submitPhone() async {
    setState(() => _error = null);
    final auth = context.read<AdminAuthService>();
    final sent = await auth.sendOtp(_phoneCtrl.text);
    if (!mounted) return;
    if (!sent) {
      setState(() => _error = auth.otpError ?? 'Kirishda xatolik');
      return;
    }
    if (_isTrustedPhone) {
      return;
    }
    setState(() {
      _showOtp = true;
      _error = null;
    });
  }

  Future<void> _verifyOtp() async {
    setState(() => _error = null);
    final auth = context.read<AdminAuthService>();
    final result = await auth.verifyOtpAndSignIn(
      _phoneCtrl.text,
      _otpCtrl.text,
    );
    if (!mounted) return;
    if (result != null) {
      setState(() => _error = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AdminAuthService>();
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('🔐 Admin Panel',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    _showOtp
                        ? '${_phoneCtrl.text} raqamiga SMS yuborildi'
                        : _isTrustedPhone
                            ? 'Telefon raqamingizni kiriting va «Kirish»ni bosing (SMS yo\'q)'
                            : 'Admin roli berilgan telefon raqam bilan kiring',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    enabled: !_showOtp,
                    inputFormatters: [FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9 +\-()]'))],
                    decoration: const InputDecoration(
                      labelText: 'Telefon raqam',
                      hintText: '+998 91 277 87 77',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_showOtp) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _otpCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      autofocus: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8),
                      decoration: const InputDecoration(
                        hintText: '------',
                        counterText: '',
                        border: OutlineInputBorder(),
                        labelText: 'SMS kod',
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(_error!,
                          style: TextStyle(color: Colors.red.shade700)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: auth.isSendingOtp || auth.isVerifyingOtp
                          ? null
                          : (_showOtp ? _verifyOtp : _submitPhone),
                      child: auth.isSendingOtp || auth.isVerifyingOtp
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(_showOtp
                              ? 'Tasdiqlash'
                              : (_isTrustedPhone ? 'Kirish' : 'SMS yuborish')),
                    ),
                  ),
                  if (_showOtp) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: auth.isSendingOtp
                          ? null
                          : () {
                              _otpCtrl.clear();
                              _submitPhone();
                            },
                      child: const Text('SMS-ni qayta yuborish'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _showOtp = false;
                        _otpCtrl.clear();
                        _error = null;
                      }),
                      child: const Text('Telefonni o\'zgartirish'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
