import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/oil_catalog_repository.dart';
import '../../bread/services/bread_image_storage.dart';
import '../../oil_change/data/oil_catalog.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_oil_catalog_service.dart';

/// Админ: мой ва фильтр каталоги + расм юклаш.
class OilCatalogAdminScreen extends StatefulWidget {
  const OilCatalogAdminScreen({super.key});

  @override
  State<OilCatalogAdminScreen> createState() => _OilCatalogAdminScreenState();
}

class _OilCatalogAdminScreenState extends State<OilCatalogAdminScreen>
    with SingleTickerProviderStateMixin {
  final _repo = OilCatalogRepository();
  final _adminApi = AdminOilCatalogService();
  late final TabController _tabs;
  bool _seeding = false;

  String get _adminPhone =>
      context.read<AdminAuthService>().phoneDigits ?? '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: error ? Colors.red : AppColors.button,
        content: Text(msg),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _seed() async {
    if (_seeding) return;
    setState(() => _seeding = true);
    try {
      final items = <Map<String, dynamic>>[];
      var order = 0;
      for (final p in [...OilCatalog.oils, ...OilCatalog.filters]) {
        final name = p.fixedName ?? (_seedTr[p.nameKey] ?? p.nameKey);
        final meta = _seedTr[p.metaKey] ?? p.metaKey;
        final reason = _seedTr[p.reasonKey] ?? p.reasonKey;
        final specs = <String, String>{};
        for (final e in p.specKeys.entries) {
          final label = _seedTr[e.key] ?? e.key;
          final value = e.value.startsWith('oil_')
              ? (_seedTr[e.value] ?? e.value)
              : e.value;
          specs[label] = value;
        }
        items.add({
          'id': p.id,
          'kind': p.isFilter ? 'filter' : 'oil',
          'name': name,
          'meta': meta,
          'reason': reason,
          'price': p.price,
          'specs': specs,
          'sortOrder': order++,
          'must': p.must,
          'dust': p.dust,
          'gas': p.gas,
        });
      }
      final n = await _adminApi.seed(
        adminPhone: _adminPhone,
        items: items,
      );
      if (!mounted) return;
      _toast(n == 0
          ? 'Каталог аллақачон мавжуд — seed ўтказилмади'
          : '$n та маҳсулот юкланди');
    } catch (e) {
      if (!mounted) return;
      _toast('Seed хато: $e', error: true);
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _openEdit({OilProduct? item, required bool asFilter}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OilCatalogEditDialog(
        item: item,
        asFilter: asFilter,
        adminPhone: _adminPhone,
        onDone: (msg) {
          if (mounted) _toast(msg);
        },
      ),
    );
  }

  Future<void> _delete(OilProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ўчириш'),
        content: Text('${p.fixedName} ўчирилсинми?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ҳа'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _adminApi.delete(adminPhone: _adminPhone, id: p.id);
      if (!mounted) return;
      _toast('Ўчирилди');
    } catch (e) {
      if (!mounted) return;
      _toast('Ўчирилмади: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Мой ва фильтр каталоги',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Админ/бухгалтер: ном, нарх, расм. Илова галереяси шу ердан олади.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _seeding ? null : _seed,
                  icon: _seeding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined),
                  label: const Text('Статик каталогни юклаш'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _openEdit(
                    asFilter: _tabs.index == 1,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Қўшиш'),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            labelColor: AppColors.primaryDark,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Мойлар'),
              Tab(text: 'Фильтрлар'),
            ],
          ),
          Expanded(
            child: StreamBuilder<List<OilProduct>>(
              stream: _repo.watchAll(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Хато: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snap.data!;
                return TabBarView(
                  controller: _tabs,
                  children: [
                    _list(
                      all.where((p) => p.isOil).toList(),
                      asFilter: false,
                    ),
                    _list(
                      all.where((p) => p.isFilter).toList(),
                      asFilter: true,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(List<OilProduct> items, {required bool asFilter}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              asFilter
                  ? 'Фильтрлар йўқ — «Статик каталогни юклаш» ёки Қўшиш'
                  : 'Мойлар йўқ — «Статик каталогни юклаш» ёки Қўшиш',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _openEdit(asFilter: asFilter),
              child: const Text('Қўшиш'),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final p = items[i];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFD5E5D6)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: _thumb(p),
            title: Text(
              p.fixedName ?? p.id,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${p.plainMeta ?? ''}\nдан ${formatPrice(p.price)} сўм'
              '${p.active ? '' : ' · ўчирилган'}',
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: p.active,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) async {
                    try {
                      await _adminApi.upsert(
                        adminPhone: _adminPhone,
                        id: p.id,
                        name: p.fixedName ?? p.id,
                        price: p.price,
                        meta: p.plainMeta ?? '',
                        reason: p.plainReason ?? '',
                        imageUrl: p.imageUrl,
                        specs: p.plainSpecs ?? const {},
                        sortOrder: p.sortOrder,
                        active: v,
                        isFilter: p.isFilter,
                        must: p.must,
                        dust: p.dust,
                        gas: p.gas,
                      );
                    } catch (e) {
                      if (!mounted) return;
                      _toast('Фаоллаштириш хато: $e', error: true);
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Таҳрир',
                  onPressed: () => _openEdit(item: p, asFilter: asFilter),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Ўчириш',
                  onPressed: () => _delete(p),
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                ),
              ],
            ),
            onTap: () => _openEdit(item: p, asFilter: asFilter),
          ),
        );
      },
    );
  }

  Widget _thumb(OilProduct p) {
    final url = p.imageUrl.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 56,
        height: 56,
        child: url.isNotEmpty && isHttpImageUrl(url)
            ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
            : ColoredBox(
                color: p.isOil
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFEEF2F7),
                child: Icon(
                  p.isOil ? Icons.opacity : Icons.filter_alt_outlined,
                  color: AppColors.primary,
                ),
              ),
      ),
    );
  }
}

