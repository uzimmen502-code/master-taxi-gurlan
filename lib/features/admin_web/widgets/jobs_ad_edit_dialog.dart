import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/job_ad.dart';
import '../services/admin_jobs_service.dart';

/// Admin — Иш топ e'lonini tahrirlash dialogi.
Future<void> showJobsAdEditDialog({
  required BuildContext context,
  required JobAd ad,
  required String adminPhone,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _JobsAdEditDialog(ad: ad, adminPhone: adminPhone),
  );
}

class _JobsAdEditDialog extends StatefulWidget {
  const _JobsAdEditDialog({
    required this.ad,
    required this.adminPhone,
  });

  final JobAd ad;
  final String adminPhone;

  @override
  State<_JobsAdEditDialog> createState() => _JobsAdEditDialogState();
}

class _JobsAdEditDialogState extends State<_JobsAdEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _text;
  late final TextEditingController _price;
  late final TextEditingController _address;
  late final TextEditingController _adminNote;
  late AdKind _kind;
  late String _status;
  late bool _urgent;
  late DateTime? _expiresAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.ad.title);
    _text = TextEditingController(text: widget.ad.text);
    _price = TextEditingController(text: widget.ad.priceText);
    _address = TextEditingController(text: widget.ad.address);
    _adminNote = TextEditingController(text: widget.ad.adminNote);
    _kind = widget.ad.kind;
    _status = widget.ad.status;
    _urgent = widget.ad.isUrgent;
    _expiresAt = widget.ad.expiresAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    _price.dispose();
    _address.dispose();
    _adminNote.dispose();
    super.dispose();
  }

  void _extendExpiry(int days) {
    final base = _expiresAt ?? DateTime.now();
    setState(() {
      _expiresAt = base.isBefore(DateTime.now())
          ? DateTime.now().add(Duration(days: days))
          : base.add(Duration(days: days));
    });
  }

  Future<void> _pickExpiryDate() async {
    final initial = _expiresAt ?? DateTime.now().add(const Duration(days: 7));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _expiresAt = picked);
  }

  Future<void> _save() async {
    if (_text.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Асосий матн бўш бўла олмайди'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<AdminJobsService>().updateAd(
            adminPhone: widget.adminPhone,
            adId: widget.ad.id,
            text: _text.text.trim(),
            isUrgent: _urgent,
            type: _kind.key,
            status: _status,
            title: _title.text.trim(),
            priceText: _price.text.trim(),
            address: _address.text.trim(),
            expiresAt: _expiresAt,
            adminNote: _adminNote.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.button,
          content: Text('Эълон янгиланди'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _expiresSummary() {
    if (_expiresAt == null) return 'Муддатсиз';
    final d = _expiresAt!;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Эълонни таҳрирлаш'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, minWidth: 360),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<AdKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Тури'),
              items: [
                for (final kind in AdKind.values)
                  DropdownMenuItem(
                    value: kind,
                    child: Text('${kind.emoji} ${kind.label}'),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _kind = v;
                  if (!v.supportsUrgent) _urgent = false;
                });
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Сарлавҳа',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Асосий матн',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _price,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Нарх / шартнома',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _address,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Манzil',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Муддат: $_expiresSummary',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _extendExpiry(7),
                  child: const Text('+7 kun'),
                ),
                OutlinedButton(
                  onPressed: _pickExpiryDate,
                  child: const Text('Sanani tanlash'),
                ),
                if (_expiresAt != null)
                  TextButton(
                    onPressed: () => setState(() => _expiresAt = null),
                    child: const Text('Muddatni olib tashlash'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _adminNote,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Admin izohi (blok sababi va h.k.)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Статус'),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Кутилмоқда')),
                DropdownMenuItem(value: 'active', child: Text('Фаол')),
                DropdownMenuItem(value: 'completed', child: Text('Ёпилган')),
                DropdownMenuItem(value: 'blocked', child: Text('Блок')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _status = v);
              },
            ),
            if (_kind.supportsUrgent)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Шошилинч'),
                subtitle: const Text('Аloҳида «Шошилинч» tabida кўринadi'),
                value: _urgent,
                onChanged: (v) => setState(() => _urgent = v),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Bekor'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text('Saqlash'),
        ),
      ],
    );
  }
}
