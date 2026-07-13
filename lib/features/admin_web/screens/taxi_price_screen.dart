import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../utils/fare_calculator.dart';
import '../../../utils/taxi_price_region.dart';

/// Admin — mahalliy taksi narxi (`settings/prices`).
class TaxiPriceScreen extends StatefulWidget {
  const TaxiPriceScreen({super.key});

  @override
  State<TaxiPriceScreen> createState() => _TaxiPriceScreenState();
}

class _RegionPriceDraft {
  _RegionPriceDraft({
    required this.baseCtrl,
    required this.perKmCtrl,
    required this.coefCtrl,
  });

  final TextEditingController baseCtrl;
  final TextEditingController perKmCtrl;
  final TextEditingController coefCtrl;
  bool enabled = false;

  void dispose() {
    baseCtrl.dispose();
    perKmCtrl.dispose();
    coefCtrl.dispose();
  }
}

class _TaxiPriceScreenState extends State<TaxiPriceScreen> {
  static const _green = AppColors.primaryDark;

  static const _regionLabels = <String, String>{
    'default': 'Default (fallback)',
    'tashkent': 'Toshkent',
    'xorazm': 'Xorazm',
    'samarqand': 'Samarqand',
    'namangan': 'Namangan',
  };

  final _globalBaseCtrl = TextEditingController();
  final _globalPerKmCtrl = TextEditingController();
  final _globalCoefCtrl = TextEditingController(text: '1.0');
  final Map<String, _RegionPriceDraft> _regionDrafts = {};

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _ok;
  String _expandedRegion = '';

  @override
  void initState() {
    super.initState();
    for (final key in _regionLabels.keys) {
      _regionDrafts[key] = _RegionPriceDraft(
        baseCtrl: TextEditingController(),
        perKmCtrl: TextEditingController(),
        coefCtrl: TextEditingController(text: '1.0'),
      );
    }
    _load();
  }

  @override
  void dispose() {
    _globalBaseCtrl.dispose();
    _globalPerKmCtrl.dispose();
    _globalCoefCtrl.dispose();
    for (final d in _regionDrafts.values) {
      d.dispose();
    }
    super.dispose();
  }

  int _parseInt(String raw, {required int fallback}) =>
      int.tryParse(raw.trim()) ?? fallback;

  double _parseCoef(String raw) {
    final v = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return 1.0;
    return v;
  }

  void _fillDraft(_RegionPriceDraft draft, Map<String, dynamic>? data) {
    if (data == null) {
      draft.enabled = false;
      draft.baseCtrl.clear();
      draft.perKmCtrl.clear();
      draft.coefCtrl.text = '1.0';
      return;
    }
    draft.enabled = true;
    draft.baseCtrl.text = '${(data['local_base'] as num?)?.toInt() ?? ''}';
    draft.perKmCtrl.text = '${(data['local_per_km'] as num?)?.toInt() ?? ''}';
    draft.coefCtrl.text =
        '${(data['local_coef'] as num?)?.toDouble() ?? 1.0}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('prices')
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      _globalBaseCtrl.text =
          '${(data['local_base'] as num?)?.toInt() ?? 5000}';
      _globalPerKmCtrl.text =
          '${(data['local_per_km'] as num?)?.toInt() ?? 1500}';
      _globalCoefCtrl.text =
          '${(data['local_coef'] as num?)?.toDouble() ?? 1.0}';

      final regions = data['regions'];
      for (final entry in _regionDrafts.entries) {
        Map<String, dynamic>? regionData;
        if (regions is Map && regions[entry.key] is Map) {
          regionData =
              Map<String, dynamic>.from(regions[entry.key] as Map);
        }
        _fillDraft(entry.value, regionData);
      }
    } catch (e) {
      _error = 'Yuklashda xatolik: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic>? _draftToMap(String regionKey, _RegionPriceDraft draft) {
    if (!draft.enabled) return null;
    final base = int.tryParse(draft.baseCtrl.text.trim());
    final perKm = int.tryParse(draft.perKmCtrl.text.trim());
    final coef = _parseCoef(draft.coefCtrl.text);
    if (base == null || base <= 0 || perKm == null || perKm <= 0) {
      throw FormatException(
        'Mintaqaviy narx noto\'g\'ri: ${_regionLabels[regionKey] ?? regionKey}',
      );
    }
    return {
      'local_base': base,
      'local_per_km': perKm,
      'local_coef': coef,
    };
  }

  int _sampleFare(int base, int perKm, double coef, double km) {
    final raw = ((base + (km * perKm).round()) * coef).round();
    return (raw / 500).round() * 500;
  }

