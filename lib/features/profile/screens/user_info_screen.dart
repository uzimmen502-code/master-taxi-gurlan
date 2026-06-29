import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/user_address.dart';
import '../controllers/profile_controller.dart';
import '../widgets/language_settings_tile.dart';
import 'address_edit_screen.dart';
import '../../../core/theme/app_theme.dart';

/// Р¤РѕР№РґР°Р»Р°РЅСѓРІС‡Рё РјР°СЉР»СѓРјРѕС‚Р»Р°СЂРё вЂ” РёСЃРј/Р¶РёРЅСЃ/СЂРѕР»СЊ/РјР°РЅР·РёР».
///
/// Profile СЌРєСЂР°РЅРёРґР°РЅ "Р¤РѕР№РґР°Р»Р°РЅСѓРІС‡Рё РјР°СЉР»СѓРјРѕС‚Р»Р°СЂРё" РєР°СЂС‚Р°СЃРё РѕСЂТ›Р°Р»Рё РѕС‡РёР»Р°РґРё.
/// Р­СЃРєРё ProfileScreen'РЅРёРЅРі info section'Рё Р±Сѓ Р№РµСЂРіР° РєСћС‡РёСЂРёР»РґРё.
class UserInfoScreen extends StatefulWidget {
  const UserInfoScreen({super.key});

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  static const _green = AppColors.primaryDark;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _birthDateCtrl = TextEditingController();

