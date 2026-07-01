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
import '../../../services/agro_pickup_service.dart';
import 'milk_pickup_orders_screen.dart';

const _bg = Color(0xFFF8FAF5);
const _titleDark = Color(0xFF1A3A20);
const _accent = Color(0xFF4A6FA5);

/// Sut qabul — buyurtma formasi.
class MilkPickupScreen extends StatefulWidget {
  const MilkPickupScreen({super.key});

  @override
  State<MilkPickupScreen> createState() => _MilkPickupScreenState();
}

class _MilkPickupScreenState extends State<MilkPickupScreen> {
  final _addressCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _literCtrl = TextEditingController(text: '10');

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
    _literCtrl.dispose();
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

  double get _literCount {
    final raw = _literCtrl.text.trim().replaceAll(',', '.');
    final n = double.tryParse(raw) ?? 0;
    return n;
  }

  bool get _canSubmit {
    if (_loading || _submitting) return false;
    if (_phone.length < 9) return false;
    if (_addressCtrl.text.trim().length < 5) return false;
    return _literCount >= 1 && _literCount <= 500;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      final service = AgroPickupService();
      await service.placeMilkOrder(
        literCount: _literCount,
        pickupAddress: _addressCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
      );

      final dispatcherPhone =
          await context.read<SettingsRepository>().getDispatcherPhone();
      await callPhone(dispatcherPhone);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('milk_order_success'))),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MilkPickupOrdersScreen()),
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
        title: Text(context.tr('milk_title')),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: context.tr('milk_my_orders'),
            icon: const Icon(Icons.list_alt),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MilkPickupOrdersScreen(),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(child: Text(_loadError!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      context.tr('milk_form_hint'),
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _fieldLabel(context.tr('milk_liter_label')),
                    TextField(
                      controller: _literCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[\d.,]'),
                        ),
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixText: context.tr('milk_liter_suffix'),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),
                    _fieldLabel(context.tr('milk_address_label')),
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
                    _fieldLabel(context.tr('milk_phone_label')),
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
                    _fieldLabel(context.tr('milk_note_label')),
                    TextField(
                      controller: _noteCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        hintText: context.tr('milk_note_hint'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
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
                                context.tr('milk_submit'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.tr('milk_call_hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
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
