import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../data/china_inquiry_repository.dart';

/// Хитойдан товар сўрови. Мижозга ички тушунчалар (таъминотчи, оператор, WeChat) кўрсатилмайди (45-банд).
class ChinaInquiryFormScreen extends StatefulWidget {
  const ChinaInquiryFormScreen({super.key, this.productId, ChinaInquiryRepository? repository})
      : _repo = repository;

  /// Маҳсулот саҳифасидан келса — сервер уни текширади.
  final String? productId;
  final ChinaInquiryRepository? _repo;

  @override
  State<ChinaInquiryFormScreen> createState() => _ChinaInquiryFormScreenState();
}

class _ChinaInquiryFormScreenState extends State<ChinaInquiryFormScreen> {
  late final ChinaInquiryRepository _repo = widget._repo ?? ChinaInquiryRepository();
  final _text = TextEditingController();
  final _qty = TextEditingController();
  bool _consent = false;
  bool _busy = false;
  String? _error;

  /// Бир форма = бир калит: қайта босилса ҲАМ шу сўров (дубликат ёзилмайди).
  final String _requestId = 'r${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    _text.dispose();
    _qty.dispose();
    super.dispose();
  }

  String _errorFor(Object e) {
    if (e is FirebaseFunctionsException) {
      final details = e.details;
      final code = details is Map ? '${details['code']}' : '';
      switch (code) {
        case 'TOO_MANY_OPEN':
          return context.tr('china_inq_err_too_many');
        case 'CHINA_INQUIRY_DISABLED':
          return context.tr('china_inq_err_disabled');
        case 'TEXT_INVALID':
          return context.tr('china_inq_err_text');
        case 'CONSENT_REQUIRED':
          return context.tr('china_inq_err_consent');
      }
    }
    debugPrint('[ChinaInquiryForm] $e');
    return context.tr('china_inq_err_generic');
  }

  Future<void> _submit() async {
    final text = _text.text.trim();
    if (text.length < 10 || text.length > 500) {
      setState(() => _error = context.tr('china_inq_err_text'));
      return;
    }
    if (!_consent) {
      setState(() => _error = context.tr('china_inq_err_consent'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _repo.create(
        text: text,
        quantity: _qty.text.trim(),
        clientRequestId: _requestId,
        productId: widget.productId,
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.tr('china_inq_sent_ok').replaceAll('{ref}', r.refNo))),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _errorFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('china_inq_form_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _text,
            enabled: !_busy,
            maxLines: 5,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: context.tr('china_inq_field_text'),
              hintText: context.tr('china_inq_field_text_hint'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            enabled: !_busy,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: context.tr('china_inq_field_qty'),
              hintText: context.tr('china_inq_field_qty_hint'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _consent,
            onChanged: _busy ? null : (v) => setState(() => _consent = v == true),
            title: Text(context.tr('china_inq_consent')),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr('china_inq_submit')),
          ),
        ],
      ),
    );
  }
}