  bool _primed = false;
  bool _editing = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _birthDateCtrl.dispose();
    super.dispose();
  }

  void _prime(ProfileController c) {
    if (_primed) return;
    _nameCtrl.text = c.name;
    _phoneCtrl.text = c.phone;
    _birthDateCtrl.text = c.birthDate;
    _primed = true;
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

  Future<void> _pickBirthDate(ProfileController c) async {
    final loc = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final initial = _parseBirthDate(c.birthDate) ?? DateTime(now.year - 25);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: loc.translate('profile_birth_date_picker_help'),
      cancelText: loc.translate('cancel'),
      confirmText: loc.translate('profile_birth_date_picker_confirm'),
    );
    if (picked == null || !mounted) return;

    final formatted = _formatBirthDate(picked);
    final ok = await c.saveBirthDateOrRequest(formatted);
    if (!mounted) return;
    if (ok && c.birthDate == formatted) {
      _birthDateCtrl.text = formatted;
    }
    final err = c.consumeError();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red),
      );
      return;
    }
    final msg = c.consumeSuccess();
    if (msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.button),
      );
    }
  }

  Future<void> _save() async {
    final c = context.read<ProfileController>();
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await c.save(
      newName: _nameCtrl.text,
      newPhone: _phoneCtrl.text,
      newAddress: c.address,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _editing = false;
    });
    if (ok) {
      _phoneCtrl.text = c.phone;
      final loc = AppLocalizations.of(context)!;
      messenger.showSnackBar(SnackBar(
        content: Text(loc.translate('saved')),
        backgroundColor: AppColors.button,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final c = context.watch<ProfileController>();
    _prime(c);

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(
          loc.translate('profile_user_info_title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        titleSpacing: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              tooltip: loc.translate('save'),
              onPressed: () => setState(() => _editing = true),
            )
          else ...[
            // Edit СЂРµР¶РёРјРёРґР° РёРєРєРёС‚Р° С‚РµРєСЃС‚Р»Рё С‚СѓРіРјР° вЂ” СЌРєСЂР°РЅРґР° С‚РѕСЂ Р±СћР»РёР± Т›РѕР»РјР°СЃРёРЅ
            // РґРµР± РёРєРѕРЅРєР°Р»aС€С‚РёСЂРёР»РґРё (Р±СѓС‚СѓРЅ Р¶РѕР№ СЌРіaР»Р»aРјaР№РґРё).
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              tooltip: loc.translate('cancel'),
              onPressed: () {
                _nameCtrl.text = c.name;
                _phoneCtrl.text = c.phone;
                setState(() => _editing = false);
              },
            ),
            IconButton(
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check, color: Colors.white),
              tooltip: loc.translate('save'),
              onPressed: _saving ? null : _save,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Column(children: [
            _row(
              icon: Icons.person_outline,
              label: loc.translate('name'),
              child: _editing
                  ? _input(_nameCtrl, loc.translate('enter_name'),
                      TextInputType.name)
                  : Text(c.name.isEmpty ? 'вЂ”' : c.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
            ),
            const Divider(height: 24),
            _row(
              icon: Icons.phone_outlined,
              label: loc.translate('phone'),
              child: _editing
                  ? _input(
                      _phoneCtrl,
                      loc.translate('enter_phone'),
                      TextInputType.phone,
                      formatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d\+\s]')),
                      ],
                    )
                  : Text(c.phone.isEmpty ? 'вЂ”' : c.phone,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
            ),
            const Divider(height: 24),
            _row(
              icon: Icons.person,
              label: loc.translate('gender'),
              child: _editing
                  ? Row(children: [
                      _genderChip(c, 'male', loc.translate('male')),
                      const SizedBox(width: 8),
                      _genderChip(c, 'female', loc.translate('female')),
                    ])
                  : Text(
                      c.gender == 'female'
                          ? loc.translate('female')
                          : loc.translate('male'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
            ),
            const Divider(height: 24),
            _row(
              icon: Icons.cake_outlined,
              label: loc.translate('profile_birth_date_label'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.birthDate.isEmpty
                        ? loc.translate('profile_not_entered')
                        : c.birthDate,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: c.birthDate.isEmpty
                          ? Colors.orange.shade700
                          : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    loc.translate('profile_birth_date_hint'),
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: c.isSaving ? null : () => _pickBirthDate(c),
                    icon: const Icon(Icons.calendar_month, size: 16),
                    label: Text(
                      c.birthDate.isEmpty
                          ? loc.translate('profile_birth_date_add')
                          : loc.translate('profile_birth_date_change_request'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            const LanguageSettingsTile(),
            const Divider(height: 24),
            _row(
              icon: Icons.badge_outlined,
              label: loc.translate('role'),
              child: Text(_roleLabel(context, c.role, loc),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500)),
            ),
            const Divider(height: 24),
            _row(
              icon: Icons.location_on_outlined,
              label: loc.translate('profile_home_address_label'),
              child: InkWell(
                onTap: () async {
                  final result = await Navigator.push<UserAddress>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddressEditScreen(
                        initial: c.structuredAddress,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  if (result != null) {
                    c.applyAddress(result);
                  } else {
                    await c.reloadAddressFromPrefs();
                  }
                },
                child: Row(children: [
                  Expanded(
                    child: Text(
                      c.addressDisplay.isEmpty
                          ? loc.translate('profile_address_tap_to_fill')
                          : c.addressDisplay,
                      style: TextStyle(
                        fontSize: 14,
                        color: c.addressDisplay.isEmpty
                            ? Colors.orange.shade700
                            : Colors.black87,
                        fontStyle: c.addressDisplay.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ),
                  const Icon(Icons.edit_location_alt,
                      color: _green, size: 18),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(
      {required IconData icon,
      required String label,
      required Widget child}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: _green, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            child,
          ],
        ),
      ),
    ]);
  }

  Widget _input(
      TextEditingController ctrl, String hint, TextInputType type,
      {List<TextInputFormatter>? formatters}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      inputFormatters: formatters,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _green)),
      ),
    );
  }

  Widget _genderChip(ProfileController c, String value, String label) {
    final sel = c.gender == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => c.setGender(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          decoration: BoxDecoration(
            color: sel ? _green : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? _green : Colors.grey.shade300),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  color: sel ? Colors.white : Colors.black87,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
        ),
      ),
    );
  }

  String _roleLabel(BuildContext context, String role, AppLocalizations loc) {
    switch (role) {
      case 'superadmin':
        return AppLocalizations.tr(context, 'role_superadmin');
      case 'dispatcher':
        return AppLocalizations.tr(context, 'role_dispatcher');
      case 'support':
        return AppLocalizations.tr(context, 'role_support');
      case 'accountant':
        return AppLocalizations.tr(context, 'role_accountant');
      case 'moderator':
        return AppLocalizations.tr(context, 'role_moderator');
      case 'admin':
        return AppLocalizations.tr(context, 'admin_role');
      case 'driver':
        return loc.translate('driver_role');
      case 'courier':
        return AppLocalizations.tr(context, 'courier_role');
      default:
        return loc.translate('user_role');
    }
  }
}
