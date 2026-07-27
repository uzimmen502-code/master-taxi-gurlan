import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/utils/formatters.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../ads/models/ad_model.dart';
import '../../../core/theme/app_theme.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_market_service.dart';
import '../widgets/market_ad_edit_dialog.dart';

class MarketModerationScreen extends StatefulWidget {
  const MarketModerationScreen({super.key});

  @override
  State<MarketModerationScreen> createState() => _MarketModerationScreenState();
}

class _MarketModerationScreenState extends State<MarketModerationScreen> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'all';
  String _query = '';
  List<AdModel> _allAds = const [];
  bool _loading = true;
  String? _loadError;

  static const _blue = AppColors.primary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAds());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAds() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final adminPhone = context.read<AdminAuthService>().phoneDigits ?? '';
      final ads = await context.read<AdminMarketService>().listAds(
            adminPhone: adminPhone,
          );
      if (!mounted) return;
      setState(() {
        _allAds = ads;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _deleteAd(AdModel ad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('E\'lonni o\'chirish'),
        content: Text('«${ad.title}» butunlay o\'chiriladi (rasmlar ham).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Yo\'q'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('O\'chirish', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final adminPhone = context.read<AdminAuthService>().phoneDigits ?? '';
      await context.read<AdminMarketService>().deleteAd(
            adminPhone: adminPhone,
            adId: ad.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E\'lon o\'chirildi')),
      );
      await _loadAds();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Xatolik: $e')),
      );
    }
  }

  Future<void> _setStatus(AdModel ad, String status) async {
    final adminPhone = context.read<AdminAuthService>().phoneDigits ?? '';
    try {
      await context.read<AdminMarketService>().updateAdStatus(
            adminPhone: adminPhone,
            adId: ad.id,
            status: status,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: status == 'active' ? Colors.green : Colors.orange,
          content: Text(
            status == 'active' ? 'Faollashtirildi: ${ad.title}' : 'O\'chirildi (nofaol): ${ad.title}',
          ),
        ),
      );
      await _loadAds();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Xatolik: $e')),
      );
    }
  }

  Future<void> _edit(AdModel ad) async {
    final adminPhone = context.read<AdminAuthService>().phoneDigits ?? '';
    await showMarketAdEditDialog(
      context: context,
      ad: ad,
      adminPhone: adminPhone,
    );
    if (mounted) await _loadAds();
  }

  List<AdModel> _filter(List<AdModel> ads) {
    final q = _query.trim().toLowerCase();
    return ads.where((ad) {
      if (_statusFilter != 'all' && ad.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return ad.title.toLowerCase().contains(q) ||
          ad.description.toLowerCase().contains(q) ||
          ad.sellerName.toLowerCase().contains(q) ||
          ad.phone.toLowerCase().contains(q) ||
          ad.ownerId.contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ads = _filter(_allAds);
    return Column(
      children: [
        _header(),
        const _MarketAutoApproveBar(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Xatolik: $_loadError'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _loadAds,
                            child: const Text('Qayta urinish'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadAds,
                      child: Column(
                        children: [
                          _summary(_allAds),
                          _filters(),
                          Expanded(
                            child: ads.isEmpty
                                ? ListView(
                                    children: const [
                                      SizedBox(height: 120),
                                      Center(child: Text('E\'lon topilmadi')),
                                    ],
                                  )
                                : _AdsTable(
                                    ads: ads,
                                    onOpen: _showAdDetail,
                                    onGallery: _openImageGallery,
                                    onActivate: (ad) =>
                                        _setStatus(ad, 'active'),
                                    onDeactivate: (ad) =>
                                        _setStatus(ad, 'inactive'),
                                    onEdit: _edit,
                                    onDelete: _deleteAd,
                                  ),
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.storefront_outlined, color: _blue),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Онлайн бозор — nazorati',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 3),
                Text(
                  'Arzon mahsulot e\'lonlarini ko\'rish, tahrirlash va o\'chirish',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Yangilash',
            onPressed: _loading ? null : _loadAds,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _summary(List<AdModel> ads) {
    int count(String status) => ads.where((a) => a.status == status).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _summaryCard('Jami', ads.length, Colors.blueGrey),
          _summaryCard('Kutilmoqda', count('pending'), Colors.deepOrange),
          _summaryCard('Faol', count('active'), Colors.green),
          _summaryCard('Nofaol', count('inactive'), Colors.orange),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, int value, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.1),
            child: Text(
              '$value',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _filters() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Sarlavha, tavsif, telefon yoki sotuvchi bo\'yicha qidirish...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final item in [
                ('all', 'Barchasi'),
                ('pending', 'Kutilmoqda'),
                ('active', 'Faol'),
                ('inactive', 'Nofaol'),
              ])
                ChoiceChip(
                  label: Text(item.$2),
                  selected: _statusFilter == item.$1,
                  onSelected: (_) => setState(() => _statusFilter = item.$1),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openImageGallery(AdModel ad) async {
    final urls = ad.imageUrls
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (urls.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _MarketImageGalleryDialog(
        title: ad.title,
        urls: urls,
      ),
    );
  }

  Future<void> _showAdDetail(AdModel ad) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _MarketAdDetailDialog(
        ad: ad,
        onGallery: () {
          Navigator.pop(ctx);
          _openImageGallery(ad);
        },
        onActivate: () {
          Navigator.pop(ctx);
          _setStatus(ad, 'active');
        },
        onDeactivate: () {
          Navigator.pop(ctx);
          _setStatus(ad, 'inactive');
        },
        onEdit: () {
          Navigator.pop(ctx);
          _edit(ad);
        },
        onDelete: () {
          Navigator.pop(ctx);
          _deleteAd(ad);
        },
      ),
    );
  }
}

String _marketStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Кутилмоқда';
    case 'active':
      return 'Фаол';
    case 'inactive':
      return 'Нофаол';
    default:
      return status;
  }
}

Color _marketStatusColor(String status) {
  switch (status) {
    case 'pending':
      return Colors.deepOrange;
    case 'active':
      return Colors.green;
    case 'inactive':
      return Colors.orange;
    default:
      return Colors.blueGrey;
  }
}

String _marketFmtDate(DateTime? d) {
  if (d == null) return '—';
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

Widget _marketStatusChip(String status) {
  final color = _marketStatusColor(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      _marketStatusLabel(status),
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Зич жадвал — қаторни босиш → детал.
class _AdsTable extends StatelessWidget {
  const _AdsTable({
    required this.ads,
    required this.onOpen,
    required this.onGallery,
    required this.onActivate,
    required this.onDeactivate,
    required this.onEdit,
    required this.onDelete,
  });

  final List<AdModel> ads;
  final ValueChanged<AdModel> onOpen;
  final ValueChanged<AdModel> onGallery;
  final ValueChanged<AdModel> onActivate;
  final ValueChanged<AdModel> onDeactivate;
  final ValueChanged<AdModel> onEdit;
  final ValueChanged<AdModel> onDelete;

  static const _headerBg = Color(0xFFE3F2FD);
  static const _border = Color(0xFFE0E0E0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth < 980
                          ? 980
                          : constraints.maxWidth,
                    ),
                    child: Table(
                      columnWidths: const {
                        0: FixedColumnWidth(64),
                        1: FlexColumnWidth(2.2),
                        2: FixedColumnWidth(120),
                        3: FixedColumnWidth(110),
                        4: FlexColumnWidth(1.4),
                        5: FixedColumnWidth(72),
                        6: FixedColumnWidth(100),
                        7: FixedColumnWidth(148),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: _border.withValues(alpha: 0.7),
                        ),
                        verticalInside: const BorderSide(color: _border),
                      ),
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(color: _headerBg),
                          children: _headers(),
                        ),
                        for (final ad in ads) _dataRow(ad),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _headers() {
    const style = TextStyle(fontWeight: FontWeight.w800, fontSize: 12);
    Widget h(String t, {TextAlign align = TextAlign.left}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Text(t, style: style, textAlign: align),
        );
    return [
      h('Расм'),
      h('Сарлавҳа'),
      h('Нарх', align: TextAlign.right),
      h('Ҳолат'),
      h('Сотувчи'),
      h('Кўриш'),
      h('Сана'),
      h('Амал', align: TextAlign.center),
    ];
  }

  TableRow _dataRow(AdModel ad) {
    final when = ad.publishedAt ?? ad.createdAt ?? ad.updatedAt;
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(6),
          child: ad.imageUrls.isNotEmpty
              ? _AdThumb(
                  urls: ad.imageUrls,
                  size: 48,
                  onOpen: () => onGallery(ad),
                )
              : Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image_outlined, size: 20),
                ),
        ),
        InkWell(
          onTap: () => onOpen(ad),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (ad.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    ad.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        InkWell(
          onTap: () => onOpen(ad),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              formatMoney(ad.price),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _marketStatusChip(ad.status),
          ),
        ),
        InkWell(
          onTap: () => onOpen(ad),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad.sellerName.isEmpty ? '—' : ad.sellerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  ad.phone.isEmpty ? ad.ownerId : ad.phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
        InkWell(
          onTap: () => onOpen(ad),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(
              '${ad.views}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ),
        InkWell(
          onTap: () => onOpen(ad),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(
              _marketFmtDate(when),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (ad.status != 'active')
                IconButton(
                  tooltip: 'Фаоллаштириш',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onActivate(ad),
                  icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                ),
              if (ad.status == 'active')
                IconButton(
                  tooltip: 'Нофаол',
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onDeactivate(ad),
                  icon: const Icon(
                    Icons.visibility_off_outlined,
                    color: Colors.orange,
                  ),
                ),
              IconButton(
                tooltip: 'Таҳрир',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: () => onEdit(ad),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Ўчириш',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: () => onDelete(ad),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MarketAdDetailDialog extends StatelessWidget {
  const _MarketAdDetailDialog({
    required this.ad,
    required this.onGallery,
    required this.onActivate,
    required this.onDeactivate,
    required this.onEdit,
    required this.onDelete,
  });

  final AdModel ad;
  final VoidCallback onGallery;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final when = ad.publishedAt ?? ad.createdAt ?? ad.updatedAt;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ad.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ad.imageUrls.isNotEmpty)
                        _AdThumb(
                          urls: ad.imageUrls,
                          size: 96,
                          onOpen: onGallery,
                        )
                      else
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.image_outlined),
                        ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatMoney(ad.price),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _marketStatusChip(ad.status),
                            const SizedBox(height: 8),
                            Text(
                              '${ad.sellerName.isEmpty ? '—' : ad.sellerName}'
                              ' · ${ad.phone.isEmpty ? ad.ownerId : ad.phone}',
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${ad.views} кўриш · ${_marketFmtDate(when)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (ad.description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Тавсиф',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(ad.description, style: const TextStyle(height: 1.35)),
                  ],
                  if (ad.adminNote.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Админ изоҳ: ${ad.adminNote}',
                      style: TextStyle(
                        color: Colors.purple.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (ad.status != 'active')
                    FilledButton.icon(
                      onPressed: onActivate,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Фаоллаштириш'),
                    ),
                  if (ad.status == 'active')
                    OutlinedButton.icon(
                      onPressed: onDeactivate,
                      icon: const Icon(Icons.visibility_off_outlined, size: 18),
                      label: const Text('Нофаол'),
                    ),
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Таҳрир'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Ўчириш'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Admin web: Storage CORS + HtmlElement fallback — rasmlar ko'rinsin.
class _AdThumb extends StatelessWidget {
  const _AdThumb({
    required this.urls,
    required this.onOpen,
    this.size = 88,
  });

  final List<String> urls;
  final VoidCallback onOpen;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = urls.first;
    final radius = size >= 72 ? 10.0 : 8.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(radius),
        child: Tooltip(
          message: 'Расмни катталаштириш (${urls.length})',
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Image.network(
                  url,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      width: size,
                      height: size,
                      color: Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: size * 0.28,
                        height: size * 0.28,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    width: size,
                    height: size,
                    color: Colors.grey.shade200,
                    child: Icon(Icons.image_not_supported, size: size * 0.35),
                  ),
                ),
              ),
              if (urls.length > 1)
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+${urls.length - 1}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: size >= 72 ? 11 : 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              if (size >= 64)
                Positioned(
                  right: 3,
                  top: 3,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.zoom_in,
                      size: size >= 80 ? 14 : 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarketImageGalleryDialog extends StatefulWidget {
  const _MarketImageGalleryDialog({
    required this.title,
    required this.urls,
  });

  final String title;
  final List<String> urls;

  @override
  State<_MarketImageGalleryDialog> createState() =>
      _MarketImageGalleryDialogState();
}

class _MarketImageGalleryDialogState extends State<_MarketImageGalleryDialog> {
  late final PageController _page;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _page = PageController();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.urls.length;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${_index + 1} / $n',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  IconButton(
                    tooltip: 'Ёпиш',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: n,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.network(
                        widget.urls[i],
                        fit: BoxFit.contain,
                        webHtmlElementStrategy:
                            WebHtmlElementStrategy.fallback,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                        errorBuilder: (_, __, ___) => const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image, size: 48),
                            SizedBox(height: 8),
                            Text('Расм юкланмади'),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (n > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: _index <= 0
                          ? null
                          : () => _page.previousPage(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                              ),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _index >= n - 1
                          ? null
                          : () => _page.nextPage(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                              ),
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `settings/app.marketAutoApprove` — ҚЎЛДА / АВТО.
class _MarketAutoApproveBar extends StatefulWidget {
  const _MarketAutoApproveBar();

  @override
  State<_MarketAutoApproveBar> createState() => _MarketAutoApproveBarState();
}

class _MarketAutoApproveBarState extends State<_MarketAutoApproveBar> {
  bool _busy = false;

  Future<void> _setAuto(bool enabled) async {
    final adminPhone = context.read<AdminAuthService>().phoneDigits ?? '';
    if (adminPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Admin telefon topilmadi — qayta kiring'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AdminMarketService>().setAutoApprove(
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
        final auto = snap.data?.data()?['marketAutoApprove'] == true;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(18, 10, 18, 0),
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
                      ? 'Авто фаоллаштириш: ЁҚИҚ — янги эълонлар дарҳол актив'
                      : 'Қўлда фаоллаштириш — янги эълонлар «Кутилмоқда»га тушади',
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
