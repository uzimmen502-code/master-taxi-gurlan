import 'package:flutter/material.dart';

/// Админ амали учун тасдиқ + сабаб (audit). Бекор қилинса `null`; тасдиқ — сабаб
/// матни (`required` бўлса камида [minLength] белги, акс ҳолда бўш бўлиши мумкин).
Future<String?> showAdminReasonDialog(
  BuildContext context, {
  required String title,
  String? message,
  bool required = true,
  int minLength = 3,
  String confirmLabel = 'Тасдиқлаш',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _AdminReasonDialog(
      title: title,
      message: message,
      required: required,
      minLength: minLength,
      confirmLabel: confirmLabel,
    ),
  );
}

class _AdminReasonDialog extends StatefulWidget {
  const _AdminReasonDialog({
    required this.title,
    required this.message,
    required this.required,
    required this.minLength,
    required this.confirmLabel,
  });

  final String title;
  final String? message;
  final bool required;
  final int minLength;
  final String confirmLabel;

  @override
  State<_AdminReasonDialog> createState() => _AdminReasonDialogState();
}

class _AdminReasonDialogState extends State<_AdminReasonDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = !widget.required || _ctrl.text.trim().length >= widget.minLength;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(widget.message!, style: const TextStyle(fontSize: 13)),
              ),
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLength: 300,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: widget.required ? 'Сабаб (мажбурий, audit)' : 'Сабаб (ихтиёрий, audit)',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Бекор')),
        FilledButton(
          onPressed: ok ? () => Navigator.pop(context, _ctrl.text.trim()) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
