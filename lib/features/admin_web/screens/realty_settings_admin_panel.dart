import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';

/// Admin — 🏠 Кўчмас мулк нархлари ва созламалари.
///
/// `settings/app` ҳужжатига ёзади: `realtyPricing`, `realtyAgentPhone`,
/// `realtyAutoApprove`. Firestore rule: `settings/{docId}` — `isAdmin()`
/// бўлса client тўғридан-тўғри ёзади (`tv_ad_pricing_admin_screen.dart`
/// билан бир хил нақш, CF шарт эмас).
///
/// Бошланғич қийматлар серверdan (`getRealtyPricing`) олинади — default
/// нархлар CF ичида турибди, бу ерда такрорланмайди.
class RealtySettingsAdminPanel extends StatefulWidget {
  const RealtySettingsAdminPanel({super.key});

  @override
  State<RealtySettingsAdminPanel> createState() =>
      _RealtySettingsAdminPanelState();
}

class _RealtySettingsAdminPanelState extends State<RealtySettingsAdminPanel> {
  static const _green = AppColors.primaryDark;

  static const _paidTiers = [RealtyTier.promo, RealtyTier.urgent];

  static const _tierLabels = <RealtyTier, String>{
    RealtyTier.promo: 'РЕКЛАМА',
    RealtyTier.urgent: 'СРОЧНО',
  };

  final _repo = RealtyRepository();

  final Map<RealtyTier, Map<int, TextEditingController>> _ctrls = {
    for (final tier in _paidTiers)
      tier: {
        for (final d in tier.durationOptions) d: TextEditingController(),
      },
  };
  final _agentPhoneCtrl = TextEditingController();

  bool _autoApprove = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _ok;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final tierMap in _ctrls.values) {
      for (final c in tierMap.values) {
        c.dispose();
      }
    }
    _agentPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pricing = await _repo.loadPricing();
      for (final tier in _paidTiers) {
        for (final d in tier.durationOptions) {
          _ctrls[tier]![d]!.text = '${pricing[tier]?[d] ?? 0}';
        }
      }
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      _agentPhoneCtrl.text = '${data['realtyAgentPhone'] ?? ''}';
      _autoApprove = data['realtyAutoApprove'] != false;
    } catch (e) {
      _error = 'Юклашда хатолик: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _ok = null;
    });
    try {
      final pricing = <String, dynamic>{};
      for (final tier in _paidTiers) {
        final durations = <String, dynamic>{};
        for (final d in tier.durationOptions) {
          final v = int.tryParse(_ctrls[tier]![d]!.text.trim());
          if (v == null || v < 0) {
            throw FormatException(
              '${_tierLabels[tier]} — $d кун учун нарх нотўғри',
            );
          }
          durations['$d'] = v;
        }
        pricing[tier.key] = durations;
      }

      // Концепция талаби: СРОЧНО РЕКЛАМАдан қиммат. Бир хил муддатда
      // тескари бўлса, бу тариф хатоси — сақлашдан олдин тўхтатамиз.
      for (final d in RealtyTier.urgent.durationOptions) {
        final urgent = pricing['urgent'][ '$d'] as int?;
        final promo = pricing['promo']['$d'] as int?;
        if (urgent != null && promo != null && urgent <= promo) {
          throw FormatException(
            '$d кун: СРОЧНО ($urgent) РЕКЛАМАдан ($promo) қиммат бўлиши керак',
          );
        }
      }

      final phone = _agentPhoneCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (phone.isNotEmpty && phone.length < 9) {
        throw const FormatException('Риэлтор рақами нотўғри');
      }

      await FirebaseFirestore.instance.collection('settings').doc('app').set(
        {
          'realtyPricing': pricing,
          'realtyAgentPhone': phone,
          'realtyAutoApprove': _autoApprove,
          'realtyPricingUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (mounted) {
        setState(() =>
            _ok = 'Сақланди. Янги нарх кейинги сотиб олишдан кучга киради.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Сақлашда хатолик: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: const [
                Icon(Icons.apartment_outlined, color: _green, size: 26),
                SizedBox(width: 10),
                Text(
                  'Кўчмас мулк — нарх ва созламалар',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ]),
              const SizedBox(height: 6),
              const Text(
                'Нарх сўмда. ОДДИЙ эълон бепул (ҳар бир фойдаланувчига '
                '2 тагача) — бу ерда созланмайди.',
                style: TextStyle(fontSize: AppText.bodySmall),
              ),
              const SizedBox(height: 20),

              for (final tier in _paidTiers) ...[
                Text(
                  _tierLabels[tier]!,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final d in tier.durationOptions) ...[
                      Expanded(
                        child: TextField(
                          controller: _ctrls[tier]![d],
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: '$d кун',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
              ],

              const Divider(height: 32),
              TextField(
                controller: _agentPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'AVA риэлторлик хизмати рақами',
                  helperText: 'Бўш бўлса — харидор эга рақамига қўнғироқ қилади',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                value: _autoApprove,
                onChanged: (v) => setState(() => _autoApprove = v),
                title: const Text('Эълонлар текширувсиз лентага тушсин'),
                subtitle: const Text(
                  'Ўчирилса — ҳар бир янги ва таҳрирланган эълон '
                  '«Текширувда» бўлимига тушади',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 20),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_ok != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_ok!, style: const TextStyle(color: _green)),
                ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Сақланмоқда...' : 'Сақлаш'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _saving ? null : _load,
                    child: const Text('Қайта юклаш'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