class _OilCatalogEditDialog extends StatefulWidget {
  const _OilCatalogEditDialog({
    required this.asFilter,
    required this.adminPhone,
    required this.onDone,
    this.item,
  });

  final OilProduct? item;
  final bool asFilter;
  final String adminPhone;
  final void Function(String msg) onDone;

  @override
  State<_OilCatalogEditDialog> createState() => _OilCatalogEditDialogState();
}

class _OilCatalogEditDialogState extends State<_OilCatalogEditDialog> {
  final _adminApi = AdminOilCatalogService();
  late final TextEditingController _name;
  late final TextEditingController _meta;
  late final TextEditingController _price;
  late final TextEditingController _reason;
  late final TextEditingController _sort;
  late final TextEditingController _imageUrl;
  late bool _active;
  late bool _must;
  late bool _dust;
  late bool _gas;
  late bool _isFilter;
  bool _saving = false;
  bool _uploading = false;
  String? _docId;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final p = widget.item;
    _docId = p?.id;
    _name = TextEditingController(text: p?.fixedName ?? '');
    _meta = TextEditingController(text: p?.plainMeta ?? '');
    _price = TextEditingController(text: p != null ? '${p.price}' : '');
    _reason = TextEditingController(text: p?.plainReason ?? '');
    _sort = TextEditingController(text: '${p?.sortOrder ?? 0}');
    _imageUrl = TextEditingController(text: p?.imageUrl ?? '');
    _active = p?.active ?? true;
    _must = p?.must ?? false;
    _dust = p?.dust ?? false;
    _gas = p?.gas ?? false;
    _isFilter = p?.isFilter ?? widget.asFilter;
  }

  @override
  void dispose() {
    _name.dispose();
    _meta.dispose();
    _price.dispose();
    _reason.dispose();
    _sort.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  int? _parsePrice(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  Future<void> _pickImage() async {
    if (_uploading) return;
    setState(() {
      _uploading = true;
      _formError = null;
    });
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        setState(() => _formError = 'Файл ўқилмади — кичикроқ JPG/PNG танланг.');
        return;
      }
      if (bytes.length > 2 * 1024 * 1024) {
        setState(() => _formError = 'Расм 2 MB дан кичик бўлсин.');
        return;
      }
      final name = f.name.toLowerCase();
      final mime = name.endsWith('.png')
          ? 'image/png'
          : name.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';

      _docId ??=
          FirebaseFirestore.instance.collection('oil_change_catalog').doc().id;
      final url = await BreadImageStorage().uploadOilImage(
        docId: _docId!,
        bytes: bytes,
        contentType: mime,
      );
      _imageUrl.text = url;
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => _formError = 'Расм хато: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = _parsePrice(_price.text.trim());
    if (name.isEmpty || price == null || price < 0) {
      setState(() => _formError = 'Ном ва нархни тўғри киритинг (масалан 185000).');
      return;
    }
    if (widget.adminPhone.isEmpty) {
      setState(() => _formError = 'Админ телефон топилмади — қайта киринг.');
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      final id = await _adminApi.upsert(
        adminPhone: widget.adminPhone,
        id: _docId,
        name: name,
        price: price,
        meta: _meta.text.trim(),
        reason: _reason.text.trim(),
        imageUrl: _imageUrl.text.trim(),
        specs: widget.item?.plainSpecs ?? const {},
        sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
        active: _active,
        isFilter: _isFilter,
        must: _must,
        dust: _dust,
        gas: _gas,
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onDone('Сақланди ($id)');
    } catch (e) {
      if (!mounted) return;
      setState(() => _formError = 'Сақланмади: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _imageUrl.text.trim();
    return AlertDialog(
      title: Text(widget.item == null ? 'Янги маҳсулот' : 'Таҳрирлаш'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_formError != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _formError!,
                    style: const TextStyle(color: Color(0xFFB71C1C)),
                  ),
                ),
              ],
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: url.isNotEmpty && isHttpImageUrl(url)
                      ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                      : ColoredBox(
                          color: const Color(0xFFEAF6EB),
                          child: Icon(
                            _isFilter
                                ? Icons.filter_alt_outlined
                                : Icons.opacity,
                            size: 48,
                            color: AppColors.primary,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickImage,
                      icon: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload),
                      label: const Text('Расм юклаш'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Ном',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _meta,
                decoration: const InputDecoration(
                  labelText: 'Қисқа meta (API, SAE…)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Нарх (сўм)',
                  hintText: '185000',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reason,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Нега тавсия',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _sort,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Тартиб (sortOrder)',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Фаол'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Фильтр (мой эмас)'),
                value: _isFilter,
                onChanged: (v) => setState(() => _isFilter = v),
              ),
              if (_isFilter) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Мажбурий мой билан (must)'),
                  value: _must,
                  onChanged: (v) => setState(() => _must = v ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Чанг / қишлоқ (dust)'),
                  value: _dust,
                  onChanged: (v) => setState(() => _dust = v ?? false),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Газ учун (gas)'),
                  value: _gas,
                  onChanged: (v) => setState(() => _gas = v ?? false),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Бекор'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Сақлаш'),
        ),
      ],
    );
  }
}

