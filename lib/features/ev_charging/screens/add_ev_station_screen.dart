import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/ev_charging_station.dart';
import '../../../repositories/ev_station_repository.dart';
import '../../../services/location_service.dart';
import '../../profile/screens/wallet_screen.dart';

/// 12-band: xarita orqali nuqta tanlash (tap / joriy GPS / drag) — koordinata
/// majburiy, keyin ixtiyoriy forma. `editing` berilsa — 19-band "Текшириш"
/// oqимi: koordinata o'zgarmaydi, faqat ixtiyoriy maydonlar to'ldiriladi/
/// to'g'irlanadi.
///
/// 2026-09-22 (эга қарори): янги станция қўшиш ПУЛЛИК — `editing==null`
/// бўлганда [tariff] МАЖБУРИЙ (харита экранидаги [EvStationTariffSheet]дан
/// келади); сақлаш `EvStationRepository.payAndCreateStation()` орқали
/// (AVA ҳамёнидан тўлов + станция яратиш — атомик).
class AddEvStationScreen extends StatefulWidget {
  const AddEvStationScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.editing,
    this.tariff,
    this.phone,
  }) : assert(
          editing != null || tariff != null,
          'Янги станция қўшишда tariff мажбурий (EvStationTariffSheet орқали танланади).',
        );

  final double? initialLat;
  final double? initialLng;
  final EvChargingStation? editing;

  /// Танланган тариф — фақат яратишда (`editing == null`).
  final EvStationTariff? tariff;

  /// Баланс етмаса "Тўлдириш" тугмаси учун (фақат яратишда керак).
  final String? phone;

  @override
  State<AddEvStationScreen> createState() => _AddEvStationScreenState();
}

class _AddEvStationScreenState extends State<AddEvStationScreen> {
  static const _connectorsAll = ['CCS2', 'Type 2', 'GB/T', 'CHAdeMO', 'Бошқа'];
  static const _chargingTypesAll = ['AC', 'DC', 'AC+DC'];

