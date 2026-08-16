import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/service_config_holder.dart';
import '../../../models/geo_area.dart';
import '../../../repositories/service_config_repository.dart';
import '../models/tv_shop.dart';
import '../repositories/tv_shop_repository.dart';
import 'tv_vitrine_card.dart';

/// AVA дўкони ичидаги сотувчи витринаси (расмий каталогдан алоҳида).
class TvVitrineSection extends StatefulWidget {
  const TvVitrineSection({super.key});

  @override
  State<TvVitrineSection> createState() => _TvVitrineSectionState();
}

class _TvVitrineSectionState extends State<TvVitrineSection> {
  final _repo = TvShopRepository();
  final _geo = ServiceConfigRepository();
  List<TvShopItem> _items = const [];
  List<GeoDistrict> _districts = const [];
  String _districtId = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final regionId = ServiceConfigHolder.regionId;
    try {
      final districts = regionId.isEmpty
          ? const <GeoDistrict>[]
          : await _geo.fetchDistricts(regionId);
      final items = await _repo.fetchVitrine(districtId: _districtId);
      if (!mounted) return;
      setState(() {
        _districts = districts;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[TvVitrine] $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final items = await _repo.fetchVitrine(districtId: _districtId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[TvVitrine] reload $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDistrict() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            children: [
              ListTile(
                title: Text(context.tr('tv_market_all_districts')),
                trailing: _districtId.isEmpty
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(ctx, ''),
              ),
              for (final d in _districts)
                ListTile(
                  title: Text(d.displayName),
                  trailing: _districtId == d.id
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(ctx, d.id),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _districtId = picked);
    await _reload();
  }

  String _chipLabel() {
    if (_districtId.isEmpty) return context.tr('tv_market_all_districts');
    for (final d in _districts) {
      if (d.id == _districtId) return d.displayName;
    }
    return context.tr('tv_market_all_districts');
  }

  @override
  Widget build(BuildContext context) {
    if (!_loading && _items.isEmpty && _districtId.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('tv_vitrine_title'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ActionChip(
                onPressed: _pickDistrict,
                label: Text(_chipLabel()),
                avatar: const Icon(Icons.place_outlined, size: 16),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Text(
              context.tr('tv_vitrine_empty'),
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          SizedBox(
            height: 268,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              scrollDirection: Axis.horizontal,
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                return SizedBox(
                  width: 168,
                  child: TvVitrineCard(item: _items[i]),
                );
              },
            ),
          ),
      ],
    );
  }
}