/// Seed учун кириллча матнлар (админ панели).
const _seedTr = <String, String>{
  'oil_prod_o1_meta': 'Full Syn · API SP · ACEA C3',
  'oil_prod_o1_reason':
      'Метан ва таксида двигатель иссиқроқ — бу мой иссиққа чидайди.',
  'oil_prod_o2_meta': 'Full Syn · ACEA C3',
  'oil_prod_o2_reason': 'Узоқ йўл ва оғир иш учун барқарор сифат.',
  'oil_prod_o3_meta': 'Full Syn · API SN',
  'oil_prod_o3_reason':
      'Нарх/сифат мувозанати — шаҳар таксисига мақбул.',
  'oil_prod_o4_meta': 'Full Syn · API SP',
  'oil_prod_o4_reason':
      'Тўхтаб-кетувчи тирбандликда ҳимояни ушлаб туради.',
  'oil_prod_o5_meta': 'Full Syn · API SP',
  'oil_prod_o5_reason':
      'Мақбул нархдаги тўлиқ синтетик — бюджетни сақлайди.',
  'oil_prod_o6_meta': 'Semi · API SN',
  'oil_prod_o6_reason': 'Фақат енгил шахсий иш. Газ/такси учун эмас.',
  'oil_filter_f1_name': 'Мой фильтри',
  'oil_filter_f1_meta': 'Мой билан бирга',
  'oil_filter_f1_reason':
      'Мой алмаштирилса фильтр ҳам янги бўлсин — акс ҳолда кир қайта айланади.',
  'oil_filter_f1_role': 'Мойни тозалаш',
  'oil_filter_f1_when': 'Ҳар мой алмаштиришда',
  'oil_filter_f1_ava': 'Мажбурий бирга',
  'oil_filter_f2_name': 'Ҳаво фильтри',
  'oil_filter_f2_meta': 'Чангга қарши',
  'oil_filter_f2_reason':
      'Ўзбекистон чангида муҳим. Булғанса ёқилғи кўпаяди.',
  'oil_filter_f2_role': 'Ҳавони тозалаш',
  'oil_filter_f2_city': '10–15 минг км текшириш',
  'oil_filter_f2_rural': '5–7 минг км',
  'oil_filter_f3_name': 'Салон фильтри',
  'oil_filter_f3_meta': 'Кондиционер',
  'oil_filter_f3_reason':
      'Ҳид ва чангни камайтиради — мижоз ҳам рози.',
  'oil_filter_f3_role': 'Салон ҳавоси',
  'oil_filter_f3_when': 'Йилига 1–2 марта',
  'oil_filter_f4_name': 'Ёқилғи фильтри',
  'oil_filter_f4_meta': 'CNG / бензин',
  'oil_filter_f4_reason': 'Насос ва форсункани ҳимоя қилади.',
  'oil_filter_f4_role': 'Ёқилғи тозалиги',
  'oil_filter_f4_gas': 'Сифатсиз газда тезроқ',
  'oil_spec_sae': 'SAE',
  'oil_spec_api': 'API',
  'oil_spec_acea': 'ACEA',
  'oil_spec_type': 'Тури',
  'oil_spec_country': 'Давлат',
  'oil_spec_role': 'Вазифа',
  'oil_spec_when': 'Қачон',
  'oil_spec_ava': 'AVA',
  'oil_spec_city': 'Шаҳар',
  'oil_spec_rural': 'Қишлоқ',
  'oil_spec_gas': 'Газ',
  'oil_spec_val_full_syn': 'Full Synthetic',
  'oil_spec_val_semi': 'Semi-Synthetic',
};
