import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/phone_launcher.dart';
import '../../../models/user_address.dart';
import '../../../models/user_model.dart';
import '../../../repositories/settings_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/carpet_wash_service.dart';
import 'carpet_wash_orders_screen.dart';

const _bg = Color(0xFFF6FAF2);
const _titleDark = Color(0xFF1A3A20);
const _accent = Color(0xFF6D4C41);

/// Gilam yuvish — sodda buyurtma formasi.
class CarpetWashScreen extends StatefulWidget {
  const CarpetWashScreen({super.key});

  @override
  State<CarpetWashScreen> createState() => _CarpetWashScreenState();
}

class _CarpetWashScreenState extends State<CarpetWashScreen> {
  final _addressCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _countCtrl = TextEditingController(text: '1');

  bool _loading = true;
  bool _submitting = false;
  String _phone = '';
  String _name = '';
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _noteCtrl.dispose();
    _countCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = phoneDigits(prefs.getString('user_phone') ?? '');
      final name = (prefs.getString('user_name') ?? '').trim();
      UserModel? user;
      if (phone.length >= 9) {
        user = await context.read<UserRepository>().getById(phone);
      }
      final address = user?.address ?? const UserAddress();
      final display = user?.addressDisplay.trim() ?? '';
      if (!mounted) return;
      setState(() {
        _phone = phone;
        _name = name.isNotEmpty ? name : (user?.name.trim() ?? '');
        _addressCtrl.text =
            display.isNotEmpty ? display : address.formatted.trim();
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  int get _carpetCount {
    final n = int.tryParse(_countCtrl.text.trim()) ?? 0;
    return n.clamp(1, 20);
  }

  bool get _canSubmit {
    if (_loading || _submitting) return false;
    if (_phone.length < 9) return false;
    if (_addressCtrl.text.trim().length < 5) return false;
    return _carpetCount >= 1;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      final service = CarpetWashService();
      await service.placeOrder(
        carpetCount: _carpetCount,
        pickupAddress: _addressCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
      );

      final dispatcherPhone =
          await context.read<SettingsRepository>().getDispatcherPhone();
      await callPhone(dispatcherPhone);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('carpet_order_success'))),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CarpetWashOrdersScreen()),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(context.tr('carpet_wash_title')),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: context.tr('carpet_my_orders'),
            icon: const Icon(Icons.list_alt),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CarpetWashOrdersScreen(),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Text(_loadError!))
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(
                            context.tr('carpet_form_hint'),
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _fieldLabel(context.tr('carpet_count_label')),
                          TextField(
                            controller: _countCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(2),
                            ],
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              suffixText: context.tr('carpet_count_suffix'),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                          _fieldLabel(context.tr('carpet_address_label')),
                          TextField(
                            controller: _addressCtrl,
                            maxLines: 2,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                          _fieldLabel(context.tr('carpet_phone_label')),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              _phone,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          if (_name.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              _name,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          _fieldLabel(context.tr('carpet_note_label')),
                          TextField(
                            controller: _noteCtrl,
                            maxLines: 3,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              hintText: context.tr('carpet_note_hint'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        10,
                        16,
                        10 + MediaQuery.paddingOf(context).bottom,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, -3),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _canSubmit ? _submit : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _submitting
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      context.tr('carpet_submit'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.tr('carpet_call_hint'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: _titleDark,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}
