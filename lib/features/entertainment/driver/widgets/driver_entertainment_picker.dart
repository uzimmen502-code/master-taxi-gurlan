import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/user_error.dart';
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

  /// Xato matni emas — l10n kaliti (ekranda `context.tr(_errorKey!)`).
  String? _errorKey;

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
        _errorKey = userErrorKey(e, fallbackKey: 'err_load_failed');
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
        SnackBar(content: Text(context.tr('ent_saved'))),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'permission-denied'
          ? context.tr('ent_perm_denied')
          : userErrorMessage(context, e, fallbackKey: 'ent_save_failed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      // Repozitoriy (setDriverEntertainmentIds) kirill matnli Exception
      // tashlaydi — xom matn ko'rsatilmaydi, faqat umumiy xabar.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                userErrorMessage(context, e, fallbackKey: 'ent_save_failed'))),
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
        child: Text(
          context.tr('ent_need_admin'),
          style: const TextStyle(fontSize: 12),
        ),
      );
    }

    if (_catalog.isEmpty) {
      return Text(
        context.tr('ent_catalog_empty'),
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(context.tr('ent_picker_title'),
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const Spacer(),
          Text(
            '${_selected.length}/${EntertainmentRepository.maxDriverSelection}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          context.tr('ent_picker_hint'),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        if (_errorKey != null) ...[
          const SizedBox(height: 6),
          Text(context.tr(_errorKey!),
              style: const TextStyle(color: Colors.red, fontSize: 11)),
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
            style: FilledButton.styleFrom(
              backgroundColor: widget.primaryColor,
              foregroundColor: AppColors.onPrimary,
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.onPrimary),
                  )
                : Text(context.tr('ent_picker_save')),
          ),
        ),
      ],
    );
  }
}
