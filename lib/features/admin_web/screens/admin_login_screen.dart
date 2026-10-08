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
  final _pinCtrl = TextEditingController();
  // «Maxfiy kod bilan kirish» rejimi olib tashlandi (ega qarori 2026-10-08,
  // admin audit D-5): umumiy kod shaxsiy PIN'ni chetlab o'tardi; server
  // `adminWebSignInWithCode` endi har qanday kodni rad etadi.
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
    if (!mounted || auth.isLoggedIn) return;
    // Сессия йўқ — фақат телефонни олдиндан тўлдирамиз (PIN сақланмайди).
    final saved = await auth.savedPhone();
    if (mounted && saved != null && _phoneCtrl.text.isEmpty) {
      _phoneCtrl.text = saved;
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitPhone() async {
    setState(() => _error = null);
    final auth = context.read<AdminAuthService>();
    final err = await auth.signInWithPhonePin(_phoneCtrl.text, _pinCtrl.text);
    if (!mounted) return;
    if (err != null) {
      _pinCtrl.clear();
      setState(() => _error = err);
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
                    'Admin roli berilgan telefon va shaxsiy PIN. '
                    'PIN\'ni superadmin beradi.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 24),
                  ...[
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9 +\-()]'))
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Telefon raqam',
                        hintText: '+998 __ ___ __ __',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 12,
                      onSubmitted: (_) => _submitPhone(),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'PIN',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                        counterText: '',
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
                          : _submitPhone,
                      child: auth.isSendingOtp || auth.isVerifyingOtp
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Kirish'),
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
