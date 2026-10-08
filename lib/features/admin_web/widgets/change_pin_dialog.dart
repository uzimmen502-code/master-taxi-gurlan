import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/admin_auth_service.dart';

/// Админ ўз PIN'ини алмаштиради (`adminChangeOwnPin`). [required] — superadmin
/// берган вақтинчалик PIN билан кирилганда (ёпиш тугмаси «Кейинроқ»).
Future<void> showChangePinDialog(BuildContext context, {bool required = false}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !required,
    builder: (_) => _ChangePinDialog(required: required),
  );
}

class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog({required this.required});

  final bool required;

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_next.text.trim() != _repeat.text.trim()) {
      setState(() => _error = 'Янги PIN такрори мос эмас.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await context.read<AdminAuthService>().changeOwnPin(
          currentPin: _current.text,
          newPin: _next.text,
        );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(content: Text('✅ PIN алмаштирилди')));
  }

  Widget _pinField(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 12,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            counterText: '',
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('PIN\'ни алмаштириш'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.required)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Сиз superadmin берган вақтинчалик PIN билан кирдингиз. '
                  'Ўзингизникига алмаштиринг.',
                ),
              ),
            _pinField(_current, 'Жорий PIN'),
            _pinField(_next, 'Янги PIN (6–12 рақам)'),
            _pinField(_repeat, 'Янги PIN (такрор)'),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(widget.required ? 'Кейинроқ' : 'Бекор'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сақлаш'),
        ),
      ],
    );
  }
}
