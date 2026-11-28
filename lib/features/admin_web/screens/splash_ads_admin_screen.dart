import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../bread/services/bread_image_storage.dart';
import '../../splash_ad/splash_ad.dart';
import '../../splash_ad/splash_ad_prefetcher.dart' show SplashAdPrefetcher;
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
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Splash реклама'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Рекламалар'),
            Tab(key: SplashAdsAdminScreen.moderationTabKey, text: 'Модерация'),
            Tab(key: SplashAdsAdminScreen.tariffTabKey, text: 'Тариф ва созлама'),
          ]),
        ),
        body: TabBarView(children: [
          _AdsTab(svc: svc),
          _ModerationTab(svc: svc),
          _TariffTab(svc: svc),
        ]),
      ),
    );
  }

  static const moderationTabKey = Key('splash-admin-moderation');
  static const tariffTabKey = Key('splash-admin-tariff');
}

class _AdsTab extends StatelessWidget {
  const _AdsTab({required this.svc});

  final AdminSplashAdsService svc;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                'Илова ҲАР очилганда 2 сония кўринади (ўтказиб юбориш йўқ). Бир нечта мос реклама бўлса — '
                'навбат билан, ОҒИРЛИК бўйича (пуллик: кунига тўланган сумма; админ рекламаси: шу ерда белгиланади, '
                'сўм/кун эквиваленти). Мос реклама йўқ пайт — «Бу ерда сизнинг рекламангиз бўлиши мумкин». '
                'Креативлар олдиндан юкланади (~3 соатда янгиланади).',
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

String _areaLabel(Map<String, dynamic> o) => switch ('${o['areaLevel'] ?? ''}') {
      'district' => 'туманлар: ${o['districts'] is List ? (o['districts'] as List).join(', ') : ''}',
      'region' => 'вилоят: ${o['regionId'] ?? ''}',
      _ => 'бутун республика',
    };

/// Модерация навбати: тасдиқлаш (реклама ёқилади) ёки рад этиш (сабаб + ТЎЛИҚ қайтариш).
class _ModerationTab extends StatelessWidget {
  const _ModerationTab({required this.svc});

