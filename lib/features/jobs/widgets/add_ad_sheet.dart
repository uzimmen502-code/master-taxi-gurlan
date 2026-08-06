import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_ad.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/jobs_controller.dart';
import '../jobs_colors.dart';
import 'urgent_toggle.dart';

/// Янги эълон қўшиш bottom sheet — тур танлаш.
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

  Color get _color => JobsColors.accentFor(_kind);

  String get _hint {
    switch (_kind) {
      case AdKind.work:
        return 'Масалан: Шоли экишга 5-6 одам керак';
      case AdKind.service:
        return 'Масалан: Электрикман, бригадам бор';
      case AdKind.ad:
        return 'Масалан: Ҳайдовчи керак — Гурлан–Урганч';
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
            ? Colors.orange.shade800
            : JobsColors.urgent,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      return;
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: const Text('Эълон текширувга юборилди'),
      backgroundColor: _color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: JobsColors.surface,
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
                      color: JobsColors.border,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 14),

            if (widget.presetKind == null) ...[
              const Text('Тур:',
                  style: TextStyle(
                      fontSize: AppText.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: JobsColors.ink)),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: AdKindX.userPanelKinds.map((k) {
                    final sel = k == _kind;
                    final col = JobsColors.accentFor(k);
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
                            color: sel ? col : JobsColors.fieldFill,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sel ? col : JobsColors.border,
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
                                        ? JobsColors.onBar
                                        : JobsColors.muted,
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
              style: const TextStyle(color: JobsColors.ink),
              decoration: InputDecoration(
                hintText: _hint,
                hintStyle: const TextStyle(
                    color: JobsColors.hint, fontSize: AppText.bodyMedium),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JobsColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JobsColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _color, width: 1.5)),
                filled: true,
                fillColor: JobsColors.fieldFill,
              ),
            ),

            const SizedBox(height: 8),
            TextField(
              controller: _priceCtrl,
              maxLength: 40,
              style: const TextStyle(color: JobsColors.ink),
              decoration: InputDecoration(
                hintText: _kind == AdKind.ad
                    ? 'Нарх (масалан: 200 000 сўм)'
                    : 'Нарх / шартнома',
                hintStyle: const TextStyle(
                    color: JobsColors.hint,
                    fontSize: AppText.bodyMedium),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JobsColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: JobsColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _color, width: 1.5)),
                filled: true,
                fillColor: JobsColors.fieldFill,
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
                          strokeWidth: 2, color: JobsColors.onBar))
                  : const Icon(Icons.send, size: 18),
              label: Text(
                _submitting ? 'Юборилмоқда...' : 'ЭЪЛОН ҚЎШИШ',
                style: const TextStyle(
                    fontSize: AppText.bodyLarge, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _color,
                foregroundColor: JobsColors.onBar,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                '$_visibleDays кун давомида кўринади • Кунига ${JobsController.dailyAdLimit} та эълон',
                style: const TextStyle(
                    fontSize: AppText.labelTiny, color: JobsColors.muted),
              ),
            ),
          ]),
    );
  }
}
