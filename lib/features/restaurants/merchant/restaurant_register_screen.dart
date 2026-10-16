// Рўйхатдан ўтиш (Б2.1, D-REST-7): форма → `restaurantRegister` → `applied`
// (админ тасдиғи) ёки `approved` (`settings/app.restaurantAutoApprove`).

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../data/restaurants_repository.dart';
import '../widgets/restaurant_checkout_sheet.dart' show restaurantsErrorText;
import 'restaurant_form_fields.dart';
import 'restaurant_panel_screen.dart';
import 'restaurant_register_form.dart';

class RestaurantRegisterScreen extends StatefulWidget {
  const RestaurantRegisterScreen({super.key, this.repository, this.homeCook = false});

  final RestaurantsRepository? repository;

  /// `true` — «Уй ошпази бўлиш»: `legalType` `individual` га қотирилади,
  /// танлов кўрсатилмайди. `false` — кафе-ресторан: фақат `yatt`/`llc`.
  final bool homeCook;

  @override
  State<RestaurantRegisterScreen> createState() => _RestaurantRegisterScreenState();
}

class _RestaurantRegisterScreenState extends State<RestaurantRegisterScreen> {
  late final RestaurantsRepository _repo = widget.repository ?? RestaurantsRepository();
  late final _data = RestaurantFormData(
    legalType: widget.homeCook ? RestaurantFormData.homeCookLegalType : RestaurantFormData.cafeLegalTypes.first,
  );
  bool _sending = false;
  bool _phoneLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  Future<void> _loadPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user_phone') ?? '';
      if (raw.isNotEmpty) _data.contactPhone = raw;
    } catch (_) {}
    if (mounted) setState(() => _phoneLoaded = true);
  }

  Future<void> _submit() async {
    final errs = _data.validate();
    if (errs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('restaurants_m_err_${errs.first}')), backgroundColor: Colors.red.shade700),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await _repo.register(_data.toRegisterPayload());
      if (!mounted) return;
      final rid = (res['restaurantId'] ?? '') as String;
      final status = (res['status'] ?? 'applied') as String;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr(status == 'approved' ? 'restaurants_m_submitted_approved' : 'restaurants_m_submitted_pending'))),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RestaurantPanelScreen(restaurantId: rid, repository: _repo)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(restaurantsErrorText(context, e)), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(context.tr(widget.homeCook ? 'home_create_home_cook' : 'restaurants_m_register_title'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
      ),
      body: !_phoneLoaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  RestaurantFormFields(
                    data: _data,
                    onChanged: () => setState(() {}),
                    showLegalType: !widget.homeCook,
                    legalTypeOptions: RestaurantFormData.cafeLegalTypes,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _sending ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.brand,
                      foregroundColor: c.brandInk,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(context.tr('restaurants_m_submit'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
    );
  }
}
