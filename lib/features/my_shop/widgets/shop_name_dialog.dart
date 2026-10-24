import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';

/// Дўкон номи энг камида шунча белги (серверда алоҳида текширув йўқ — `tv_shops`
/// rules фақат эгалик; шу қоида клиентда ягона манба).
const kShopNameMinLength = 2;
const kShopNameMaxLength = 60;

/// Номни тозалайди ва текширади: тўғри бўлса тозаланган матн, акс ҳолда `null`.
String? validShopName(String raw) {
  final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.length < kShopNameMinLength || name.length > kShopNameMaxLength) {
    return null;
  }
  return name;
}

/// «Дўкон номи» ойнаси. [save] чақирилади; муваффақиятли бўлса сақланган ном
/// қайтади, бекор қилинса `null`. Хатода ойна ёпилмайди — матн қолади ва
/// содда жумла кўрсатилади (25-банд).
Future<String?> showShopNameDialog(
  BuildContext context, {
  required String initial,
  required Future<void> Function(String name) save,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ShopNameDialog(initial: initial, save: save),
  );
}

class _ShopNameDialog extends StatefulWidget {
  const _ShopNameDialog({required this.initial, required this.save});

  final String initial;
  final Future<void> Function(String name) save;

  @override
  State<_ShopNameDialog> createState() => _ShopNameDialogState();
}

class _ShopNameDialogState extends State<_ShopNameDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = validShopName(_ctrl.text);
    if (name == null) {
      setState(() => _error = context.tr('my_shop_name_err'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save(name);
      if (mounted) Navigator.of(context).pop(name);
    } catch (e) {
      debugPrint('[ShopName] save failed: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.tr('my_shop_name_save_failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('my_shop_name_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            enabled: !_busy,
            autofocus: true,
            maxLength: kShopNameMaxLength,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              hintText: context.tr('my_shop_name_hint'),
              helperText: context.tr('my_shop_name_note'),
              helperMaxLines: 2,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(context.tr('cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('save')),
        ),
      ],
    );
  }
}
