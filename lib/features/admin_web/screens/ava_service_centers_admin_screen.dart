import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/geo/uz_bounds.dart';
import '../../../core/widgets/service_area_picker.dart';
import '../../../models/map_picker_result.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';
import '../../../repositories/service_config_repository.dart';
import '../../map_picker/screens/map_picker_screen.dart';

/// AVA Сервис марказлари — ҳар туман учун битта (эга 2026-11-03: «ҳар битта туман учун Админ
/// белгилайди»). Сақланадиган жой — `oil_change_services/ava_<districtId>` (Мой алмаштириш сервис
/// нуқталари билан БИР тўплам; rules: write = isAdmin). Мижозда: «Менинг машинам» ва «Мой алмаштириш».
class AvaServiceCentersAdminScreen extends StatefulWidget {
  const AvaServiceCentersAdminScreen({super.key, this.repo});

  final OilChangeRepository? repo;

  @override
  State<AvaServiceCentersAdminScreen> createState() => _AvaServiceCentersAdminScreenState();
}

/// Киритилганни текшириш (соф функция — тест учун). → хато матни ёки `null`.
@visibleForTesting
String? validateAvaCenterInput({
  required String districtId,
  required String name,
  required String phone,
  required double? lat,
  required double? lng,
}) {
  if (districtId.trim().isEmpty) return 'Туманни танланг';
  if (name.trim().length < 2) return 'Номини ёзинг';
  if (phone.replaceAll(RegExp(r'\D'), '').length < 9) return 'Телефон нотўғри';
  if (!inUzbekistanBounds(lat, lng)) return 'Жойни харитада белгиланг (координата Ўзбекистон ичида бўлсин)';
  return null;
}

class _AvaServiceCentersAdminScreenState extends State<AvaServiceCentersAdminScreen> {
  late final OilChangeRepository _repo = widget.repo ?? OilChangeRepository();
  late final Future<Map<String, String>> _districtNames = _loadDistrictNames();

  Future<Map<String, String>> _loadDistrictNames() async {
    final list = await ServiceConfigRepository().fetchAllDistricts(activeOnly: false);
    return {for (final d in list) d.id: d.nameFor('uz_Cyrl')};
  }

  Future<void> _edit(OilServicePoint? existing) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _AvaCenterDialog(repo: _repo, existing: existing),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сақланди')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AVA Сервис марказлари')),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('ava_center_add'),
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('Марказ қўшиш'),
      ),
      body: FutureBuilder<Map<String, String>>(
        future: _districtNames,
        builder: (context, names) {
          return StreamBuilder<List<OilServicePoint>>(
            stream: _repo.watchAvaCenters(),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(child: Text('Юклаб бўлмади: ${snap.error}'));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final dn = names.data ?? const <String, String>{};
              final list = [...snap.data!]
                ..sort((a, b) => (dn[a.districtId] ?? a.districtId).compareTo(dn[b.districtId] ?? b.districtId));
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Text(
                    'Ҳар туман учун битта марказ. Мижоз «Менинг машинам» ва «Мой алмаштириш»да ўз '
                    '(тепада кўрсатилган) туманининг марказини кўради: номи, манзили, қўнғироқ ва йўл. '
                    'Марказ бўлмаса — диспетчер телефони.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Ҳали марказ йўқ')),
                    ),
                  for (final c in list)
                    Card(
                      child: ListTile(
                        key: ValueKey('ava_center_${c.districtId}'),
                        leading: Icon(
                          c.active ? Icons.build_circle : Icons.pause_circle,
                          color: c.active ? Colors.green.shade700 : Colors.grey,
                        ),
                        title: Text('${dn[c.districtId] ?? c.districtId} — ${c.name}'),
                        subtitle: Text([
                          if (c.address.isNotEmpty) c.address,
                          if (c.phone.isNotEmpty) c.phone,
                          c.hasLocation
                              ? '${c.lat!.toStringAsFixed(5)}, ${c.lng!.toStringAsFixed(5)}'
                              : 'Жой белгиланмаган',
                          if (!c.active) 'Ўчиқ',
                        ].join(' · ')),
                        trailing: const Icon(Icons.edit),
                        onTap: () => _edit(c),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _AvaCenterDialog extends StatefulWidget {
  const _AvaCenterDialog({required this.repo, this.existing});

  final OilChangeRepository repo;
  final OilServicePoint? existing;

  @override
  State<_AvaCenterDialog> createState() => _AvaCenterDialogState();
}

class _AvaCenterDialogState extends State<_AvaCenterDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? 'AVA Сервис маркази');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _address = TextEditingController(text: widget.existing?.address ?? '');
  late final _lat = TextEditingController(text: widget.existing?.lat?.toStringAsFixed(6) ?? '');
  late final _lng = TextEditingController(text: widget.existing?.lng?.toStringAsFixed(6) ?? '');
  late String _districtId = widget.existing?.districtId ?? '';
  late bool _active = widget.existing?.active ?? true;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _lat, _lng]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final r = await Navigator.of(context).push<MapPickerResult>(
      MaterialPageRoute(builder: (_) => const MapPickerScreen(title: 'Марказ жойини белгилаш')),
    );
    if (r == null || !mounted) return;
    setState(() {
      _lat.text = r.lat.toStringAsFixed(6);
      _lng.text = r.lng.toStringAsFixed(6);
      if (_address.text.trim().isEmpty) _address.text = r.label;
      _error = null;
    });
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final lat = _num(_lat);
    final lng = _num(_lng);
    final err = validateAvaCenterInput(
      districtId: _districtId,
      name: _name.text,
      phone: _phone.text,
      lat: lat,
      lng: lng,
    );
    if (err != null) return setState(() => _error = err);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.saveAvaCenter(
        OilServicePoint(
          id: OilServicePoint.avaCenterId(_districtId),
          name: _name.text.trim(),
          phone: _phone.text.replaceAll(RegExp(r'[^\d+]'), ''),
          address: _address.text.trim(),
          lat: lat,
          lng: lng,
          active: _active,
          districtId: _districtId,
          isAvaCenter: true,
        ),
        actor: (FirebaseAuth.instance.currentUser?.phoneNumber ?? '').replaceAll(RegExp(r'\D'), ''),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Сақлаб бўлмади: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'Янги AVA Сервис маркази' : 'Марказни таҳрирлаш'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isNew)
                ServiceAreaPicker(
                  showAreaDropdown: false,
                  onChanged: (_, districtId, __) => _districtId = districtId,
                )
              else
                Text('Туман: ${widget.existing!.districtId} (ўзгартириб бўлмайди — туманга битта марказ)',
                    style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 12),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Номи')),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Телефон'),
              ),
              TextField(controller: _address, decoration: const InputDecoration(labelText: 'Манзил (матн)')),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lat,
                      decoration: const InputDecoration(labelText: 'Кенглик (lat)'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lng,
                      decoration: const InputDecoration(labelText: 'Узунлик (lng)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('ava_center_pick_map'),
                onPressed: _busy ? null : _pickOnMap,
                icon: const Icon(Icons.map),
                label: const Text('Харитада белгилаш'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Фаол (мижозларга кўринади)'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Бекор')),
        FilledButton(
          key: const ValueKey('ava_center_save'),
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Сақлаш'),
        ),
      ],
    );
  }
}
