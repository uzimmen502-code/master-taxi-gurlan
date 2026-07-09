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
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                        18, 8, 18, 24),
                                    itemCount: ads.length,
                                    itemBuilder: (_, i) => _adCard(ads[i]),
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

  Widget _adCard(AdModel ad) {
    final active = ad.status == 'active';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ad.imageUrls.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      ad.imageUrls.first,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 72,
                        height: 72,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.image_not_supported),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.image_outlined),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ad.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${ad.price} so\'m · ${ad.sellerName} · ${ad.phone}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      if (ad.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          ad.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _chip(
                            active ? 'Faol' : 'Nofaol',
                            active ? Colors.green : Colors.orange,
                          ),
                          _chip('${ad.views} ko\'rish', Colors.blueGrey),
                          if (ad.adminNote.isNotEmpty)
                            _chip('Admin izoh bor', Colors.purple),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!active)
                  OutlinedButton.icon(
                    onPressed: () => _setStatus(ad, 'active'),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Faollashtirish'),
                  ),
                if (active)
                  OutlinedButton.icon(
                    onPressed: () => _setStatus(ad, 'inactive'),
                    icon: const Icon(Icons.visibility_off_outlined, size: 18),
                    label: const Text('Nofaol qilish'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _edit(ad),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Tahrir'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _deleteAd(ad),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('O\'chirish'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
