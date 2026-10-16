import 'package:flutter/material.dart';

/// «Kuryerdan olish» tasdiqlash oynasi: sabab ixtiyoriy (audit'ga yoziladi).
/// Bekor qilinsa `null`, tasdiqlansa sabab matni (bo'sh bo'lishi mumkin).
Future<String?> showReleaseTaskDialog(
  BuildContext context, {
  required String taskLabel,
  required String resultLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReleaseTaskDialog(taskLabel: taskLabel, resultLabel: resultLabel),
  );
}

class _ReleaseTaskDialog extends StatefulWidget {
  const _ReleaseTaskDialog({required this.taskLabel, required this.resultLabel});

  final String taskLabel;
  final String resultLabel;

  @override
  State<_ReleaseTaskDialog> createState() => _ReleaseTaskDialogState();
}

class _ReleaseTaskDialogState extends State<_ReleaseTaskDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Kuryerdan olib qo\'yilsinmi?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.taskLabel}: vazifa kuryerdan olinadi va "${widget.resultLabel}" '
            'holatiga qaytadi — boshqa kuryer olishi mumkin. Kuryer biriktirishi tozalanadi.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Sabab (ixtiyoriy, audit uchun)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bekor')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _reason.text.trim()),
          child: const Text('Kuryerdan olish'),
        ),
      ],
    );
  }
}
