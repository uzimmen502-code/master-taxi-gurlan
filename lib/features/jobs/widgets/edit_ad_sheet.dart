import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_ad.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/jobs_controller.dart';
import 'urgent_toggle.dart';

Future<void> showEditAdSheet({
  required BuildContext context,
  required JobAd ad,
  required JobsController controller,
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
        child: _EditAdView(ad: ad),
      ),
    ),
  );
}

class _EditAdView extends StatefulWidget {
  const _EditAdView({required this.ad});

  final JobAd ad;

  @override
  State<_EditAdView> createState() => _EditAdViewState();
}

class _EditAdViewState extends State<_EditAdView> {
  static const _blue = AppColors.primaryDark;
  static const _green = Color(0xFF795548);

  late TextEditingController _titleCtrl;
  late TextEditingController _textCtrl;
  late TextEditingController _priceCtrl;
  late bool _isUrgent;
  late String _status;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.ad.title);
    _textCtrl = TextEditingController(text: widget.ad.text);
    _priceCtrl = TextEditingController(text: widget.ad.priceText);
    _isUrgent = widget.ad.isUrgent;
    _status = widget.ad.status;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _textCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = context.read<JobsController>();
    setState(() => _isSaving = true);
    final result = await c.updateAd(
      adId: widget.ad.id,
      text: _textCtrl.text,
      isUrgent: _isUrgent,
      type: widget.ad.type,
      status: c.isAdmin ? _status : null,
      title: _titleCtrl.text.trim(),
      priceText: _priceCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.error ?? 'Хатолик'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('✅ Эълон янгиланди!'),
      backgroundColor: _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Эълонни ўчириш'),
        content: const Text('Бу эълон ноқайд ўчирилади. Давом этасизми?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ўчириш', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final c = context.read<JobsController>();
    setState(() => _isSaving = true);
    final result = await c.deleteAd(widget.ad.id);
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.error ?? 'Хатолик'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Эълон ўчирилди'),
      backgroundColor: Colors.orange,
    ));
  }

  Widget _statusBtn(String value, String label) {
    final selected = _status == value;
    return GestureDetector(
      onTap: () => setState(() => _status = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _blue : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? _blue : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: AppText.labelSmall,
                color: selected ? Colors.white : Colors.grey.shade600,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<JobsController>();
    final canDelete = c.isOwner(widget.ad) || c.isAdmin;
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Material(
            color: Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(2))),
                      ),
                      const SizedBox(height: 16),
                      const Row(children: [
                        Icon(Icons.edit, color: _blue, size: 24),
                        SizedBox(width: 8),
                        Text('Эълонни таҳрирлаш',
                            style: TextStyle(
                                fontSize: AppText.titleMedium,
                                fontWeight: FontWeight.bold)),
                      ]),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _titleCtrl,
                          maxLength: 80,
                          decoration: InputDecoration(
                            labelText: 'Сарлавҳа',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _textCtrl,
                          maxLines: 4,
                          maxLength: 300,
                          decoration: InputDecoration(
                            labelText: 'Матн',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _priceCtrl,
                          maxLength: 40,
                          decoration: InputDecoration(
                            labelText: 'Нарх (ихтиёрий)',
                            hintText: '200 000 сўм',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (widget.ad.supportsUrgent) ...[
                          UrgentToggle(
                            isUrgent: _isUrgent,
                            onTap: () =>
                                setState(() => _isUrgent = !_isUrgent),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (c.isAdmin) ...[
                          const Text('Статус:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            _statusBtn('active', '✅ Фаол'),
                            _statusBtn('pending', '⏳ Кутилмоқда'),
                            _statusBtn('completed', '✔️ Ёпилган'),
                            _statusBtn('blocked', '🚫 Блок'),
                          ]),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(children: [
                    if (canDelete)
                      IconButton(
                        onPressed: _isSaving ? null : _delete,
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red),
                        tooltip: 'Ўчириш',
                      ),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Бекор қилиш'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save, size: 18),
                        label: Text(_isSaving ? '...' : 'САҚЛАШ',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
