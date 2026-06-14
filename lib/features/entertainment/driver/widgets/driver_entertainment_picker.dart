import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../../../../models/entertainment_video.dart';
import '../../../../repositories/entertainment_repository.dart';

/// Ҳайдовчи панели — каталогдан ≤5 ta film tanlash (B variant).
class DriverEntertainmentPicker extends StatefulWidget {
  const DriverEntertainmentPicker({
    super.key,
    required this.driverId,
    this.primaryColor = AppColors.primary,
  });

  final String driverId;
  final Color primaryColor;

  @override
  State<DriverEntertainmentPicker> createState() =>
      _DriverEntertainmentPickerState();
}

class _DriverEntertainmentPickerState extends State<DriverEntertainmentPicker> {
  List<EntertainmentVideo> _catalog = const [];
  final Set<String> _selected = {};
  bool _allowed = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<EntertainmentRepository>();
    try {
      final catalog = await repo.getCatalog();
      final allowed = await repo.isEntertainmentAllowed(widget.driverId);
      final ids = await repo.getDriverEntertainmentIds(widget.driverId);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _allowed = allowed;
        _selected
          ..clear()
          ..addAll(ids);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<EntertainmentRepository>().setDriverEntertainmentIds(
            widget.driverId,
            _selected.toList(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Фильмлар сақланди')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'permission-denied'
          ? 'Рухсат йўқ: админ «Kino» ёқилганини текширинг'
          : 'Firestore: ${e.message ?? e.code}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (_selected.length <
          EntertainmentRepository.maxDriverSelection) {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }

    if (!_allowed) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '🎬 Кино: админ рухсати керак. Админ панелдан «Кино рухсати»ни ёқинг.',
          style: TextStyle(fontSize: 12),
        ),
      );
    }

    if (_catalog.isEmpty) {
      return const Text(
        'Админ ҳали кино юкламаган.',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('🎬 САФАР КИНО',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const Spacer(),
          Text(
            '${_selected.length}/${EntertainmentRepository.maxDriverSelection}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ]),
        const SizedBox(height: 6),
        const Text(
          'Йўловчилар танланган фильмларни Wi‑Fi да юклаб, сафарда офлайн томоша қилади.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 11)),
        ],
        const SizedBox(height: 8),
        ..._catalog.map((v) {
          final sel = _selected.contains(v.id);
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: sel,
            onChanged: (_) => _toggle(v.id),
            title: Text(v.title, style: const TextStyle(fontSize: 13)),
            subtitle: v.durationLabel.isNotEmpty
                ? Text(v.durationLabel, style: const TextStyle(fontSize: 11))
                : null,
            activeColor: widget.primaryColor,
          );
        }),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: widget.primaryColor),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('ФИЛМЛАРНИ САҚЛАШ'),
          ),
        ),
      ],
    );
  }
}
