import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_ad.dart';
import '../../../core/theme/app_theme.dart';
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
  final _textCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  late AdKind _kind = widget.presetKind ?? AdKind.ad;
  bool _isUrgent = false;
  bool _submitting = false;

  Color get _color {
    switch (_kind) {
      case AdKind.work:
        return const Color(0xFFD84315);
      case AdKind.service:
        return AppColors.primary;
      case AdKind.ad:
        return AppColors.primary;
      case AdKind.sell:
        return AppColors.primary;
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
      case AdKind.sell:
        return 'Масалан: Сут сотаман — 5 кг/кун, Гурлан';
    }
  }

  int get _visibleDays {
    if (_isUrgent && _kind.userCanMarkUrgent) {
      return AdKindX.urgentExpiryDays;
    }
    return _kind.expiresInDays;
  }

  @override
  void dispose() {
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
      priceText: _priceCtrl.text,
      isUrgent: _isUrgent && _kind.userCanMarkUrgent,
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

            if (widget.presetKind == null) ...[
              const Text('Тур:',
                  style: TextStyle(
                      fontSize: AppText.labelSmall,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: AdKindX.userPanelKinds.map((k) {
                    final sel = k == _kind;
                    final col = _kindColor(k);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _kind = k;
                          if (!k.userCanMarkUrgent) _isUrgent = false;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: sel ? col : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sel ? col : Colors.grey.shade200,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(k.emoji,
                                  style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 6),
                              Text(k.label,
                                  style: TextStyle(
                                    fontSize: AppText.labelTiny,
                                    fontWeight: FontWeight.bold,
                                    color: sel
                                        ? Colors.white
                                        : Colors.grey.shade700,
                                  )),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Text(_kind.emoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 8),
                    Text(
                      _kind.label,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppText.bodyLarge,
                        color: _color,
                      ),
                    ),
                  ],
                ),
              ),

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

            // Price (ихтиёрий).
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

            if (_kind.userCanMarkUrgent) ...[
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
                '$_visibleDays кун давомида кўринади • Кунига ${JobsController.dailyAdLimit} та эълон',
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
        return AppColors.primary;
      case AdKind.ad:
        return AppColors.primary;
      case AdKind.sell:
        return AppColors.primary;
    }
  }
}
