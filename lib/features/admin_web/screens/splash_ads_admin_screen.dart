import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../bread/services/bread_image_storage.dart';
import '../../splash_ad/splash_ad_cache.dart';
import '../services/admin_splash_ads_service.dart';
import '../utils/web_image_compress.dart';

/// Админ — «Splash реклама» (эга 2026-11-28): илова очилишидаги 2 сониялик реклама ўрни.
///
/// Ёзиш фақат `adminUpsertSplashAd` / `adminDeleteSplashAd` (сервер текширади, `admin_audit`).
/// Расм — `platform_images/` га юкланади (мавжуд каталог йўли, сервер фақат Firebase Storage ҳаволасини олади).
class SplashAdsAdminScreen extends StatelessWidget {
  const SplashAdsAdminScreen({super.key, this.service});

  final AdminSplashAdsService? service;

  @override
  Widget build(BuildContext context) {
    final svc = service ?? AdminSplashAdsService();
    return Scaffold(
      appBar: AppBar(title: const Text('Splash реклама')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, svc, null, null),
        icon: const Icon(Icons.add),
        label: const Text('Янги реклама'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: svc.watchAds(),
        builder: (context, snap) {
          if (snap.hasError) return const Center(child: Text('Юклаб бўлмади. Қайта уриниб кўринг.'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              const Text(
                'Илова очилганда 2 сония кўринади (ўтказиб юбориш йўқ). Бир қурилмада кунига энг кўпи '
                '${SplashAdCache.maxPerDay} марта рекламачи креативи, қолган пайт — «Бу ерда сизнинг рекламангиз '
                'бўлиши мумкин». Креатив кейинги очилишда кўринади (олдиндан юкланади, ~3 соатда янгиланади). '
                'Бир нечта мос реклама бўлса — устуворлиги юқориси.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              if (docs.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Реклама йўқ.'))),
              for (final d in docs) _AdTile(id: d.id, data: d.data(), svc: svc),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _openEditor(BuildContext context, AdminSplashAdsService svc, String? id, Map<String, dynamic>? data) =>
    showDialog<void>(context: context, builder: (_) => _SplashAdEditor(svc: svc, id: id, data: data));

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _AdTile extends StatelessWidget {
  const _AdTile({required this.id, required this.data, required this.svc});

  final String id;
  final Map<String, dynamic> data;
  final AdminSplashAdsService svc;

  @override
  Widget build(BuildContext context) {
    DateTime? at(Object? v) => v is Timestamp ? v.toDate() : null;
    final s = at(data['startAt']);
    final e = at(data['endAt']);
    final active = data['active'] == true;
    final districts = data['districts'] is List ? (data['districts'] as List).join(', ') : '';
    final img = '${data['imageUrl'] ?? ''}';
    final now = DateTime.now();
    final running = active && s != null && e != null && !now.isBefore(s) && now.isBefore(e);
    return Card(
      child: ListTile(
        leading: img.isEmpty
            ? const Icon(Icons.text_fields, size: 40)
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(img, width: 56, height: 56, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40)),
              ),
        title: Text('${data['title'] ?? id}'),
        subtitle: FutureBuilder<int>(
          future: svc.impressionsLast7Days(id),
          builder: (context, st) => Text(
            '${running ? 'Ҳозир кўринмоқда' : active ? 'Ёқилган (муддатдан ташқари)' : 'Ўчирилган'} · '
            '${s == null ? '—' : _fmtDate(s)} → ${e == null ? '—' : _fmtDate(e)} · '
            'туманлар: ${districts.isEmpty ? 'барчаси' : districts} · устуворлик ${data['priority'] ?? 0} · '
            '7 кун: ${st.data ?? '…'} марта',
          ),
        ),
        trailing: Wrap(spacing: 4, children: [
          IconButton(
            tooltip: 'Таҳрирлаш',
            icon: const Icon(Icons.edit),
            onPressed: () => _openEditor(context, svc, id, data),
          ),
          IconButton(
            tooltip: 'Ўчириш',
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => _confirmDelete(context),
          ),
        ]),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Рекламани ўчириш'),
        content: Text('«${data['title'] ?? id}» ўчирилади (аввалги ҳолати аудитда сақланади). '
            'Вақтинча тўхтатиш учун «Ёқилган» белгисини олиб ташланг.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Бекор')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ўчириш')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await svc.delete(id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ўчирилди')));
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(splashAdAdminError(err))));
      }
    }
  }
}

class _SplashAdEditor extends StatefulWidget {
  const _SplashAdEditor({required this.svc, this.id, this.data});

  final AdminSplashAdsService svc;
  final String? id;
  final Map<String, dynamic>? data;

  @override
  State<_SplashAdEditor> createState() => _SplashAdEditorState();
}

