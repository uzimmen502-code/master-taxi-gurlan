import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../utils/intercity_places.dart';
import 'mfy_field.dart';

/// Marshrut / shaharlararo haydovchi arizasi — avval marshrut, keyin ariza.
class DriverRouteApplicationResult {
  const DriverRouteApplicationResult({
    required this.from,
    required this.to,
    this.midStops = const [],
  });

  final String from;
  final String to;
  final List<String> midStops;

  String get label {
    if (midStops.isEmpty) return '$from → $to';
    return '$from → ${midStops.join(' → ')} → $to';
  }

  List<String> get allStops {
    if (midStops.isEmpty) return [from, to];
    return [from, ...midStops, to];
  }
}

Future<DriverRouteApplicationResult?> showDriverRouteApplicationDialog(
  BuildContext context, {
  required String taxiType,
}) {
  final isMarshrut = taxiType == 'marshrut';
  return showDialog<DriverRouteApplicationResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DriverRouteDialog(isMarshrut: isMarshrut),
  );
}

class _DriverRouteDialog extends StatefulWidget {
  const _DriverRouteDialog({required this.isMarshrut});

  final bool isMarshrut;

  @override
  State<_DriverRouteDialog> createState() => _DriverRouteDialogState();
}

class _DriverRouteDialogState extends State<_DriverRouteDialog> {
  static const _green = AppColors.primaryDark;
  static const _blue = AppColors.primary;

  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();

  String _fromQuery = '';
  String _toQuery = '';
  bool _showFromSug = false;
  bool _showToSug = false;
  Timer? _debounce;

  bool get _valid =>
      _fromCtrl.text.trim().length >= 2 &&
      _toCtrl.text.trim().length >= 2;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFromChanged(String q) {
    setState(() {
      _fromQuery = q;
      _showFromSug = q.trim().length >= 2;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _showFromSug = _fromQuery.trim().length >= 2);
    });
  }

  void _onToChanged(String q) {
    setState(() {
      _toQuery = q;
      _showToSug = q.trim().length >= 2;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _showToSug = _toQuery.trim().length >= 2);
    });
  }

  Future<void> _submit() async {
    if (!_valid) return;

    if (!mounted) return;
    final normalizedFrom = widget.isMarshrut
        ? _fromCtrl.text.trim()
        : IntercityPlaces.normalizeLocation(_fromCtrl.text.trim());
    final normalizedTo = widget.isMarshrut
        ? _toCtrl.text.trim()
        : IntercityPlaces.normalizeLocation(_toCtrl.text.trim());
    Navigator.of(context).pop(
      DriverRouteApplicationResult(
        from: normalizedFrom,
        to: normalizedTo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMarshrut ? _green : _blue;
    final title = widget.isMarshrut
        ? 'Маршрут такси — маршрутингиз'
        : 'Шаҳарлараро — йўналишингиз';
    final subtitle = widget.isMarshrut
        ? 'Ариза юборишдан олдин қайси йўналишда ишлайсиз?'
        : 'Ариза юборишдан олдин қайси шаҳарлар орасида ишлайсиз?';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.route, color: color, size: 40),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 18),
            if (widget.isMarshrut) ...[
              MfyField(
                ctrl: _fromCtrl,
                hint: 'Қаердан (МФЙ)',
                iconColor: color,
                showSug: _showFromSug,
                query: _fromQuery,
                onChanged: _onFromChanged,
                onSelected: (v) => setState(() {
                  _fromCtrl.text = v;
                  _fromQuery = v;
                  _showFromSug = false;
                }),
                onClear: () => setState(() {
                  _fromCtrl.clear();
                  _fromQuery = '';
                  _showFromSug = false;
                }),
              ),
              const SizedBox(height: 12),
              MfyField(
                ctrl: _toCtrl,
                hint: 'Қаерга (МФЙ)',
                iconColor: color,
                showSug: _showToSug,
                query: _toQuery,
                onChanged: _onToChanged,
                onSelected: (v) => setState(() {
                  _toCtrl.text = v;
                  _toQuery = v;
                  _showToSug = false;
                }),
                onClear: () => setState(() {
                  _toCtrl.clear();
                  _toQuery = '';
                  _showToSug = false;
                }),
              ),
            ] else ...[
              _intercityField(
                ctrl: _fromCtrl,
                hint: 'Қаердан (шаҳар)',
                color: color,
                showSug: _showFromSug,
                query: _fromQuery,
                onChanged: _onFromChanged,
                onSelected: (v) => setState(() {
                  _fromCtrl.text = v;
                  _fromQuery = v;
                  _showFromSug = false;
                }),
              ),
              const SizedBox(height: 12),
              _intercityField(
                ctrl: _toCtrl,
                hint: 'Қаерга (шаҳар)',
                color: color,
                showSug: _showToSug,
                query: _toQuery,
                onChanged: _onToChanged,
                onSelected: (v) => setState(() {
                  _toCtrl.text = v;
                  _toQuery = v;
                  _showToSug = false;
                }),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _valid ? _submit : null,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Давом этиш'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Бекор қилиш'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _intercityField({
    required TextEditingController ctrl,
    required String hint,
    required Color color,
    required bool showSug,
    required String query,
    required ValueChanged<String> onChanged,
    required ValueChanged<String> onSelected,
  }) {
    final suggestions = IntercityPlaces.search(query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: ctrl,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(Icons.location_on, color: color, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
        if (showSug && suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: suggestions.length.clamp(0, 8),
              itemBuilder: (_, i) {
                final s = suggestions[i];
                return ListTile(
                  dense: true,
                  title: Text(s, style: const TextStyle(fontSize: 13)),
                  onTap: () => onSelected(s),
                );
              },
            ),
          ),
      ],
    );
  }
}
