// ТАКЛИФЧИ ИМКОНИЯТЛАРИ ВА РОЗИЛИК (13.4.11).
//
// Экраннинг иккита вазифаси бор:
//
// 1) ИМКОНИЯТ: «мен нима қиламан, қайси ҳудудда». Шу ёзув
//    `provider_capabilities/{uid}_{module}`га тушади ва ўша заҳоти
//    тескари matching ишга тушади (`onProviderAvailable`) — яъни одам
//    мос АКТИВ талабларни дарҳол кўради, янги талаб кутмайди.
//
// 2) РОЗИЛИК: cold start'да одам `ads` эълонидан номзод бўлиб тушган
//    (`consentGiven: false`) ва PUSH ОЛМАГАН. Шу экранда у «ҳа, оламан»
//    деса, `provider_capabilities` ёзилади ва шундан кейин push олади.
//
//    Концепция: «AVA ўтмишдаги фаолиятдан таклиф ясайди: "Сиз телефон
//    сотгансиз. Шу йўналишда талаблар олишни хоҳлайсизми?"»
//
// МАХФИЙЛИК ВА ХАВФСИЗЛИК: Firestore қоидаси бу ҳужжатга `trustScore`,
// `rating`, `completedCount` каби майдонларни ёзишга РУХСАТ БЕРМАЙДИ.
// Шунинг учун экран уларга умуман тегмайди.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/ava_tokens.dart';
import '../../domain/demand_enums.dart';

/// Push созламаси — концепция: «ёқиш, ўчириш ёки фақат кечки дайжест».
enum ProviderPushMode { on, digestOnly, off }

class ProviderCapabilitiesScreen extends StatefulWidget {
  const ProviderCapabilitiesScreen({
    super.key,
    required this.userId,
    required this.module,
    required this.categories,
    this.firestore,
    this.initialCategoryIds = const [],
    this.initialRegionIds = const [],
    this.initialDistrictIds = const [],
    this.initialPushMode = ProviderPushMode.on,
    this.availableRegions = const ['xorazm'],
    this.consentPrompt = false,
  });

  /// Канон телефон ID (`998XXXXXXXXX`).
  final String userId;

  final DemandModule module;

  /// `categoryId` → кўринадиган ном.
  final Map<String, String> categories;

  final FirebaseFirestore? firestore;

  final List<String> initialCategoryIds;
  final List<String> initialRegionIds;
  final List<String> initialDistrictIds;
  final ProviderPushMode initialPushMode;
  final List<String> availableRegions;

  /// `true` — cold start розилик оқими (матн бошқача).
  final bool consentPrompt;

  @override
  State<ProviderCapabilitiesScreen> createState() =>
      _ProviderCapabilitiesScreenState();
}

class _ProviderCapabilitiesScreenState
    extends State<ProviderCapabilitiesScreen> {
  late Set<String> _categories;
  late Set<String> _regions;
  late ProviderPushMode _pushMode;
  bool _saving = false;
  String? _error;

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _categories = widget.initialCategoryIds.toSet();
    _regions = widget.initialRegionIds.isNotEmpty
        ? widget.initialRegionIds.toSet()
        : widget.availableRegions.take(1).toSet();
    _pushMode = widget.initialPushMode;
  }

  Future<void> _save() async {
    if (_categories.isEmpty) {
      setState(() => _error = context.tr('request_what_needed'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final key = '${widget.userId}_${widget.module.wire}';
      // Клиент ЎЗИ ёзади — бу ҳужжат фойдаланувчининг ўз қарори.
      // Қоида `trustScore`/`rating`/`stats` майдонларини рад этади,
      // шунинг учун улар бу ерда УМУМАН йўқ.
      await _db.collection('provider_capabilities').doc(key).set({
        'providerId': widget.userId,
        'module': widget.module.wire,
        'active': true,
        'categoryIds': _categories.toList()..sort(),
        'categoryGroups': <String>[],
        'regionIds': _regions.toList()..sort(),
        'districtIds': widget.initialDistrictIds,
        'pushOptOut': _pushMode == ProviderPushMode.off,
        'digestOnly': _pushMode == ProviderPushMode.digestOnly,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _declineConsent() async {
    // Розилик бермади — ҳужжат `active: false` билан ёзилади.
    //
    // Нега умуман ёзилади: акс ҳолда ҳар кирганда қайта сўралади ва
    // бу безовта қилади. `active: false` — «сўраманг» белгиси.
    setState(() => _saving = true);
    try {
      final key = '${widget.userId}_${widget.module.wire}';
      await _db.collection('provider_capabilities').doc(key).set({
        'providerId': widget.userId,
        'module': widget.module.wire,
        'active': false,
        'declinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) Navigator.of(context).pop(false);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(
          context.tr(
            widget.consentPrompt ? 'consent_title' : 'capabilities_title',
          ),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
          maxLines: 2,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              context.tr(
                widget.consentPrompt ? 'consent_body' : 'capabilities_hint',
              ),
              style: TextStyle(fontSize: 12, color: c.ink2),
            ),
            const SizedBox(height: 16),

            _sectionLabel(context, 'capabilities_title'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in widget.categories.entries)
                  _toggleChip(
                    context,
                    label: e.value,
                    selected: _categories.contains(e.key),
                    onTap: () => setState(() {
                      if (_categories.contains(e.key)) {
                        _categories.remove(e.key);
                      } else {
                        _categories.add(e.key);
                      }
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            _sectionLabel(context, 'capabilities_regions'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in widget.availableRegions)
                  _toggleChip(
                    context,
                    label: r,
                    selected: _regions.contains(r),
                    onTap: () => setState(() {
                      if (_regions.contains(r)) {
                        // Камида битта ҳудуд қолиши керак.
                        if (_regions.length > 1) _regions.remove(r);
                      } else {
                        _regions.add(r);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            _sectionLabel(context, 'capabilities_push'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.line),
              ),
              child: Column(
                children: [
                  _pushOption(context, ProviderPushMode.on, 'capabilities_push_on'),
                  Divider(height: 1, color: c.line),
                  _pushOption(
                    context,
                    ProviderPushMode.digestOnly,
                    'capabilities_push_digest',
                  ),
                  Divider(height: 1, color: c.line),
                  _pushOption(
                    context,
                    ProviderPushMode.off,
                    'capabilities_push_off',
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.dangerSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: c.danger),
                ),
              ),
            ],

            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.brandInk,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                context.tr(
                  widget.consentPrompt ? 'consent_yes' : 'capabilities_save',
                ),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            if (widget.consentPrompt) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : _declineConsent,
                child: Text(
                  context.tr('consent_no'),
                  style: TextStyle(fontSize: 13, color: c.ink2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String key) => Text(
        context.tr(key),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: context.ava.ink,
        ),
      );

  Widget _toggleChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = context.ava;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.8,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? c.brandSoft : c.chip,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? c.brand : c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 14,
                color: selected ? c.brand : c.ink3,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? c.brand : c.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pushOption(BuildContext context, ProviderPushMode mode, String key) {
    final c = context.ava;
    return RadioListTile<ProviderPushMode>(
      value: mode,
      // ignore: deprecated_member_use
      groupValue: _pushMode,
      // ignore: deprecated_member_use
      onChanged: _saving ? null : (v) => setState(() => _pushMode = v!),
      title: Text(
        context.tr(key),
        style: TextStyle(fontSize: 13, color: c.ink),
      ),
      activeColor: c.brand,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      dense: true,
    );
  }
}