  final AdminSplashAdsService svc;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: svc.watchOrders('pending'),
      builder: (context, snap) {
        if (snap.hasError) return const Center(child: Text('Юклаб бўлмади. Қайта уриниб кўринг.'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = [...snap.data!.docs]..sort((a, b) {
            final x = a.data()['createdAt'], y = b.data()['createdAt'];
            return x is Timestamp && y is Timestamp ? x.compareTo(y) : 0;
          });
        if (docs.isEmpty) return const Center(child: Text('Модерация кутаётган реклама йўқ.'));
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [for (final d in docs) _OrderCard(id: d.id, o: d.data(), svc: svc)],
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.id, required this.o, required this.svc});

  final String id;
  final Map<String, dynamic> o;
  final AdminSplashAdsService svc;

  Future<void> _act(BuildContext context, String decision) async {
    String reason = '';
    if (decision == 'reject') {
      final c = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Рад этиш'),
          content: TextField(
            controller: c,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Сабаб (рекламачига юборилади)', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Бекор')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Рад этиш ва пулни қайтариш')),
          ],
        ),
      );
      reason = c.text.trim();
      c.dispose();
      if (ok != true) return;
    }
    try {
      await svc.moderate(id, decision, reason: reason);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(decision == 'approve' ? 'Тасдиқланди — реклама ёқилди' : 'Рад этилди — пул қайтарилди')));
      }
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(splashAdAdminError(err))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cr = o['creative'] is Map ? Map<String, dynamic>.from(o['creative'] as Map) : <String, dynamic>{};
    final img = '${cr['imageUrl'] ?? ''}';
    final text = cr['text'] is Map ? '${(cr['text'] as Map)['uz_Cyrl'] ?? ''}' : '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (img.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Image.network(img, width: 120, height: 160, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48)),
            ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${o['startDay'] ?? ''} дан ${o['days'] ?? 0} кун · ${_areaLabel(o)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('Тўланди: ${o['amount'] ?? 0} сўм (кунига ${o['pricePerDay'] ?? 0}) · тариф v${o['tariffVersion'] ?? '?'}'),
              Text('Рекламачи: ***${'${o['uid'] ?? ''}'.length >= 4 ? '${o['uid']}'.substring('${o['uid']}'.length - 4) : ''}'),
              if (text.isNotEmpty) Text('Матн: $text'),
              if ('${cr['linkUrl'] ?? ''}'.isNotEmpty) Text('Ҳавола: ${cr['linkUrl']}'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                FilledButton(onPressed: () => _act(context, 'approve'), child: const Text('Тасдиқлаш')),
                OutlinedButton(onPressed: () => _act(context, 'reject'), child: const Text('Рад этиш')),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Тариф (ўзгармас версиялар) ва босқич (OFF / INTERNAL / PILOT / PUBLIC).
class _TariffTab extends StatefulWidget {
  const _TariffTab({required this.svc});

  final AdminSplashAdsService svc;

  @override
  State<_TariffTab> createState() => _TariffTabState();
}

class _TariffTabState extends State<_TariffTab> {
  final _district = TextEditingController();
  final _region = TextEditingController();
  final _republic = TextEditingController();
  final _note = TextEditingController();
  final _phones = TextEditingController();
  final _pilot = TextEditingController();
  String _stage = 'off';
  Map<String, dynamic>? _s;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_district, _region, _republic, _note, _phones, _pilot]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.svc.settings();
      if (!mounted) return;
      final cfg = s['config'] is Map ? s['config'] as Map : const {};
      final per = s['tariff'] is Map && (s['tariff'] as Map)['perDay'] is Map ? (s['tariff'] as Map)['perDay'] as Map : const {};
      setState(() {
        _s = s;
        _stage = '${cfg['stage'] ?? 'off'}';
        _phones.text = cfg['internalPhones'] is List ? (cfg['internalPhones'] as List).join(', ') : '';
        _pilot.text = cfg['pilotDistrictIds'] is List ? (cfg['pilotDistrictIds'] as List).join(', ') : '';
        _district.text = '${per['district'] ?? ''}';
        _region.text = '${per['region'] ?? ''}';
        _republic.text = '${per['republic'] ?? ''}';
      });
    } catch (err) {
      if (mounted) setState(() => _s = {'error': splashAdAdminError(err)});
    }
  }

  List<String> _split(String s) => [for (final x in s.split(RegExp(r'[,\s]+'))) if (x.trim().isNotEmpty) x.trim()];

  Future<void> _run(Future<void> Function() f, String ok) async {
    setState(() => _busy = true);
    try {
      await f();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      await _load();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(splashAdAdminError(err))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _num(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, suffixText: 'сўм/кун', border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) return const Center(child: CircularProgressIndicator());
    if (s['error'] != null) return Center(child: Text('${s['error']}'));
    final versions = s['tariffVersions'] is List ? s['tariffVersions'] as List : const [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Тариф (кунлик нарх, бутун сўм)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const Text(
          'Нарх = кунлик нарх × кун (туман даражасида × танланган туманлар сони). Ҳар сақлаш — янги ўзгармас версия; '
          'аввал тўланган буюртмалар ўз нархида қолади.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 10),
        _num(_district, 'Бир туман'),
        _num(_region, 'Бутун вилоят'),
        _num(_republic, 'Бутун республика'),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Изоҳ (ихтиёрий)', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                    () => widget.svc.publishTariff(
                      district: int.tryParse(_district.text.trim()) ?? 0,
                      region: int.tryParse(_region.text.trim()) ?? 0,
                      republic: int.tryParse(_republic.text.trim()) ?? 0,
                      note: _note.text.trim(),
                    ),
                    'Янги тариф версияси сақланди',
                  ),
          child: const Text('Янги тариф версиясини сақлаш'),
        ),
        const SizedBox(height: 6),
        for (final v in versions.take(5))
          if (v is Map) Text('v${v['version']}: ${v['perDay']} ${v['note'] ?? ''}', style: const TextStyle(fontSize: 12)),
        const Divider(height: 32),
        const Text('Сотиш босқичи', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        Wrap(spacing: 8, children: [
          for (final st in const ['off', 'internal', 'pilot', 'public'])
            ChoiceChip(
              label: Text(const {'off': 'Ўчиқ', 'internal': 'Ички', 'pilot': 'Пилот', 'public': 'Ҳамма'}[st]!),
              selected: _stage == st,
              onSelected: (_) => setState(() => _stage = st),
            ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _phones,
          decoration: const InputDecoration(labelText: 'Ички синовчилар (998…, вергул билан)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _pilot,
          decoration: const InputDecoration(labelText: 'Пилот туманлар ID (вергул билан)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                    () => widget.svc.saveConfig(stage: _stage, internalPhones: _split(_phones.text), pilotDistrictIds: _split(_pilot.text)),
                    'Созлама сақланди',
                  ),
          child: const Text('Босқични сақлаш'),
        ),
      ],
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
    final regions = data['regionIds'] is List ? (data['regionIds'] as List).join(', ') : '';
    final paid = data['source'] == 'paid';
    final house = data['house'] == true;
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
            '${paid ? 'ПУЛЛИК · ' : ''}${house ? 'НАМУНА · ' : ''}ҳудуд: ${districts.isEmpty && regions.isEmpty ? 'барчаси' : [districts, regions].where((x) => x.isNotEmpty).join(' / ')} · оғирлик ${data['weight'] ?? 1} · '
            '7 кун: ${st.data ?? '…'} марта',
          ),
        ),
        trailing: Wrap(spacing: 4, children: [
          IconButton(
            tooltip: 'Таҳрирлаш',
            icon: const Icon(Icons.edit),
            onPressed: paid ? null : () => _openEditor(context, svc, id, data),
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
  late final _regions =
      TextEditingController(text: _d['regionIds'] is List ? (_d['regionIds'] as List).join(', ') : '');
  late final _weight = TextEditingController(text: '${_d['weight'] ?? 1}');
  late String _imageUrl = '${_d['imageUrl'] ?? ''}';
  late DateTime _start = _d['startAt'] is Timestamp ? (_d['startAt'] as Timestamp).toDate() : _today();
  late DateTime _end = _d['endAt'] is Timestamp
      ? (_d['endAt'] as Timestamp).toDate()
      : _today().add(const Duration(days: 7));
  late bool _active = _d['active'] == true;
  late bool _house = _d['house'] == true;
  bool _busy = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    for (final c in [_title, _cyr, _lat, _ru, _link, _districts, _regions, _weight]) {
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
      // Эга 2026-11-28: клиент кеши 1500 КБ дан каттасини кўрсатмайди — юклашда шу чегарагача сиқилади.
      final prepared = await WebImageCompress.prepareForUploadMax(f.bytes!,
          maxBytes: SplashAdPrefetcher.maxImageBytes,
          mimeHint: ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg');
      final url = await BreadImageStorage().uploadPlatformImage(
        docId: 'splash_${widget.id ?? 'new'}',
        bytes: prepared.bytes,
        contentType: prepared.mime,
        index: 0,
      );
      if (mounted) setState(() => _imageUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(e is StateError ? e.message : 'Расм юкланмади. Қайта уриниб кўринг.')));
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
      'regionIds': [
        for (final x in _regions.text.split(RegExp(r'[,\s]+')))
          if (x.trim().isNotEmpty) x.trim(),
      ],
      'priority': _d['priority'] is int ? _d['priority'] as int : 0,
      'weight': int.tryParse(_weight.text.trim()) ?? 0,
      'active': _active,
      'house': _house,
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
            Padding(
              key: const ValueKey('splash-admin-creative-spec'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Расм ёки камида кирилл матн шарт. ${SplashAdTexts.creativeSpec('uz_Cyrl')}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ),
            _field(_cyr, 'Матн (кирилл)', max: 140),
            _field(_lat, 'Матн (лотин) — бўш бўлса кириллдан автоматик', max: 140),
            _field(_ru, 'Матн (рус) — бўш бўлса кирилл', max: 140),
            _field(_link, 'Ҳавола (ихтиёрий, https://…)'),
            _field(_districts, 'Туманлар ID (вергул билан)', hint: 'gurlan, urganch'),
            _field(_regions, 'Вилоятлар ID (вергул билан; иккаласи бўш — бутун республика)', hint: 'xorazm'),
            _field(_weight, 'Оғирлик (айланишдаги улуш, сўм/кун эквиваленти)', hint: '50000'),
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
            SwitchListTile(
              key: const ValueKey('splash-admin-house'),
              contentPadding: EdgeInsets.zero,
              value: _house,
              onChanged: (v) => setState(() => _house = v),
              title: const Text('Намуна реклама (AVA чорлови)'),
              subtitle: const Text('Фақат ҳудудда бошқа реклама бўлмаганда кўрсатилади; босилса — «Реклама бериш».'),
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
