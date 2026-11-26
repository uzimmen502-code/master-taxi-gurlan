import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';

/// `users/{uid}.holidayRemindersOptIn` (ВАҚТИНЧА шартнома, эга 2026-11-26). Майдон йўқ — ЁҚИҚ (эслатма боради;
/// сервер ҳам шундай ҳисоблайди — UNKNOWN, келишилади). Фақат шу bool ёзилади (rules: эга, ҳамён майдонлари тегилмайди).
const kHolidayRemindersField = 'holidayRemindersOptIn';

bool holidayRemindersOn(Map<String, dynamic>? userDoc) => userDoc?[kHolidayRemindersField] != false;

class HolidayRemindersStore {
  Future<String> _uid() async {
    final prefs = await SharedPreferences.getInstance();
    return canonicalPhoneId(prefs.getString('user_phone') ?? '');
  }

  Future<bool> load() async {
    final uid = await _uid();
    if (uid.length < 12) return true;
    final d = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return holidayRemindersOn(d.data());
  }

  Future<void> save(bool on) async {
    final uid = await _uid();
    if (uid.length < 12) throw StateError('HOLIDAY_REMINDERS_NO_USER');
    await FirebaseFirestore.instance.collection('users').doc(uid).set({kHolidayRemindersField: on}, SetOptions(merge: true));
  }
}

/// Профил → «Байрам эслатмалари» (байрам ва қариндош туғилган куни эслатмалари). Ҳеч қачон буюртма бермайди.
class HolidayRemindersToggle extends StatefulWidget {
  const HolidayRemindersToggle({super.key, this.load, this.save});

  final Future<bool> Function()? load;
  final Future<void> Function(bool on)? save;

  @override
  State<HolidayRemindersToggle> createState() => _HolidayRemindersToggleState();
}

class _HolidayRemindersToggleState extends State<HolidayRemindersToggle> {
  final _store = HolidayRemindersStore();
  bool? _on;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final v = await (widget.load ?? _store.load)();
        if (mounted) setState(() => _on = v);
      } catch (e) {
        debugPrint('[Profile] HOLIDAY_REMINDERS_LOAD_FAILED: $e');
        if (mounted) setState(() => _on = true);
      }
    }();
  }

  Future<void> _set(bool v) async {
    final prev = _on;
    setState(() {
      _on = v;
      _saving = true;
    });
    try {
      await (widget.save ?? _store.save)(v);
    } catch (e) {
      debugPrint('[Profile] HOLIDAY_REMINDERS_SAVE_FAILED: $e');
      if (!mounted) return;
      setState(() => _on = prev);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('hb_reminders_save_failed'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return SwitchListTile(
      key: const ValueKey('holiday_reminders_toggle'),
      secondary: Icon(Icons.celebration_outlined, color: c.ink2),
      value: _on ?? true,
      onChanged: _on == null || _saving ? null : _set,
      title: Text(context.tr('hb_reminders_title'), style: TextStyle(fontSize: 16, color: c.ink)),
      subtitle: Text(context.tr('hb_reminders_hint'), style: TextStyle(fontSize: 14, color: c.ink2)),
    );
  }
}
