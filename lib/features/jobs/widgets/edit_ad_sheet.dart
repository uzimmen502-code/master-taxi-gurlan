import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_ad.dart';
import '../../../utils/app_theme.dart';
import '../controllers/jobs_controller.dart';
import 'urgent_toggle.dart';

/// Мавжуд эълонни таҳрирлаш bottom sheet'и.
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
  static const _blue = Color(0xFF5D4037);
  static const _green = Color(0xFF795548);

  late TextEditingController _textCtrl;
  late bool _isUrgent;
  late String _status;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.ad.text);
    _isUrgent = widget.ad.isUrgent;
    _status = widget.ad.status;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
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
      status: _status,
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
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(20),
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
          const SizedBox(height: 16),
          Row(children: const [
            Icon(Icons.edit, color: _blue, size: 24),
            SizedBox(width: 8),
            Text('Эълонни таҳрирлаш',
                style: TextStyle(
                    fontSize: AppText.titleMedium,
                    fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _textCtrl,
            maxLines: 4,
            maxLength: 300,
            decoration: InputDecoration(
              hintText: 'Эълон матни...',
              hintStyle: TextStyle(
                  color: Colors.grey.shade400, fontSize: AppText.bodyMedium),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _blue, width: 1.5)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 12),
          if (widget.ad.isWork) ...[
            UrgentToggle(
              isUrgent: _isUrgent,
              onTap: () => setState(() => _isUrgent = !_isUrgent),
              showHint: false,
            ),
            const SizedBox(height: 16),
          ],
          if (c.isAdmin) ...[
            const Text('Статус:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              _statusBtn('active', '✅ Фаол'),
              const SizedBox(width: 8),
              _statusBtn('completed', '✔️ Ёпилган'),
              const SizedBox(width: 8),
              _statusBtn('blocked', '🚫 Блок'),
            ]),
            const SizedBox(height: 16),
          ],
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _isSaving ? null : () => Navigator.of(context).pop(),
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
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