class _SplashAdEditorState extends State<_SplashAdEditor> {
  late final Map<String, dynamic> _d = widget.data ?? const {};
  late final Map _text = _d['text'] is Map ? _d['text'] as Map : const {};
  late final _title = TextEditingController(text: '${_d['title'] ?? ''}');
  late final _cyr = TextEditingController(text: '${_text['uz_Cyrl'] ?? ''}');
  late final _lat = TextEditingController(text: '${_text['uz_Latn'] ?? ''}');
  late final _ru = TextEditingController(text: '${_text['ru'] ?? ''}');
  late final _link = TextEditingController(text: '${_d['linkUrl'] ?? ''}');
  late final _districts =
      TextEditingController(text: _d['districts'] is List ? (_d['districts'] as List).join(', ') : '');
  late final _priority = TextEditingController(text: '${_d['priority'] ?? 0}');
  late String _imageUrl = '${_d['imageUrl'] ?? ''}';
  late DateTime _start = _d['startAt'] is Timestamp ? (_d['startAt'] as Timestamp).toDate() : _today();
  late DateTime _end = _d['endAt'] is Timestamp
      ? (_d['endAt'] as Timestamp).toDate()
      : _today().add(const Duration(days: 7));
  late bool _active = _d['active'] == true;
  bool _busy = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    for (final c in [_title, _cyr, _lat, _ru, _link, _districts, _priority]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = res?.files.single;
    if (f?.bytes == null) return;
    setState(() => _busy = true);
    try {
      final ext = (f!.extension ?? 'jpg').toLowerCase();
      final prepared = await WebImageCompress.prepareForUpload(f.bytes!,
          mimeHint: ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg');
      final url = await BreadImageStorage().uploadPlatformImage(
        docId: 'splash_${widget.id ?? 'new'}',
        bytes: prepared.bytes,
        contentType: prepared.mime,
        index: 0,
      );
      if (mounted) setState(() => _imageUrl = url);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(backgroundColor: Colors.red, content: Text('Расм юкланмади. Қайта уриниб кўринг.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate(bool start) async {
    final cur = start ? _start : _end;
    final d = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: DateTime(2026),
      lastDate: DateTime(2030),
    );
    if (d == null) return;
    setState(() => start ? _start = d : _end = d);
  }

  Future<void> _save() async {
    // Сана — Тошкент куни: бошланиш 00:00, тугаш куни ҳам киради (кейинги кун 00:00 гача).
    final startMs = DateTime.utc(_start.year, _start.month, _start.day).millisecondsSinceEpoch - 5 * 3600000;
    final endMs = DateTime.utc(_end.year, _end.month, _end.day).add(const Duration(days: 1)).millisecondsSinceEpoch -
        5 * 3600000;
    final ad = <String, Object?>{
      if (widget.id != null) 'id': widget.id,
      'title': _title.text.trim(),
      'text': {'uz_Cyrl': _cyr.text.trim(), 'uz_Latn': _lat.text.trim(), 'ru': _ru.text.trim()},
      'imageUrl': _imageUrl,
      'linkUrl': _link.text.trim(),
      'startAtMs': startMs,
      'endAtMs': endMs,
      'districts': [
        for (final x in _districts.text.split(RegExp(r'[,\s]+')))
          if (x.trim().isNotEmpty) x.trim(),
      ],
      'priority': int.tryParse(_priority.text.trim()) ?? -1,
      'active': _active,
    };
    setState(() => _busy = true);
    try {
      await widget.svc.upsert(ad);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сақланди')));
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(splashAdAdminError(err))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label, {int? max, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          maxLength: max,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.id == null ? 'Янги splash реклама' : 'Splash рекламани таҳрирлаш'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _field(_title, 'Номи (ички, рекламачи)', max: 80),
            Row(children: [
              if (_imageUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Image.network(_imageUrl, height: 90, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(_imageUrl.isEmpty ? 'Расм юклаш' : 'Расмни алмаштириш'),
              ),
              if (_imageUrl.isNotEmpty)
                TextButton(onPressed: _busy ? null : () => setState(() => _imageUrl = ''), child: const Text('Расмсиз')),
            ]),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Расм ёки камида кирилл матн шарт. Тик расм тавсия этилади (≤ 1.5 МБ).',
                  style: TextStyle(color: Colors.black54, fontSize: 12)),
            ),
            _field(_cyr, 'Матн (кирилл)', max: 140),
            _field(_lat, 'Матн (лотин) — бўш бўлса кириллдан автоматик', max: 140),
            _field(_ru, 'Матн (рус) — бўш бўлса кирилл', max: 140),
            _field(_link, 'Ҳавола (ихтиёрий, https://…)'),
            _field(_districts, 'Туманлар ID (вергул билан; бўш — барча туманлар)', hint: 'gurlan, urganch'),
            _field(_priority, 'Устуворлик (0–100)'),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: () => _pickDate(true), child: Text('Бошланиш: ${_fmtDate(_start)}')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(onPressed: () => _pickDate(false), child: Text('Тугаш: ${_fmtDate(_end)}')),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Ёқилган'),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Бекор')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Кутинг…' : 'Сақлаш')),
      ],
    );
  }
}
