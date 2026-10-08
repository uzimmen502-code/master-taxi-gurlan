import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/map_picker_result.dart';
import '../../../models/realty_alert.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../../map_picker/screens/map_picker_screen.dart';
import '../widgets/realty_feedback.dart';

/// «Шундай уй чиқса, хабар бер» — янги хабарнома (эга қарори 2026-10-08,
/// БЕПУЛ). Битим тури, харитадаги марказ, радиус, хона ва нарх чегараси.
///
/// Ҳамма текширув серверда (`createRealtyAlert`); бу ер фақат тўплайди.
/// Сақлангач `RealtyAlertCreateResult` қайтади — ҳозир мос эълонлар сони
/// чақирувчига кўрсатилади.
class RealtyAlertFormScreen extends StatefulWidget {
  const RealtyAlertFormScreen({
    super.key,
    this.initialDeal = RealtyDeal.rent,
    this.repository,
    this.pickPoint,
  });

  final RealtyDeal initialDeal;
  final RealtyRepository? repository;

  /// Тест учун: харита экрани ўрнига нуқта қайтарувчи функция.
  final Future<MapPickerResult?> Function(BuildContext context)? pickPoint;

  @override
  State<RealtyAlertFormScreen> createState() => _RealtyAlertFormScreenState();
}

class _RealtyAlertFormScreenState extends State<RealtyAlertFormScreen> {
  late final RealtyRepository _repo = widget.repository ?? RealtyRepository();
  late RealtyDeal _deal = widget.initialDeal;
  MapPickerResult? _point;
  int _radiusKm = 3;
  int? _roomsMin;
  int? _roomsMax;
  final _priceCtrl = TextEditingController();
  bool _saving = false;

  /// Хона танлови: «1», «2», «3», «4+» — 4+ максимумсиз.
  static const _roomChoices = [1, 2, 3, 4];

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  int? get _priceMax {
    final n = int.tryParse(_priceCtrl.text.replaceAll(RegExp(r'\D'), ''));
    return n == null || n <= 0 ? null : n;
  }

  Future<void> _pick() async {
    final picker = widget.pickPoint ??
        (ctx) => Navigator.of(ctx).push<MapPickerResult>(
              MaterialPageRoute(
                builder: (_) =>
                    MapPickerScreen(title: ctx.tr('realty_alert_pick_center')),
              ),
            );
    final r = await picker(context);
    if (r != null && mounted) setState(() => _point = r);
  }

  /// Бир нечта хона чипи: биринчи босилгани — оралиқ боши, кейингиси —
  /// оралиқ охири; қайта босилса тозаланади.
  void _toggleRoom(int n) {
    setState(() {
      if (_roomsMin == null) {
        _roomsMin = n;
        _roomsMax = n == 4 ? null : n;
      } else if (_roomsMin == n && (_roomsMax == n || (n == 4 && _roomsMax == null))) {
        _roomsMin = null;
        _roomsMax = null;
      } else {
        final lo = n < _roomsMin! ? n : _roomsMin!;
        final hi = n > (_roomsMax ?? _roomsMin!) ? n : (_roomsMax ?? _roomsMin!);
        _roomsMin = lo;
        _roomsMax = hi == 4 ? null : hi;
      }
    });
  }

  bool _roomSelected(int n) {
    final lo = _roomsMin;
    if (lo == null) return false;
    final hi = _roomsMax ?? 99;
    return n >= lo && n <= hi;
  }

  Future<void> _save() async {
    final point = _point;
    if (point == null || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final res = await _repo.createAlert(
        deal: _deal,
        lat: point.lat,
        lng: point.lng,
        radiusKm: _radiusKm,
        roomsMin: _roomsMin,
        roomsMax: _roomsMax,
        priceMax: _priceMax,
      );
      if (!mounted) return;
      nav.pop(res);
    } on RealtyException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showRealtyError(messenger, realtyErrorText(context, e));
    } catch (e) {
      debugPrint('[RealtyAlertForm] save $e');
      if (!mounted) return;
      setState(() => _saving = false);
      showRealtyError(messenger, context.tr('realty_error_generic'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final point = _point;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('realty_alert_new_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Text(
            context.tr('realty_alert_intro'),
            style: TextStyle(fontSize: AppText.bodyMedium, color: c.ink2),
          ),
          const SizedBox(height: 16),
          SegmentedButton<RealtyDeal>(
            segments: [
              ButtonSegment(
                value: RealtyDeal.rent,
                label: Text(context.tr('realty_deal_rent')),
              ),
              ButtonSegment(
                value: RealtyDeal.sale,
                label: Text(context.tr('realty_deal_sale')),
              ),
            ],
            selected: {_deal},
            onSelectionChanged: (s) => setState(() => _deal = s.first),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('realty_alert_pick'),
            onPressed: _pick,
            icon: Icon(point == null ? Icons.add_location_alt_outlined : Icons.place),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              alignment: Alignment.centerLeft,
            ),
            label: Text(
              point == null
                  ? context.tr('realty_alert_pick_center')
                  : (point.label.trim().isNotEmpty
                      ? point.label.trim()
                      : context.tr('realty_alert_center_chosen')),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),
          Text(context.tr('realty_alert_radius'),
              style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final km in RealtyAlert.radiusOptionsKm)
                ChoiceChip(
                  label: Text('$km км'),
                  selected: _radiusKm == km,
                  onSelected: (_) => setState(() => _radiusKm = km),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(context.tr('realty_alert_rooms'),
              style: TextStyle(fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final n in _roomChoices)
                FilterChip(
                  label: Text(n == 4 ? '4+' : '$n'),
                  selected: _roomSelected(n),
                  onSelected: (_) => _toggleRoom(n),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('realty_alert_price'),
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            maxLength: 13,
            decoration: InputDecoration(
              labelText: context.tr('realty_alert_price_max'),
              helperText: context.tr(_deal == RealtyDeal.rent
                  ? 'realty_field_price_amount_hint_rent'
                  : 'realty_field_price_amount_hint_sale'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('realty_alert_privacy_note'),
            style: TextStyle(fontSize: AppText.bodySmall, color: c.ink3),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton.icon(
            key: const ValueKey('realty_alert_save'),
            onPressed: point == null || _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active_outlined),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            label: Text(context.tr('realty_alert_save')),
          ),
        ),
      ),
    );
  }
}
