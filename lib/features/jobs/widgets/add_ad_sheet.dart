import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_ad.dart';
import '../../../utils/app_theme.dart';
import '../controllers/jobs_controller.dart';
import 'urgent_toggle.dart';

/// Янги эълон қўшиш bottom sheet — 3 турдан танлаш.
///
/// Хато йўли: турни танлашсиз эълон юбормайди. Ҳар бир тур ўз муддатига эга.
Future<void> showAddAdSheet({
  required BuildContext context,
  required JobsController controller,
  AdKind? presetKind,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
      child: ChangeNotifierProvider<JobsController>.value(
        value: controller,
        child: _AddAdView(presetKind: presetKind),
      ),
    ),
  );
}

class _AddAdView extends StatefulWidget {
  const _AddAdView({this.presetKind});

  final AdKind? presetKind;

  @override
  State<_AddAdView> createState() => _AddAdViewState();
}

class _AddAdViewState extends State<_AddAdView> {
  final _titleCtrl = TextEditingController();
  final _textCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  late AdKind _kind = widget.presetKind ?? AdKind.work;
  bool _isUrgent = false;
  bool _submitting = false;

  Color get _color {
    switch (_kind) {
      case AdKind.work:
        return const Color(0xFFD84315);
      case AdKind.service:
        return const Color(0xFF6A1B9A);
      case AdKind.ad:
        return const Color(0xFF0277BD);
    }
  }

  String get _hint {
    switch (_kind) {
      case AdKind.work:
        return 'Масалан: Шоли экишга 5-6 одам керак';
      case AdKind.service:
        return 'Масалан: Электрикман, бригадам бор';
      case AdKind.ad:
        return 'Масалан: Сотилади: Damas 2018, ҳолати яхши';
    }
  }

  String get _titleHint {
    switch (_kind) {
      case AdKind.work:
        return 'Иш номи (ихтиёрий)';
      case AdKind.service:
        return 'Хизмат номи (ихтиёрий)';
      case AdKind.ad:
        return 'Эълон сарлавҳаси (ихтиёрий)';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _textCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final c = context.read<JobsController>();
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await c.submitAd(
      type: _kind.key,
      text: _textCtrl.text,
      title: _titleCtrl.text,
      priceText: _priceCtrl.text,
      isUrgent: _isUrgent && _kind == AdKind.work,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!result.success) {
      messenger.showSnackBar(SnackBar(
        content: Text(result.error ?? 'Хатолик'),
        backgroundColor: result.error?.startsWith('⚠️') == true
            ? Colors.orange
            : Colors.red,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: const Text('✅ Эълон текширувга юборилди'),
      backgroundColor: _color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<JobsController>();
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 14),

            // Kind chooser.
            const Text('Тур:',
                style: TextStyle(
                    fontSize: AppText.labelSmall, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(children: AdKind.values.map((k) {
              final sel = k == _kind;
              final col = _kindColor(k);
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _kind = k),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: sel ? col : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: sel ? col : Colors.grey.shade200),
                      ),
                      child: Column(children: [
                        Text(k.emoji,
                            style: const TextStyle(fontSize: 18)),
                        const SizedBox(height: 2),
                        Text(k.label,
                            style: TextStyle(
                                fontSize: AppText.labelTiny,
                                fontWeight: FontWeight.bold,
                                color: sel
                                    ? Colors.white
                                    : Colors.grey.shade700)),
                      ]),
                    ),
                  ),
                ),
              );
            }).toList()),
            const SizedBox(height: 14),

            // Title (ихтиёрий).
            TextField(
              controller: _titleCtrl,
              maxLength: 80,
              decoration: InputDecoration(
                hintText: _titleHint,
                hintStyle: TextStyle(
                    color: Colors.grey.shade400, fontSize: AppText.bodyMedium),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _color, width: 1.5)),
                filled: true,
                fillColor: Colors.grey.shade50,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),

            // Body text.
            TextField(
              controller: _textCtrl,
              maxLines: 4,
              maxLength: 300,
              decoration: InputDecoration(
                hintText: _hint,
                hintStyle: TextStyle(
                    color: Colors.grey.shade400, fontSize: AppText.bodyMedium),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _color, width: 1.5)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),

            // Price (ихтиёрий — ad учун муҳим).
            if (_kind != AdKind.work) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _priceCtrl,
                maxLength: 40,
                decoration: InputDecoration(
                  hintText: _kind == AdKind.ad
                      ? '💰 Нарх (масалан: 200 000 сўм)'
                      : '💰 Нарх / шартнома',
                  hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: AppText.bodyMedium),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _color, width: 1.5)),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  counterText: '',
                ),
              ),
            ],

            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _color.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _color.withOpacity(0.2)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📌 Профилдан автоматик:',
                        style: TextStyle(
                            fontSize: AppText.labelSmall,
                            fontWeight: FontWeight.w600,
                            color: _color)),
                    const SizedBox(height: 4),
                    Text('📞 ${c.userPhone}',
                        style:
                            const TextStyle(fontSize: AppText.bodySmall)),
                    if (c.userAddress.isNotEmpty)
                      Text('📍 ${c.userAddress}',
                          style:
                              const TextStyle(fontSize: AppText.bodySmall)),
                  ]),
            ),

            if (_kind == AdKind.work) ...[
              const SizedBox(height: 10),
              UrgentToggle(
                isUrgent: _isUrgent,
                onTap: () => setState(() => _isUrgent = !_isUrgent),
              ),
            ],

            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, size: 18),
              label: Text(
                _submitting ? 'Юборилмоқда...' : 'ЭЪЛОН ҚЎШИШ',
                style: const TextStyle(
                    fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                '${_kind.expiresInDays} кун давомида кўринади • Кунига 5 та эълон',
                style: TextStyle(
                    fontSize: AppText.labelTiny, color: Colors.grey.shade400),
              ),
            ),
          ]),
    );
  }

  Color _kindColor(AdKind k) {
    switch (k) {
      case AdKind.work:
        return const Color(0xFFD84315);
      case AdKind.service:
        return const Color(0xFF6A1B9A);
      case AdKind.ad:
        return const Color(0xFF0277BD);
    }
  }
}
