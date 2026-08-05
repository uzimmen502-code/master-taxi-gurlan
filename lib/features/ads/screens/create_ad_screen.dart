import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../onboarding/screens/phone_reverify_screen.dart';
import '../repositories/ads_repository.dart';
import '../services/ads_storage_service.dart';

/// Онлайн бозорга янги эълон жойлаш — профессионал форма.
class CreateAdScreen extends StatefulWidget {
  const CreateAdScreen({super.key});

  @override
  State<CreateAdScreen> createState() => _CreateAdScreenState();
}

class _CreateAdScreenState extends State<CreateAdScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  final List<XFile> _newImages = [];
  bool _loading = false;
  bool _checkedLimit = false;

  static const _ink = Color(0xFF102418);
  static const _muted = Color(0xFF4A6740);
  static const _fieldFill = Color(0xFFFFFFFF);
  static const _chipBg = Color(0xFF1B3D12);
  static const _chipFg = Color(0xFFD9FF3F);
  static const _pageBg = Color(0xFFF3F8E8);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLimit());
  }

  Future<void> _checkLimit() async {
    final uid = await _ownerId();
    if (!mounted) return;
    if (uid.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final can = await context.read<AdsRepository>().canCreateAd(uid);
    if (!mounted) return;
    if (!can) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.tr('create_ad_limit_title')),
          content: Text(context.tr('create_ad_limit_body')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.tr('ok')),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() => _checkedLimit = true);
  }

  Future<String> _ownerId() async {
    final prefs = await SharedPreferences.getInstance();
    return canonicalPhoneId(prefs.getString('user_phone') ?? '');
  }

  String _sellerName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Сотувчи';
    final name = user.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) return email;
    return 'Сотувчи';
  }

  Future<void> _pickImages() async {
    if (_newImages.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('create_ad_images_max'))),
      );
      return;
    }
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 85,
      limit: 5 - _newImages.length,
    );
    if (picked.isEmpty) return;
    setState(() {
      _newImages.addAll(picked);
      if (_newImages.length > 5) {
        _newImages.removeRange(5, _newImages.length);
      }
    });
  }

  String _cfError(Object e) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'unauthenticated':
          return context.tr('create_ad_err_auth');
        case 'resource-exhausted':
          return e.message ?? context.tr('create_ad_err_limit');
        case 'invalid-argument':
          return e.message ?? context.tr('create_ad_err_invalid');
        case 'permission-denied':
          return context.tr('create_ad_err_permission');
        default:
          return e.message ?? context.tr('create_ad_err_generic').replaceAll('{code}', e.code);
      }
    }
    return context.tr('create_ad_err_generic').replaceAll('{code}', '$e');
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('create_ad_images_required')),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('create_ad_err_session')),
          backgroundColor: AppColors.error,
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PhoneReverifyScreen()),
        (_) => false,
      );
      return;
    }

    final ownerId = await _ownerId();
    if (phoneDigits(ownerId).length < 9) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('create_ad_err_phone'))),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _loading = true);
    final limitFullMsg = context.tr('create_ad_err_limit_full');
    try {
      final repo = context.read<AdsRepository>();
      final storage = context.read<AdsStorageService>();
      if (!await repo.canCreateAd(ownerId)) {
        throw StateError(limitFullMsg);
      }
      final urls = await storage.uploadImages(
        ownerId: ownerId,
        images: _newImages,
      );
      await repo.createAd(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        price: int.parse(_priceCtrl.text.trim()),
        sellerName: _sellerName(),
        imageUrls: urls,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('create_ad_success'))),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_cfError(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
    Widget? prefix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefix,
      filled: true,
      fillColor: _fieldFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: const TextStyle(
        color: _muted,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      hintStyle: TextStyle(
        color: _muted.withValues(alpha: 0.55),
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFC8E09A)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFC8E09A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.limeDeep, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedLimit) {
      return const Scaffold(
        backgroundColor: _pageBg,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.limeDeep),
        ),
      );
    }

    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _chipBg,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('create_ad_title'),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: Colors.white,
              ),
            ),
            Text(
              context.tr('home_seller_cta_badge'),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: _chipFg,
              ),
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                children: [
                  _IntroCard(
                    title: context.tr('create_ad_intro_title'),
                    body: context.tr('create_ad_intro_body'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('create_ad_photos_label'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('create_ad_photos_hint'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _PhotoPickerRow(
                    images: _newImages,
                    loading: _loading,
                    onAdd: _pickImages,
                    onRemove: (i) => setState(() => _newImages.removeAt(i)),
                    addLabel: context.tr('create_ad_add_photo'),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _titleCtrl,
                    maxLength: 120,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _ink,
                      fontSize: 15,
                    ),
                    decoration: _fieldDecoration(
                      label: context.tr('create_ad_name_label'),
                      hint: context.tr('create_ad_name_hint'),
                      prefix: const Icon(Icons.sell_outlined, color: AppColors.limeDeep),
                    ),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.length < 3) {
                        return context.tr('create_ad_name_short');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      fontSize: 16,
                    ),
                    decoration: _fieldDecoration(
                      label: context.tr('create_ad_price_label'),
                      hint: context.tr('create_ad_price_hint'),
                      prefix: const Icon(
                        Icons.payments_outlined,
                        color: AppColors.limeDeep,
                      ),
                    ).copyWith(
                      suffixText: context.tr('currency_sum'),
                      suffixStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _muted,
                        fontSize: 13,
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return context.tr('create_ad_price_required');
                      }
                      final n = int.tryParse(v.trim());
                      if (n == null) return context.tr('create_ad_price_digits');
                      if (n < 1) return context.tr('create_ad_price_positive');
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 5,
                    maxLength: 2000,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: _ink,
                      fontSize: 14,
                      height: 1.35,
                    ),
                    decoration: _fieldDecoration(
                      label: context.tr('create_ad_desc_label'),
                      hint: context.tr('create_ad_desc_hint'),
                    ),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.length < 3) {
                        return context.tr('create_ad_desc_short');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F2D0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFC8E09A)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.phone_in_talk_outlined,
                          size: 20,
                          color: AppColors.limeDeep,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            context.tr('create_ad_phone_note'),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: _muted,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomPad),
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
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.limeDeep,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.limeDeep.withValues(alpha: 0.45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          context.tr('create_ad_submit'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B3D12), Color(0xFF2E5C1E)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFD9FF3F).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Color(0xFFD9FF3F),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFD9FF3F),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.88),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPickerRow extends StatelessWidget {
  const _PhotoPickerRow({
    required this.images,
    required this.loading,
    required this.onAdd,
    required this.onRemove,
    required this.addLabel,
  });

  final List<XFile> images;
  final bool loading;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...List.generate(images.length, (i) {
            final f = images[i];
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: 108,
                      height: 108,
                      color: const Color(0xFFE8F2D0),
                      child: kIsWeb
                          ? Image.network(
                              f.path,
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              File(f.path),
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  if (i == 0)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B3D12).withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          context.tr('create_ad_cover_badge'),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD9FF3F),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Material(
                      color: const Color(0xFF1B3D12),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: loading ? null : () => onRemove(i),
                        child: const SizedBox(
                          width: 26,
                          height: 26,
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (images.length < 5)
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: loading ? null : onAdd,
                borderRadius: BorderRadius.circular(14),
                child: Ink(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF8BC34A),
                      width: 1.4,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F2D0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.add_a_photo_outlined,
                          color: AppColors.limeDeep,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        addLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF102418),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
