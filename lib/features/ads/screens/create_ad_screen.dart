import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../onboarding/screens/phone_reverify_screen.dart';
import '../models/ad_model.dart';
import '../repositories/ads_repository.dart';
import '../services/ads_storage_service.dart';

/// Form to publish a new cheap product ad.
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
  final _phoneCtrl = TextEditingController();

  final List<XFile> _newImages = [];
  bool _loading = false;
  bool _checkedLimit = false;

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
          title: const Text('Чеклов'),
          content: const Text(
            'Фаол эълонлар сони 50 тадан ошмаслиги керак. '
            'Аввал бирор эълонни яширинг ёки ўчиринг.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() => _checkedLimit = true);
    final prefs = await SharedPreferences.getInstance();
    final phone = phoneDigits(prefs.getString('user_phone') ?? '');
    if (phone.length >= 9 && _phoneCtrl.text.isEmpty) {
      _phoneCtrl.text = phone;
    }
  }

  Future<String> _ownerId() async {
    final prefs = await SharedPreferences.getInstance();
    return phoneDigits(prefs.getString('user_phone') ?? '');
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
        const SnackBar(content: Text('Энг кўпи 5 та расм')),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_newImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Расм жойлаштириш тавсия қилинади'),
        ),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сессия тугади. Телефонни қайта тасдиқланг'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PhoneReverifyScreen()),
        (_) => false,
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userPhone = prefs.getString('user_phone') ?? '';
    final ownerId = canonicalPhoneId(userPhone);
    if (phoneDigits(ownerId).length < 9) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Аввал телефонни тасдиқланг')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final repo = context.read<AdsRepository>();
      final storage = context.read<AdsStorageService>();
      if (!await repo.canCreateAd(ownerId)) {
        throw StateError('Фаол эълонлар лимити тўлди');
      }
      final urls = await storage.uploadImages(
        ownerId: ownerId,
        images: _newImages,
      );
      final title = _titleCtrl.text.trim();
      final ad = AdModel(
        id: '',
        ownerId: ownerId,
        title: title,
        titleLower: title.toLowerCase(),
        description: _descCtrl.text.trim(),
        price: int.parse(_priceCtrl.text.trim()),
        phone: _phoneCtrl.text.trim(),
        sellerName: _sellerName(),
        imageUrls: urls,
        status: 'pending',
        views: 0,
      );
      await repo.createAd(ad);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Эълон модерацияга юборилди. Тасдиқлангач бозорда кўринади',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Хатолик: $e'),
            backgroundColor: Colors.red,
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
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedLimit) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Янги эълон'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...List.generate(_newImages.length, (i) {
                  final f = _newImages[i];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: kIsWeb
                            ? Image.network(
                                f.path,
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                              )
                            : Image.file(
                                File(f.path),
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                              ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _loading
                              ? null
                              : () => setState(() => _newImages.removeAt(i)),
                        ),
                      ),
                    ],
                  );
                }),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pickImages,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Расм (1–5)'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Номи *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Номини киритинг' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Нархи (so\'m) *'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Нархни киритинг';
                if (int.tryParse(v.trim()) == null) return 'Фақат рақам';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Тавсиф *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Тавсифни киритинг' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Телефон *'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Телефонни киритинг';
                if (phoneDigits(v).length < 9) return 'Телефон нотўғри';
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Жойлаштириш'),
            ),
          ],
        ),
      ),
    );
  }
}
