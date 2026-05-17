import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../models/news_item.dart';
import '../../../repositories/news_repository.dart';
import '../../../services/admin_service.dart';

/// Админ учун — янги хабар яратиш (admin_news collection).
///
/// Категория, аудитория, муҳимлик даражасини танлаб юборилади. Барча
/// фойдаланувчилар Profile → Янгилик ва хабарлар бўлимида кўрадилар.
class AdminNewsComposeScreen extends StatefulWidget {
  const AdminNewsComposeScreen({super.key});

  @override
  State<AdminNewsComposeScreen> createState() => _AdminNewsComposeScreenState();
}

class _AdminNewsComposeScreenState extends State<AdminNewsComposeScreen> {
  static const _blue = Color(0xFF1565C0);

  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _ctaLabelCtrl = TextEditingController();
  final _ctaUrlCtrl = TextEditingController();

  String _category = 'info';
  String _audience = 'all';
  int _priority = 0;
  bool _sending = false;
  bool _adminChecked = false;
  bool _isAdmin = false;
  String? _err;

  /// Title/body uchun maxLength — Firestore document size limit (≈1 MB) va
  /// UI o'qиш qulayligi uchun.
  static const _maxTitle = 120;
  static const _maxBody = 2000;
  static const _maxCtaLabel = 40;
  static const _maxCtaUrl = 500;

  static const _categories = [
    ('info', 'Маълумот', Icons.info, Colors.green),
    ('update', 'Янгиланиш', Icons.system_update_alt, Colors.blue),
    ('promo', 'Акция', Icons.local_offer, Colors.purple),
    ('warning', 'Огоҳлантириш', Icons.warning_amber, Colors.orange),
    ('emergency', 'Шошилинч', Icons.report, Colors.red),
  ];

  static const _audiences = [
    ('all', 'Барча', Icons.public),
    ('user', 'Фойдаланувчилар', Icons.person),
    ('driver', 'Ҳайдовчилар', Icons.directions_car),
    ('courier', 'Курьерлар', Icons.delivery_dining),
  ];

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _ctaLabelCtrl.dispose();
    _ctaUrlCtrl.dispose();
    super.dispose();
  }

  /// Server-side admin check. Foydaланувчи admin emas — экранни ёпaмиз.
  Future<void> _checkAdmin() async {
    bool ok = false;
    try {
      ok = await context.read<AdminService>().isCurrentUserAdmin();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _isAdmin = ok;
      _adminChecked = true;
    });
    if (!ok) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('⛔ Сизда хабар юбориш ҳуқуқи йўқ'),
          ),
        );
        Navigator.of(context).pop();
      });
    }
  }

  /// CTA URL валидaциясi: бо'ш бўлса OK, акс ҳолда https/http schemе керaк.
  String? _validateCtaUrl(String url) {
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return 'URL "https://" ёки "http://" билан бошлансин';
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return 'Фақат https:// ёки http:// URL қабул қилинади';
    }
    if (uri.host.isEmpty) {
      return 'URL хост (domен) ҳам бўлиши керак';
    }
    return null;
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    final ctaLabel = _ctaLabelCtrl.text.trim();
    final ctaUrl = _ctaUrlCtrl.text.trim();

    if (title.isEmpty || body.isEmpty) {
      setState(() => _err = 'Сарлавҳа ва матн мажбурий');
      return;
    }
    if (title.length > _maxTitle) {
      setState(() => _err = 'Сарлавҳа $_maxTitle белгидан ошмаслиги керак');
      return;
    }
    if (body.length > _maxBody) {
      setState(() => _err = 'Матн $_maxBody белгидан ошмаслиги керак');
      return;
    }
    // CTA — иккаласи бо'ш ёки иккаласи тўлдирилгaн бўлсин.
    if ((ctaLabel.isEmpty) != (ctaUrl.isEmpty)) {
      setState(() => _err = 'CTA тугмa учун ҳам **матн**, ҳам **URL** тўлдиринг');
      return;
    }
    final urlErr = _validateCtaUrl(ctaUrl);
    if (urlErr != null) {
      setState(() => _err = urlErr);
      return;
    }

    setState(() {
      _sending = true;
      _err = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<NewsRepository>().create(NewsItem(
            id: '',
            title: title,
            body: body,
            category: _category,
            audience: _audience,
            priority: _priority,
            ctaLabel: ctaLabel,
            ctaUrl: ctaUrl,
            createdAt: DateTime.now(),
          ));
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        content: Text('✅ Хабар юборилди'),
        backgroundColor: Colors.green,
      ));
      Navigator.pop(context);
    } catch (e) {
      setState(() => _err = 'Хатолик: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_adminChecked || !_isAdmin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text('Янги хабар'),
        backgroundColor: _blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _sectionLabel('Категория'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((c) {
              final selected = _category == c.$1;
              return GestureDetector(
                onTap: () => setState(() => _category = c.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? c.$4 : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: selected ? c.$4 : Colors.grey.shade300),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(c.$3,
                        size: 14,
                        color: selected ? Colors.white : Colors.grey.shade700),
                    const SizedBox(width: 6),
                    Text(c.$2,
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                selected ? Colors.white : Colors.grey.shade700,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal)),
                  ]),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          _sectionLabel('Аудитория'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _audiences.map((a) {
              final selected = _audience == a.$1;
              return GestureDetector(
                onTap: () => setState(() => _audience = a.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? _blue : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: selected ? _blue : Colors.grey.shade300),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(a.$3,
                        size: 14,
                        color: selected ? Colors.white : Colors.grey.shade700),
                    const SizedBox(width: 6),
                    Text(a.$2,
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                selected ? Colors.white : Colors.grey.shade700,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal)),
                  ]),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          _sectionLabel('Муҳимлик даражаси (0–10)'),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Slider(
                value: _priority.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                label: '$_priority',
                activeColor: _blue,
                onChanged: (v) => setState(() => _priority = v.round()),
              ),
            ),
            SizedBox(
              width: 32,
              child: Text('$_priority',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 8),
          _sectionLabel('Сарлавҳа *'),
          const SizedBox(height: 6),
          TextField(
            controller: _titleCtrl,
            maxLength: _maxTitle,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_maxTitle),
            ],
            decoration: _inputDeco('Қисқа ва аниқ'),
          ),
          const SizedBox(height: 4),
          _sectionLabel('Матн *'),
          const SizedBox(height: 6),
          TextField(
            controller: _bodyCtrl,
            maxLines: 6,
            maxLength: _maxBody,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_maxBody),
            ],
            decoration: _inputDeco('Тўлиқ маълумот'),
          ),
          const SizedBox(height: 4),
          _sectionLabel('CTA — ҳаракат тугмаси (ихтиёрий)'),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctaLabelCtrl,
                maxLength: _maxCtaLabel,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(_maxCtaLabel),
                ],
                decoration: _inputDeco('Тугма матни'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _ctaUrlCtrl,
                maxLength: _maxCtaUrl,
                keyboardType: TextInputType.url,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(_maxCtaUrl),
                ],
                decoration: _inputDeco('https://...'),
              ),
            ),
          ]),
          if (_err != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(_err!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, size: 18),
              label: const Text('Хабарни юбориш'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String s) => Text(s,
      style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade700));

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _blue, width: 1.5)),
      );
}
