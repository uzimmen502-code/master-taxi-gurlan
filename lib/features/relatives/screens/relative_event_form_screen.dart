import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../models/relative_event.dart';
import '../../../models/relative_person.dart';
import '../../../repositories/relatives_repository.dart';
import '../l10n/relatives_l10n.dart';

/// 📅 Sana / uchrashuv qo'shish-tahrirlash.
class RelativeEventFormScreen extends StatefulWidget {
  const RelativeEventFormScreen({
    super.key,
    required this.userId,
    this.existing,
    this.allPeople = const [],
  });

  final String userId;
  final RelativeEvent? existing;
  final List<RelativePerson> allPeople;

  static const _accent = Color(0xFF6A4C93);

  @override
  State<RelativeEventFormScreen> createState() =>
      _RelativeEventFormScreenState();
}

class _RelativeEventFormScreenState extends State<RelativeEventFormScreen> {
  final _repo = RelativesRepository();

  final _titleCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime? _date;
  bool _repeatYearly = false;
  RelativeEventType _type = RelativeEventType.meeting;
  final Set<String> _personIds = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e.title;
      _placeCtrl.text = e.place;
      _noteCtrl.text = e.note;
      _date = e.date;
      _repeatYearly = e.repeatYearly;
      _type = e.type;
      _personIds.addAll(e.personIds);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _placeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 10),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack(context.tr('rel_event_title_required'));
      return;
    }
    if (_date == null) {
      _snack(context.tr('rel_event_date_required'));
      return;
    }
    setState(() => _busy = true);
    try {
      final event = RelativeEvent(
        id: widget.existing?.id ?? '',
        title: title,
        date: _date!,
        repeatYearly: _repeatYearly,
        personIds: _personIds.toList(),
        place: _placeCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
        type: _type,
      );
      if (widget.existing == null) {
        await _repo.addEvent(widget.userId, event);
      } else {
        await _repo.updateEvent(widget.userId, widget.existing!.id, event);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        _snack(RelativesL10n.trParams(
            context, 'error_generic', {'error': '$e'}));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final e = widget.existing;
    if (e == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('delete')),
        content: Text(RelativesL10n.trParams(
            ctx, 'rel_delete_confirm_body', {'name': e.title})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('no'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text(ctx.tr('rel_delete_i_confirm')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteEvent(widget.userId, e.id);
    if (mounted) Navigator.pop(context);
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit
            ? context.tr('rel_event_edit_title')
            : context.tr('rel_event_add_title')),
        backgroundColor: RelativeEventFormScreen._accent,
        foregroundColor: Colors.white,
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field(_titleCtrl, context.tr('rel_event_field_title'),
              Icons.title_outlined),
          const SizedBox(height: 12),
          _typeDropdown(),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(_date == null
                ? context.tr('rel_event_field_date')
                : _fmtDate(_date!)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _pickDate,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: RelativeEventFormScreen._accent,
            title: Text(context.tr('rel_event_repeat')),
            subtitle: Text(context.tr('rel_event_repeat_sub')),
            value: _repeatYearly,
            onChanged: (v) => setState(() => _repeatYearly = v),
          ),
          const SizedBox(height: 4),
          _field(_placeCtrl, context.tr('rel_event_place'),
              Icons.location_on_outlined),
          const SizedBox(height: 12),
          _field(_noteCtrl, context.tr('rel_field_notes'), Icons.notes_outlined,
              maxLines: 3),
          if (widget.allPeople.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              context.tr('rel_event_linked'),
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: RelativeEventFormScreen._accent),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: widget.allPeople.map((p) {
                final sel = _personIds.contains(p.id);
                return FilterChip(
                  label: Text(p.fullName),
                  selected: sel,
                  selectedColor:
                      RelativeEventFormScreen._accent.withValues(alpha: 0.2),
                  checkmarkColor: RelativeEventFormScreen._accent,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _personIds.add(p.id);
                    } else {
                      _personIds.remove(p.id);
                    }
                  }),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: RelativeEventFormScreen._accent,
                  foregroundColor: Colors.white),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(context.tr('save')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeDropdown() {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: context.tr('rel_event_field_type'),
        prefixIcon: const Icon(Icons.category_outlined),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<RelativeEventType>(
          value: _type,
          isExpanded: true,
          items: RelativeEventType.values
              .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text('${t.emoji} ${t.trLabel(context)}'),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _type = v ?? _type),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  String _fmtDate(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year}';
  }
}
