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
  final _codeCtrl = TextEditingController();
  bool _codeMode = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitCode() async {
    setState(() => _error = null);
    final auth = context.read<AdminAuthService>();
    final result = await auth.signInWithCode(_codeCtrl.text);
    if (!mounted) return;
    if (result != null) {
      setState(() => _error = result);
    }
  }

  Future<void> _submitPhone() async {
    setState(() => _error = null);
    final auth = context.read<AdminAuthService>();
    final sent = await auth.sendOtp(_phoneCtrl.text);
    if (!mounted) return;
    if (!sent) {
      setState(() => _error = auth.otpError ?? 'Kirishda xatolik');
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
                    _codeMode
                        ? 'Maxfiy kirish kodini kiriting (telefon shart emas)'
                        : 'Admin roli berilgan telefonni kiriting — '
                            'SMS va parol shart emas',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 24),
                  if (_codeMode)
                    TextField(
                      controller: _codeCtrl,
                      obscureText: true,
                      autofocus: true,
                      onSubmitted: (_) => _submitCode(),
                      decoration: const InputDecoration(
                        labelText: 'Kirish kodi',
                        prefixIcon: Icon(Icons.key),
                        border: OutlineInputBorder(),
                      ),
                    )
                  else
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      onSubmitted: (_) => _submitPhone(),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9 +\-()]'))
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Telefon raqam',
                        hintText: '+998 91 277 87 77',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                      ),
                    ),
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
                          : (_codeMode ? _submitCode : _submitPhone),
                      child: auth.isSendingOtp || auth.isVerifyingOtp
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Kirish'),
                    ),
                  ),
                  if (!_codeMode)
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _codeMode = true;
                        _error = null;
                      }),
                      icon: const Icon(Icons.key, size: 18),
                      label: const Text('Maxfiy kod bilan kirish'),
                    ),
                  if (_codeMode)
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _codeMode = false;
                        _codeCtrl.clear();
                        _error = null;
                      }),
                      icon: const Icon(Icons.phone, size: 18),
                      label: const Text('Telefon bilan kirish'),
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
