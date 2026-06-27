import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/courier_order.dart';
import '../../../models/user_address.dart';
import '../../../models/user_model.dart';
import '../../../repositories/courier_orders_repository.dart';
import '../../../repositories/settings_repository.dart';
import '../../../repositories/user_repository.dart';

const _bg = Color(0xFFF6FAF2);
const _cardBorder = AppColors.cardBorderMuted;
const _sectionLabel = AppColors.sectionMuted;
const _titleDark = Color(0xFF1A3A20);
const _primaryGreen = AppColors.courierGreen;

/// Mijoz kuryer buyurtmasi — tavsif + yetkazish ma'lumotlari.
class CourierOrderScreen extends StatefulWidget {
  const CourierOrderScreen({super.key});

  @override
  State<CourierOrderScreen> createState() => _CourierOrderScreenState();
}

class _CourierOrderScreenState extends State<CourierOrderScreen> {
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  int _deliveryFee = SettingsRepository.defaultCourierDeliveryFee;
  String _phone = '';
  String _name = '';
  UserAddress _address = const UserAddress();
  String _addressDisplay = '';
  bool _hasAddress = false;
  bool _addressMissing = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _descCtrl.addListener(() => setState(() {}));
    _loadData();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final settingsRepo = context.read<SettingsRepository>();
    final userRepo = context.read<UserRepository>();

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = phoneDigits(
        prefs.getString('user_phone') ?? '',
      );
      final name = (prefs.getString('user_name') ??
              prefs.getString('userName') ??
              '')
          .trim();

      final fee = await settingsRepo.getCourierDeliveryFee();
      UserModel? user;
      if (phone.length >= 9) {
        user = await userRepo.getById(phone);
      }

      final address = user?.address ?? const UserAddress();
      final display = user != null
          ? user.addressDisplay.trim()
          : '';
      final hasAddress = address.hasManualAddress && display.isNotEmpty;

      if (!mounted) return;
      setState(() {
        _phone = phone;
        _name = name.isNotEmpty ? name : (user?.name.trim() ?? '');
        _deliveryFee = fee;
        _address = address;
        _addressDisplay =
            display.isNotEmpty ? display : address.formatted.trim();
        _hasAddress = hasAddress;
        _addressMissing = !hasAddress;
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  bool get _canSubmit {
    if (_loading || _submitting) return false;
    if (_phone.length < 9) return false;
    if (!_hasAddress) return false;
    return _descCtrl.text.trim().length >= 10;
  }

  bool get _descTooShort {
    final len = _descCtrl.text.trim().length;
    return len > 0 && len < 10;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() => _submitting = true);
    try {
      final repo = context.read<CourierOrdersRepository>();
      await repo.create(
        CourierOrder(
          id: '',
          customerPhone: _phone,
          customerName: _name,
          deliveryAddress: _addressDisplay,
          deliveryLat: _address.lat,
          deliveryLng: _address.lng,
          description: _descCtrl.text.trim(),
          estimatedPrice:
              int.tryParse(_priceCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ??
                  0,
          deliveryFee: _deliveryFee,
          totalPrice: 0,
          status: CourierOrderStatus.pending,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('courier_order_success'))),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _titleDark,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.tr('currency_sum');

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _titleDark,
        elevation: 0,
        title: Text(
          context.tr('courier_order_screen_title'),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: _titleDark,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _primaryGreen))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionCard(
                    title: context.tr('courier_order_info_card'),
                    children: [
                      TextField(
                        controller: _descCtrl,
                        maxLines: 4,
                        maxLength: 200,
                        decoration: InputDecoration(
                          labelText: context.tr('courier_order_desc_label'),
                          hintText: context.tr('courier_order_desc_hint'),
                          errorText: _descTooShort
                              ? context.tr('courier_order_desc_min_error')
                              : null,
                          border: const OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _priceCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          labelText: context.tr('courier_order_price_label'),
                          hintText: context.tr('courier_order_price_label'),
                          border: const OutlineInputBorder(),
                          suffixText: currency,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: context.tr('courier_order_delivery_card'),
                    children: [
                      Text(
                        context.tr('courier_order_delivery_address'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: _sectionLabel,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _addressDisplay.isNotEmpty ? _addressDisplay : '—',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _titleDark,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            context.tr('courier_order_delivery_fee_label'),
                            style: const TextStyle(
                              fontSize: 13,
                              color: _sectionLabel,
                            ),
                          ),
                          Text(
                            '${formatPrice(_deliveryFee)} $currency',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _primaryGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_addressMissing || _loadError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline,
                              size: 18, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _loadError ??
                                  context.tr('courier_order_no_address'),
                              style: TextStyle(
                                color: Colors.red.shade800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _primaryGreen,
                      disabledBackgroundColor: _cardBorder,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            context.tr('courier_order_submit'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
