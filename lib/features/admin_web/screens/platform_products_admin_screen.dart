import 'dart:async';
import 'dart:typed_data';

// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/data_url_image.dart';
import '../../../core/utils/formatters.dart';
import '../../bread/services/bread_image_storage.dart';
import '../../../models/platform_product.dart';
import '../../../repositories/platform_products_repository.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_market_service.dart';

/// Админ: платформа дўкони каталоги.
class PlatformProductsAdminScreen extends StatefulWidget {
  const PlatformProductsAdminScreen({super.key});

  @override
  State<PlatformProductsAdminScreen> createState() =>
      _PlatformProductsAdminScreenState();
}

class _PlatformProductsAdminScreenState
    extends State<PlatformProductsAdminScreen> {
  final _repo = PlatformProductsRepository();

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : AppColors.button,
      ),
    );
  }

  Future<void> _openEdit([PlatformProduct? existing]) async {
    final result = await showDialog<PlatformProduct>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    try {
      if (existing == null) {
        await _repo.create(result);
        _toast('Қўшилди');
      } else {
        await _repo.update(result);
        _toast('Сақланди');
      }
    } catch (e) {
      if (!mounted) return;
      _toast('Хато: $e', error: true);
    }
  }

  Future<void> _delete(PlatformProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ўчириш'),
        content: Text('«${p.name}» ўчирилсинми?'),
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
      await _repo.delete(p.id);
      if (!mounted) return;
      _toast('Ўчирилди');
    } catch (e) {
      if (!mounted) return;
      _toast('Хато: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(),
        backgroundColor: AppColors.button,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Маҳсулот'),
      ),
      body: Column(
        children: [
          const _PlatformFeaturedAutoBar(),
          Expanded(
            child: StreamBuilder<List<PlatformProduct>>(
              stream: _repo.watchAll(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return const Center(
                    child: Text('Каталог бўш — маҳсулот қўшинг'),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final cols = w >= 1500
                        ? 5
                        : w >= 1200
                            ? 4
                            : w >= 900
                                ? 3
                                : w >= 600
                                    ? 2
                                    : 1;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        mainAxisExtent: 76,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final p = items[i];
                        return _ProductTile(
                          index: i + 1,
                          product: p,
                          onTap: () => _openEdit(p),
                          onMenu: (v) async {
                            if (v == 'edit') {
                              await _openEdit(p);
                            } else if (v == 'toggle') {
                              await _repo.setActive(p.id, !p.active);
                            } else if (v == 'delete') {
                              await _delete(p);
                            }
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// `settings/app.platformFeaturedAuto` — ҚЎЛДА / АВТО витрина.
class _PlatformFeaturedAutoBar extends StatefulWidget {
  const _PlatformFeaturedAutoBar();

  @override
  State<_PlatformFeaturedAutoBar> createState() =>
      _PlatformFeaturedAutoBarState();
}

class _PlatformFeaturedAutoBarState extends State<_PlatformFeaturedAutoBar> {
  bool _busy = false;

  Future<void> _setAuto(bool enabled) async {
    final adminPhone = context.read<AdminAuthService>().phoneDigits ?? '';
    if (adminPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin телефон топилмади — қайта киринг'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AdminMarketService>().setPlatformFeaturedAuto(
            adminPhone: adminPhone,
            enabled: enabled,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .snapshots(),
      builder: (context, snap) {
        // Default АВТО (null/absent → true).
        final auto = snap.data?.data()?['platformFeaturedAuto'] != false;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: auto ? Colors.green.shade50 : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: auto ? Colors.green.shade200 : Colors.orange.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(
                auto ? Icons.flash_on : Icons.admin_panel_settings,
                color: auto ? Colors.green.shade700 : Colors.orange.shade800,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  auto
                      ? 'Витрина АВТО — фаол маҳсулотлар «Тавсия этамиз»да кўринади'
                      : 'Витрина ҚЎЛДА — фақат «Тавсия этамиз» белгиланганлари',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color:
                        auto ? Colors.green.shade900 : Colors.orange.shade900,
                  ),
                ),
              ),
              if (_busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                OutlinedButton(
                  onPressed: auto ? () => _setAuto(false) : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                  ),
                  child: const Text('ҚЎЛДА', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: auto ? null : () => _setAuto(true),
                  icon: const Icon(Icons.flash_on, size: 16),
                  label: const Text('АВТО', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.button,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.index,
    required this.product,
    required this.onTap,
    required this.onMenu,
  });

  final int index;
  final PlatformProduct product;
  final VoidCallback onTap;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final meta = [
      '${formatPrice(product.price)} сўм',
      product.active ? 'фаол' : 'нофаол',
      if (product.featuredOnHome) 'витрина',
      if (product.showInMarket) 'бозор',
      product.isUnlimitedStock ? 'лимитсиз' : 'қолдиқ ${product.remaining}',
    ].join(' · ');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE8ECE8)),
          ),
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '$index',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _Thumb(url: product.imageUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                onSelected: onMenu,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Таҳрир'),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(product.active ? 'Нофаол' : 'Фаол'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Ўчириш'),
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

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    Widget child = const ColoredBox(
      color: Color(0xFFE8F5E9),
      child: Icon(Icons.storefront, color: AppColors.button),
    );
    if (u.isNotEmpty && isHttpImageUrl(u)) {
      child = CachedNetworkImage(imageUrl: u, fit: BoxFit.cover);
    } else if (u.isNotEmpty && isDataImageUrl(u)) {
      final bytes = decodeDataUrlImageBytes(u);
      if (bytes != null) child = Image.memory(bytes, fit: BoxFit.cover);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 48, height: 48, child: child),
    );
  }
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({this.existing});

  final PlatformProduct? existing;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _price;
  late final TextEditingController _image;
  late final TextEditingController _unit;
  late final TextEditingController _stock;
  late final TextEditingController _sort;
  late bool _active;
  late bool _featured;
  late bool _inMarket;
  late String _docId;
  bool _uploading = false;
  StreamSubscription<html.Event>? _pasteSub;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _docId = (e?.id.isNotEmpty == true)
        ? e!.id
        : FirebaseFirestore.instance.collection('platform_products').doc().id;
    _name = TextEditingController(text: e?.name ?? '');
    _desc = TextEditingController(text: e?.description ?? '');
    _price = TextEditingController(text: e != null ? '${e.price}' : '');
    _image = TextEditingController(text: e?.imageUrl ?? '');
    _unit = TextEditingController(text: e?.unit ?? 'дона');
    _stock = TextEditingController(
      text: e != null ? '${e.totalStock}' : '0',
    );
    _sort = TextEditingController(text: e != null ? '${e.sortOrder}' : '0');
    _active = e?.active ?? true;
    _featured = e?.featuredOnHome ?? false;
    _inMarket = e?.showInMarket ?? true;
    _pasteSub = html.document.onPaste.listen(_onDocumentPaste);
  }

  @override
  void dispose() {
    _pasteSub?.cancel();
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    _image.dispose();
    _unit.dispose();
    _stock.dispose();
    _sort.dispose();
    super.dispose();
  }

  Future<Uint8List?> _blobToBytes(html.Blob blob) async {
    final reader = html.FileReader();
    final done = reader.onLoadEnd.first;
    reader.readAsArrayBuffer(blob);
    await done;
    final result = reader.result;
    if (result is ByteBuffer) {
      return Uint8List.view(result);
    }
    return null;
  }

  void _onDocumentPaste(html.Event event) {
    if (_uploading || !mounted) return;
    final e = event as html.ClipboardEvent;
    final items = e.clipboardData?.items;
    if (items == null) return;
    final len = items.length;
    if (len == null) return;
    for (var i = 0; i < len; i++) {
      final item = items[i];
      final type = item.type;
      if (type == null || !type.startsWith('image/')) continue;
      final file = item.getAsFile();
      if (file == null) continue;
      e.preventDefault();
      e.stopPropagation();
      unawaited(_uploadFromBlob(file, type));
      return;
    }
  }

  Future<void> _uploadFromBlob(html.Blob blob, String mime) async {
    final bytes = await _blobToBytes(blob);
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Нусхадаги расм ўқилмади.'),
          ),
        );
      }
      return;
    }
    await _uploadBytes(bytes, mime.isEmpty ? 'image/png' : mime);
  }

  Future<void> _uploadBytes(Uint8List bytes, String mime) async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      if (bytes.length > 2 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text('Расм 2 MB дан кичик бўлсин.'),
            ),
          );
        }
        return;
      }
      final contentType = mime.startsWith('image/') ? mime : 'image/jpeg';
      final url = await BreadImageStorage().uploadPlatformImage(
        docId: _docId,
        bytes: bytes,
        contentType: contentType,
      );
      if (!mounted) return;
      setState(() => _image.text = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.button,
          content: Text('Расм юкланди'),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Расм: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickImage() async {
    if (_uploading) return;
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text('Файл ўқилмади — кичикроқ JPG/PNG танланг.'),
            ),
          );
        }
        return;
      }
      final name = f.name.toLowerCase();
      final mime = name.endsWith('.png')
          ? 'image/png'
          : name.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
      await _uploadBytes(bytes, mime);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Расм: $e')),
        );
      }
    }
  }

  void _save() {
    final name = _name.text.trim();
    final price = int.tryParse(_price.text.trim()) ?? -1;
    if (name.isEmpty || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ном ва нарх мажбурий')),
      );
      return;
    }
    final existing = widget.existing;
    Navigator.pop(
      context,
      PlatformProduct(
        id: existing?.id.isNotEmpty == true ? existing!.id : _docId,
        name: name,
        description: _desc.text.trim(),
        price: price,
        imageUrl: _image.text.trim(),
        unit: _unit.text.trim().isEmpty ? 'дона' : _unit.text.trim(),
        minQty: existing?.minQty ?? 1,
        step: existing?.step ?? 1,
        totalStock: int.tryParse(_stock.text.trim()) ?? 0,
        soldToday: existing?.soldToday ?? 0,
        active: _active,
        featuredOnHome: _featured,
        showInMarket: _inMarket,
        sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = _image.text.trim();
    return AlertDialog(
      title: Text(widget.existing == null ? 'Янги маҳсулот' : 'Таҳрир'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: url.isNotEmpty && isHttpImageUrl(url)
                      ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
                      : const ColoredBox(
                          color: Color(0xFFEAF6EB),
                          child: Icon(
                            Icons.image_outlined,
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
                          : const Icon(Icons.add_photo_alternate),
                      label: Text(
                        _uploading
                            ? 'Юкланмоқда...'
                            : (url.isEmpty
                                ? 'Расм танлаш'
                                : 'Расмни алмаштириш'),
                      ),
                    ),
                  ),
                  if (url.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Расмни олиб ташлаш',
                      onPressed: _uploading
                          ? null
                          : () => setState(() => _image.clear()),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                  ],
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  'Файл танланг ёки нусха қўйинг (Ctrl+V). JPG/PNG/WebP, max 2 MB.',
                  style: TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
              ),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Ном'),
              ),
              TextField(
                controller: _desc,
                decoration: const InputDecoration(labelText: 'Тавсиф'),
                maxLines: 2,
              ),
              TextField(
                controller: _price,
                decoration: const InputDecoration(labelText: 'Нарх (сўм)'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              TextField(
                controller: _image,
                decoration: const InputDecoration(
                  labelText: 'Расм URL (авто тўлдирилади)',
                ),
              ),
              TextField(
                controller: _unit,
                decoration: const InputDecoration(labelText: 'Бирлик'),
              ),
              TextField(
                controller: _stock,
                decoration: const InputDecoration(
                  labelText: 'Омбор (0 = лимитсиз)',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              TextField(
                controller: _sort,
                decoration: const InputDecoration(labelText: 'Тартиб'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Фаол'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Тавсия этамиз (витрина)'),
                subtitle: const Text('ҚЎЛДА режимда витринага чиқади'),
                value: _featured,
                onChanged: (v) => setState(() => _featured = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Онлайн бозорда кўрсатиш'),
                value: _inMarket,
                onChanged: (v) => setState(() => _inMarket = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _uploading ? null : () => Navigator.pop(context),
          child: const Text('Бекор'),
        ),
        FilledButton(
          onPressed: _uploading ? null : _save,
          child: const Text('Сақлаш'),
        ),
      ],
    );
  }
}