  double? _lat;
  double? _lng;
  final _selectedConnectors = <String>{};
  final _selectedChargingTypes = <String>{};
  final _powerCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _operatorCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  bool _saving = false;
  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing != null) {
      _lat = editing.latitude;
      _lng = editing.longitude;
      _selectedChargingTypes.addAll(editing.chargingTypes);
      _selectedConnectors.addAll(editing.connectors);
      if (editing.powerKw != null) _powerCtrl.text = '${editing.powerKw}';
      if (editing.price != null) _priceCtrl.text = '${editing.price}';
      _operatorCtrl.text = editing.operatorName ?? '';
      _noteCtrl.text = editing.note ?? '';
    } else {
      _lat = widget.initialLat;
      _lng = widget.initialLng;
    }
  }

  @override
  void dispose() {
    _powerCtrl.dispose();
    _priceCtrl.dispose();
    _operatorCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _useCurrentGps() async {
    try {
      final coords = await context.read<LocationService>().getCurrentCoords();
      if (!mounted) return;
      setState(() {
        _lat = coords.lat;
        _lng = coords.lng;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is LocationException
              ? LocationException.userMessage(e.kind)
              : 'GPS xatosi'),
        ),
      );
    }
  }

  Future<bool> _confirmDuplicates(List<EvChargingStation> dups) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Яқин атрофда нуқта бор'),
        content: Text(
          'Ушбу жойдан ${dups.length} та зарядлаш нуқтаси аллақачон мавжуд. '
          'Баribир davom etasizmi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Давом этиш'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _save() async {
    if (_lat == null || _lng == null) return;
    setState(() => _saving = true);
    final repo = context.read<EvStationRepository>();
    try {
      if (!_isEditing) {
        final dups = await repo.findDuplicatesNear(_lat!, _lng!);
        if (dups.isNotEmpty) {
          final proceed = await _confirmDuplicates(dups);
          if (!proceed) {
            if (mounted) setState(() => _saving = false);
            return;
          }
        }
        final ok = await _confirmPayment();
        if (!ok) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        await repo.payAndCreateStation(
          tariffId: widget.tariff!.id,
          lat: _lat!,
          lng: _lng!,
          chargingTypes: _selectedChargingTypes.toList(),
          connectors: _selectedConnectors.toList(),
          powerKw: num.tryParse(_powerCtrl.text),
          price: num.tryParse(_priceCtrl.text),
          operatorName: _operatorCtrl.text,
          note: _noteCtrl.text,
        );
      } else {
        await repo.updateStationDetails(
          widget.editing!.id,
          chargingTypes: _selectedChargingTypes.toList(),
          connectors: _selectedConnectors.toList(),
          powerKw: num.tryParse(_powerCtrl.text),
          price: num.tryParse(_priceCtrl.text),
          operatorName: _operatorCtrl.text,
          note: _noteCtrl.text,
        );
      }
      if (mounted) Navigator.pop(context);
    } on EvStationPaymentException catch (e) {
      if (!mounted) return;
      if (e.isInsufficientBalance) {
        final balance = (e.details['balance'] as num?)?.toInt();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(balance != null
              ? 'Баланс етарли эмас (${formatMoney(balance)}) — аввал ҳамённи тўлдиринг.'
              : 'Баланс етарли эмас — аввал ҳамённи тўлдиринг.'),
          action: widget.phone == null
              ? null
              : SnackBarAction(
                  label: 'Тўлдириш',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => WalletScreen(phone: widget.phone!)),
                  ),
                ),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Тўлов амалга ошмади: ${e.code}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Хатолик: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmPayment() async {
    final tariff = widget.tariff!;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Тўловни тасдиқлаш'),
        content: Text(
          '${formatMoney(tariff.price)} ҳамёндан ечилади ва станция '
          'шу заҳоти харитада кўринади. Давом этасизми?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор қилиш'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Тўлаш — ${formatMoney(tariff.price)}'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _lat != null && _lng != null && !_saving;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(_isEditing
            ? 'Маълумотни текшириш'
            : 'Зарядлаш станциясини қўшиш'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (!_isEditing) _buildLocationPicker(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isEditing) ...[
                  Text(
                    '📍 ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F8E9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFA5D6A7)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.workspace_premium_rounded,
                            color: AppColors.primaryDark, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Танланган тариф: ${widget.tariff!.months} ой — '
                            '${formatMoney(widget.tariff!.price)}',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _sectionTitle('⚡ Қувватлаш тури'),
                _chipsRow(_chargingTypesAll, _selectedChargingTypes),
                const SizedBox(height: 16),
                _sectionTitle('🔌 Разъём'),
                _chipsRow(_connectorsAll, _selectedConnectors),
                const SizedBox(height: 16),
                _sectionTitle('🔋 Қувват (kW)'),
                TextField(
                  controller: _powerCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'Масалан: 60'),
                ),
                const SizedBox(height: 16),
                _sectionTitle('💰 Нарх (1 kWh, сўм)'),
                TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(hintText: 'Масалан: 1500'),
                ),
                const SizedBox(height: 16),
                _sectionTitle('🏢 Оператор номи'),
                TextField(controller: _operatorCtrl),
                const SizedBox(height: 16),
                _sectionTitle('📝 Изоҳ'),
                TextField(controller: _noteCtrl, maxLines: 3),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: canSave ? _save : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isEditing
                            ? 'Сақлаш'
                            : 'Тўлаш ва сақлаш — ${formatMoney(widget.tariff!.price)}'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationPicker() {
    final hasCoords = _lat != null && _lng != null;
    return Column(
      children: [
        SizedBox(
          height: 260,
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(_lat ?? 41.55, _lng ?? 60.6),
                  zoom: 15,
                ),
                onTap: (pos) => setState(() {
                  _lat = pos.latitude;
                  _lng = pos.longitude;
                }),
                markers: hasCoords
                    ? {
                        Marker(
                          markerId: const MarkerId('new_station'),
                          position: LatLng(_lat!, _lng!),
                          draggable: true,
                          onDragEnd: (pos) => setState(() {
                            _lat = pos.latitude;
                            _lng = pos.longitude;
                          }),
                        ),
                      }
                    : {},
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: FloatingActionButton.small(
                  heroTag: 'ev_use_gps',
                  onPressed: _useCurrentGps,
                  child: const Icon(Icons.my_location),
                ),
              ),
            ],
          ),
        ),
        if (!hasCoords)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Text(
              'Харитадан нуқтани танланг ёки жойлашувдан фойдаланинг — координата мажбурий.',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      );

  Widget _chipsRow(List<String> options, Set<String> selected) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        final isOn = selected.contains(o);
        return FilterChip(
          label: Text(o),
          selected: isOn,
          onSelected: (v) => setState(() {
            if (v) {
              selected.add(o);
            } else {
              selected.remove(o);
            }
          }),
        );
      }).toList(),
    );
  }
}
