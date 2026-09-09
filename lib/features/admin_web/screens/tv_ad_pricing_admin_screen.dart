import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../tv_market/services/tv_ad_service.dart';

/// Admin — AVAGram «Реклама ва Эълонлар» тариф жадвали (`settings/app.tvAdPricing`).
/// 5 тариф × 3 муддат (7/15/30 кун). Firestore rule: `settings/{docId}` —
/// `isAdmin()` бўлса client тўғридан-тўғри ёзади (CF шарт эмас).
class TvAdPricingAdminScreen extends StatefulWidget {
  const TvAdPricingAdminScreen({super.key});

  @override
  State<TvAdPricingAdminScreen> createState() =>
      _TvAdPricingAdminScreenState();
}

class _TvAdPricingAdminScreenState extends State<TvAdPricingAdminScreen> {
  static const _green = AppColors.primaryDark;

  static const _tierLabels = <String, String>{
    'basic': 'Оддий видео',
    'visibility': 'Кўпроқ кўриниш',
    'home': 'Home',
    'premium': 'Premium',
    'pro_max': 'Pro Max',
  };

  final Map<String, Map<int, TextEditingController>> _ctrls = {
    for (final tier in tvAdTiers)
      tier: {
        for (final d in tvAdDurationOptions) d: TextEditingController(),
      },
  };

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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .get();
      final raw = doc.data()?['tvAdPricing'];
      for (final tier in tvAdTiers) {
        final tierRaw = raw is Map ? raw[tier] : null;
        for (final d in tvAdDurationOptions) {
          final fromDoc = tierRaw is Map ? (tierRaw[d.toString()] as num?)?.toInt() : null;
          final fallback = tvAdTierPricingDefault[tier]?[d] ?? 0;
          _ctrls[tier]![d]!.text = '${fromDoc ?? fallback}';
        }
      }
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
      for (final tier in tvAdTiers) {
        final durations = <String, dynamic>{};
        for (final d in tvAdDurationOptions) {
          final v = int.tryParse(_ctrls[tier]![d]!.text.trim());
          if (v == null || v < 0) {
            throw FormatException(
              '${_tierLabels[tier]} — $d кун учун нарх нотўғри',
            );
          }
          durations['$d'] = v;
        }
        pricing[tier] = durations;
      }
      await FirebaseFirestore.instance.collection('settings').doc('app').set(
        {
          'tvAdPricing': pricing,
          'tvAdPricingUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (mounted) {
        setState(() => _ok = 'Сақланди. Янги нарх кейинги эълондан кучга киради.');
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
              Row(children: [
                const Icon(Icons.campaign_outlined, color: _green, size: 26),
                const SizedBox(width: 10),
                Text(
                  'AVAGram реклама нархи',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                '«Реклама ва Эълонлар» — 5 тариф × 7/15/30 кун. Фойдаланувчи '
                'жойлашда шу нархлардан кўради; wallet балансдан ечиб олинади '
                '(`publishTvAd` CF).',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              for (final tier in tvAdTiers) _tierCard(tier),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_ok != null) ...[
                const SizedBox(height: 16),
                Text(
                  _ok!,
                  style: const TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? 'Сақланмоқда...' : 'Сақлаш'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tierCard(String tier) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _tierLabels[tier] ?? tier,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final d in tvAdDurationOptions) ...[
                  Expanded(child: _priceField(tier, d)),
                  if (d != tvAdDurationOptions.last) const SizedBox(width: 10),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceField(String tier, int days) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$days кун', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: _ctrls[tier]![days],
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            suffixText: 'сўм',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