  Future<void> _save() async {
    final base = int.tryParse(_globalBaseCtrl.text.trim());
    final perKm = int.tryParse(_globalPerKmCtrl.text.trim());
    final coef = _parseCoef(_globalCoefCtrl.text);
    if (base == null || base <= 0 || perKm == null || perKm <= 0) {
      setState(() {
        _error = 'Global narx musbat butun son bo\'lishi kerak.';
        _ok = null;
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _ok = null;
    });

    try {
      final regions = <String, dynamic>{};
      for (final entry in _regionDrafts.entries) {
        final map = _draftToMap(entry.key, entry.value);
        if (map != null) regions[entry.key] = map;
      }

      await FirebaseFirestore.instance.collection('settings').doc('prices').set(
        {
          'local_base': base,
          'local_per_km': perKm,
          'local_coef': coef,
          if (regions.isNotEmpty) 'regions': regions,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      if (mounted) {
        setState(() => _ok = 'Saqlandi. Yangi narx keyingi qidiruvdan kuchga kiradi.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Saqlashda xatolik: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final globalBase = _parseInt(_globalBaseCtrl.text, fallback: 5000);
    final globalPerKm = _parseInt(_globalPerKmCtrl.text, fallback: 1500);
    final globalCoef = _parseCoef(_globalCoefCtrl.text);
    final sample5km =
        _sampleFare(globalBase, globalPerKm, globalCoef, 5);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.local_taxi, color: _green, size: 26),
                const SizedBox(width: 10),
                Text(
                  'Mahalliy taksi narxi',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade900,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Formula: (boshlang\'ich + masofa × km_narx) × koeffitsient. '
                'Keyin tungi/bayram va masofa koeffitsientlari qo\'llanadi.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              Text(
                'Umumiy (fallback)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 12),
              _intField(
                label: 'Boshlang\'ich narx (so\'m)',
                hint: '5000',
                controller: _globalBaseCtrl,
                icon: Icons.flag_outlined,
              ),
              const SizedBox(height: 12),
              _intField(
                label: 'Har km uchun (so\'m/km)',
                hint: '1500',
                controller: _globalPerKmCtrl,
                icon: Icons.route_outlined,
              ),
              const SizedBox(height: 12),
              _coefField(
                label: 'Koeffitsient (local_coef)',
                hint: '1.0',
                controller: _globalCoefCtrl,
              ),
              const SizedBox(height: 8),
              Text(
                'Namuna 5 km: $globalBase + 5×$globalPerKm = '
                '${globalBase + 5 * globalPerKm} so\'m × $globalCoef '
                '≈ ${FareCalculator.format(sample5km)} so\'m',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 28),
              Text(
                'Mintaqaviy narxlar (ixtiyoriy)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'GPS bo\'yicha: ${TaxiPriceRegion.resolveKey(lat: 41.55, lng: 60.63)} '
                'va boshqa mintaqalar. Yoqilsa global qiymatni override qiladi.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const SizedBox(height: 8),
              ..._regionLabels.entries.map((e) {
                final draft = _regionDrafts[e.key]!;
                return _regionCard(e.key, e.value, draft);
              }),
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
                  label: Text(_saving ? 'Saqlanmoqda...' : 'Saqlash'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _regionCard(String key, String label, _RegionPriceDraft draft) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        initiallyExpanded: _expandedRegion == key,
        onExpansionChanged: (open) {
          setState(() => _expandedRegion = open ? key : '');
        },
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          draft.enabled
              ? 'Maxsus: ${draft.baseCtrl.text} + km×${draft.perKmCtrl.text} ×${draft.coefCtrl.text}'
              : 'Global fallback ishlatiladi',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mintaqaviy narx yoqilgan'),
                  value: draft.enabled,
                  onChanged: (v) => setState(() => draft.enabled = v),
                ),
                if (draft.enabled) ...[
                  _intField(
                    label: 'Boshlang\'ich (so\'m)',
                    hint: _globalBaseCtrl.text,
                    controller: draft.baseCtrl,
                    icon: Icons.flag_outlined,
                  ),
                  const SizedBox(height: 10),
                  _intField(
                    label: 'Har km (so\'m/km)',
                    hint: _globalPerKmCtrl.text,
                    controller: draft.perKmCtrl,
                    icon: Icons.route_outlined,
                  ),
                  const SizedBox(height: 10),
                  _coefField(
                    label: 'Koeffitsient',
                    hint: _globalCoefCtrl.text,
                    controller: draft.coefCtrl,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _intField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _coefField({
    required String label,
    required String hint,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.tune, size: 20),
            border: const OutlineInputBorder(),
            isDense: true,
            helperText: 'Masalan: 1.0 (o\'zgarmas), 1.2 (+20%), 0.9 (-10%)',
          ),
        ),
      ],
    );
  }
}
