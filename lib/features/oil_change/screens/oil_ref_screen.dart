import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/catalog_search.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';
import '../data/oil_l10n.dart';
import '../data/oil_ref_catalog.dart';
import 'oil_car_setup_screen.dart';

/// Chevrolet moy ma'lumotnomasi — Tavsiya birinchi + katalog tablar + avto gate.
class OilRefScreen extends StatefulWidget {
  const OilRefScreen({
    super.key,
    required this.uid,
    this.initialVehicleId,
  });

  final String uid;
  final String? initialVehicleId;

  @override
  State<OilRefScreen> createState() => _OilRefScreenState();
}

class _OilRefScreenState extends State<OilRefScreen>
    with SingleTickerProviderStateMixin {
  final _repo = OilChangeRepository();
  late final TabController _tabs;
  String _query = '';
  OilVehicle? _selected;
  bool _gateDone = false;
  bool _gateRunning = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  OilVehicle _pickSelected(List<OilVehicle> vehicles) {
    if (_selected != null) {
      for (final v in vehicles) {
        if (v.id == _selected!.id) return v;
      }
    }
    if (widget.initialVehicleId != null) {
      for (final v in vehicles) {
        if (v.id == widget.initialVehicleId) return v;
      }
    }
    return vehicles.firstWhere((v) => v.isPrimary, orElse: () => vehicles.first);
  }

  Future<void> _runGate(List<OilVehicle> vehicles) async {
    if (_gateRunning || _gateDone) return;
    _gateRunning = true;

    if (vehicles.isEmpty) {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => OilCarSetupScreen(uid: widget.uid),
        ),
      );
      if (!mounted) return;
      _gateRunning = false;
      if (saved == true) {
        setState(() => _gateDone = true);
      } else {
        Navigator.pop(context);
      }
      return;
    }

    final selected = _pickSelected(vehicles);
    _selected = selected;

    if (!selected.isRecommendationReady) {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              OilCarSetupScreen(uid: widget.uid, vehicle: selected),
        ),
      );
      if (!mounted) return;
      _gateRunning = false;
      if (saved == true) {
        setState(() => _gateDone = true);
      } else if (vehicles.length == 1) {
        Navigator.pop(context);
      } else {
        setState(() => _gateDone = true);
      }
      return;
    }

    _gateRunning = false;
    setState(() => _gateDone = true);
  }

  List<OilRefProduct> _filter(List<OilRefProduct> src) {
    if (_query.isEmpty) return src;
    final q = _query;
    final list = src
        .where((p) => CatalogSearch.matches(q, [
              p.brand,
              p.name,
              p.dexos,
              p.api,
              p.sae,
            ]))
        .toList();
    list.sort((a, b) {
      return CatalogSearch.compare(
        q,
        titleA: '${a.brand} ${a.name}',
        titleB: '${b.brand} ${b.name}',
        extraA: [a.dexos, a.api, a.sae],
        extraB: [b.dexos, b.api, b.sae],
      );
    });
    return list;
  }

  bool get _showSearch => _tabs.index > 0;

  @override
  Widget build(BuildContext context) {
    if (widget.uid.length < 9) {
      return Scaffold(
        appBar: AppBar(
          title: Text(context.tr('oil_ref_guide')),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: Center(child: Text(context.tr('oil_fill_phone_first'))),
      );
    }

    return StreamBuilder<List<OilVehicle>>(
      stream: _repo.watchVehicles(widget.uid),
      builder: (context, snap) {
        final vehicles = snap.data ?? const <OilVehicle>[];
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return Scaffold(
            appBar: AppBar(
              title: Text(context.tr('oil_ref_guide')),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!_gateDone && !_gateRunning) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _runGate(vehicles);
          });
          return Scaffold(
            appBar: AppBar(
              title: Text(context.tr('oil_ref_guide')),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (vehicles.isNotEmpty) {
          _selected = _pickSelected(vehicles);
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7F4),
          appBar: AppBar(
            title: Text(context.tr('oil_ref_guide')),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                Tab(text: context.tr('oil_ref_tab_reco')),
                Tab(text: context.tr('oil_ref_tab_full')),
                Tab(text: context.tr('oil_ref_tab_semi')),
                Tab(text: context.tr('oil_ref_tab_mineral')),
              ],
            ),
          ),
          body: Column(
            children: [
              if (_showSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: context.tr('oil_ref_search_hint'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _RecoTab(
                      uid: widget.uid,
                      vehicles: vehicles,
                      selected: _selected,
                      onSelect: (v) => setState(() => _selected = v),
                      onSetup: (v) async {
                        final saved = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OilCarSetupScreen(
                              uid: widget.uid,
                              vehicle: v,
                            ),
                          ),
                        );
                        if (saved == true && mounted) setState(() {});
                      },
                    ),
                    _OilRefList(
                      products: _filter(OilRefCatalog.fullSynthetic),
                      emptyMsg: context.tr('oil_ref_empty'),
                    ),
                    _OilRefList(
                      products: _filter(OilRefCatalog.semiSynthetic),
                      emptyMsg: context.tr('oil_ref_empty'),
                    ),
                    _OilRefList(
                      products: _filter(OilRefCatalog.mineral),
                      emptyMsg: context.tr('oil_ref_empty'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecoTab extends StatelessWidget {
  const _RecoTab({
    required this.uid,
    required this.vehicles,
    required this.selected,
    required this.onSelect,
    required this.onSetup,
  });

  final String uid;
  final List<OilVehicle> vehicles;
  final OilVehicle? selected;
  final ValueChanged<OilVehicle> onSelect;
  final ValueChanged<OilVehicle?> onSetup;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        if (vehicles.length > 1) ...[
          Text(
            context.tr('oil_ref_pick_car'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: vehicles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final v = vehicles[i];
                final on = selected?.id == v.id;
                return ChoiceChip(
                  label: Text(
                    v.plate.isNotEmpty
                        ? v.plate
                        : (v.model.isNotEmpty ? v.model : v.id),
                    style: TextStyle(
                      color: on ? Colors.white : const Color(0xFF1A2E1B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  selected: on,
                  selectedColor: AppColors.primary,
                  onSelected: (_) {
                    onSelect(v);
                    if (!v.isRecommendationReady) {
                      onSetup(v);
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (selected != null && !selected!.isRecommendationReady)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('oil_ref_car_incomplete'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => onSetup(selected),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: Text(context.tr('oil_setup')),
                ),
              ],
            ),
          ),
        const _SaeGuideSection(),
      ],
    );
  }
}

/// «Мой ҳақида» tabi: SAE qo'llanma (akkordeonlar) + qiyosiy jadval.
class _SaeGuideSection extends StatelessWidget {
  const _SaeGuideSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD5E5D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('oil_sae_guide_title'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Color(0xFF1A2E1C),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('oil_sae_guide_intro'),
            style: const TextStyle(
                fontSize: 12.5, height: 1.4, color: Color(0xFF4A5A4C)),
          ),
          const SizedBox(height: 12),
          ...OilRefCatalog.saeGuide.asMap().entries.map(
                (e) => _SaeAccordion(
                  entry: e.value,
                  initiallyExpanded: e.key == 0,
                ),
              ),
          const SizedBox(height: 16),
          Text(
            context.tr('oil_sae_compare_title'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: Color(0xFF1A2E1C),
            ),
          ),
          const SizedBox(height: 8),
          const _SaeCompareTable(),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _SaeAccordion extends StatelessWidget {
  const _SaeAccordion({required this.entry, required this.initiallyExpanded});

  final SaeGuideEntry entry;
  final bool initiallyExpanded;

  static Color _badgeColor(String badge) => switch (badge) {
        'ok' => const Color(0xFF2E7D32),
        'hot' => const Color(0xFFE65100),
        'warn' => const Color(0xFFF9A825),
        'old' => const Color(0xFF6D4C41),
        'min' => const Color(0xFF546E7A),
        _ => const Color(0xFF546E7A),
      };

  @override
  Widget build(BuildContext context) {
    final color = _badgeColor(entry.badge);
    final lang = oilLangOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAF7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0EBE0)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape:
              const RoundedRectangleBorder(side: BorderSide.none),
          leading: Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              entry.sae,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          title: Text(
            entry.sae,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          subtitle: Text(
            entry.subtitle.t(lang),
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7C6E)),
          ),
          children: [
            _param(context.tr('oil_sae_param_thickness'), entry.thickness.t(lang)),
            _param(context.tr('oil_sae_param_hot'), entry.hotProtect.t(lang)),
            _param(context.tr('oil_sae_param_main'), entry.main.t(lang)),
            _param(context.tr('oil_sae_param_engines'), entry.engines.t(lang)),
            _param(context.tr('oil_sae_param_chevy'), entry.chevy.t(lang)),
            _param(context.tr('oil_sae_param_pros'), entry.pros.t(lang)),
            _param(context.tr('oil_sae_param_cons'), entry.cons.t(lang)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: entry.lpgBad
                    ? const Color(0xFFFFF0F0)
                    : const Color(0xFFEAF6EB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: entry.lpgBad
                      ? const Color(0xFFFFCDD2)
                      : const Color(0xFFB7DFB9),
                ),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: context.tr('oil_sae_gas_prefix'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(text: entry.lpg.t(lang)),
                  ],
                ),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: entry.lpgBad
                      ? const Color(0xFFB71C1C)
                      : const Color(0xFF1B5E20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _param(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: Color(0xFF2E7D32),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: Color(0xFF1A2E1C),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaeCompareTable extends StatelessWidget {
  const _SaeCompareTable();

  @override
  Widget build(BuildContext context) {
    final lang = oilLangOf(context);
    final headers = [
      context.tr('oil_sae_compare_metric'),
      '0W-20',
      '5W-30',
      '5W-40',
      '10W-40',
      '15W-40',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 34,
        dataRowMaxHeight: 48,
        columnSpacing: 18,
        horizontalMargin: 10,
        headingRowColor: WidgetStatePropertyAll(const Color(0xFFEEF6EF)),
        border: TableBorder.all(color: const Color(0xFFE0EBE0), width: 1),
        columns: [
          for (final h in headers)
            DataColumn(
              label: Text(
                h,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  color: Color(0xFF1A2E1C),
                ),
              ),
            ),
        ],
        rows: [
          for (final row in OilRefCatalog.saeCompareRows)
            DataRow(
              cells: [
                for (var i = 0; i < row.length; i++)
                  DataCell(
                    Text(
                      row[i].t(lang),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w500,
                        color: row[i].t(lang).contains('✅')
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFF344736),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _OilRefList extends StatelessWidget {
  const _OilRefList({required this.products, required this.emptyMsg});

  final List<OilRefProduct> products;
  final String emptyMsg;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Center(
        child: Text(emptyMsg, style: TextStyle(color: Colors.grey.shade600)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
      itemCount: products.length,
      itemBuilder: (_, i) => _OilRefCard(product: products[i], index: i + 1),
    );
  }
}

class _OilRefCard extends StatelessWidget {
  const _OilRefCard({required this.product, required this.index});

  final OilRefProduct product;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final stars = '★' * p.chevCompat + '☆' * (5 - p.chevCompat);
    final lpgStars = '★' * p.lpgCngCompat + '☆' * (5 - p.lpgCngCompat);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showDetail(context, p),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _typeColor(p.oilType).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$index',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: _typeColor(p.oilType),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.brand,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF7B1FA2),
                            fontWeight: FontWeight.w800,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        Text(
                          p.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _ratingColor(p.rating),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${p.rating}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _chip(p.sae, Colors.blue),
                  _chip(p.api, Colors.indigo),
                  if (p.acea.isNotEmpty) _chip(p.acea, Colors.teal),
                  if (p.dexos.isNotEmpty)
                    _chip(p.dexos, const Color(0xFF2E7D32)),
                  _chip(
                    context.tr('oil_ref_country').replaceAll('{c}', p.country),
                    Colors.blueGrey,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context
                    .tr('oil_ref_chev_stars')
                    .replaceAll('{stars}', stars)
                    .replaceAll('{n}', '${p.chevCompat}'),
                style: TextStyle(fontSize: 11, color: Colors.amber.shade800),
              ),
              const SizedBox(height: 2),
              Text(
                context
                    .tr('oil_ref_lpg_stars')
                    .replaceAll('{stars}', lpgStars)
                    .replaceAll('{n}', '${p.lpgCngCompat}'),
                style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  context
                      .tr('oil_ref_interval')
                      .replaceAll('{km}', p.intervalKm),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static Color _typeColor(OilRefType t) => switch (t) {
        OilRefType.full => const Color(0xFF1B7A28),
        OilRefType.semi => const Color(0xFFE65100),
        OilRefType.mineral => const Color(0xFF5D4037),
      };

  static Color _ratingColor(double r) {
    if (r >= 9.0) return const Color(0xFF2E7D32);
    if (r >= 8.0) return const Color(0xFFF57F17);
    return const Color(0xFF795548);
  }

  static void _showDetail(BuildContext context, OilRefProduct p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        minChildSize: 0.35,
        expand: false,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${p.brand} ${p.name}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              ctx.tr('oil_ref_country').replaceAll('{c}', p.country),
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            _detailRow('SAE', p.sae),
            _detailRow('API', p.api),
            if (p.acea.isNotEmpty) _detailRow('ACEA', p.acea),
            if (p.dexos.isNotEmpty) _detailRow('Dexos', p.dexos),
            _detailRow(
              ctx.tr('oil_ref_chev_label'),
              '${'★' * p.chevCompat}${'☆' * (5 - p.chevCompat)} ${p.chevCompat}/5',
            ),
            _detailRow(
              ctx.tr('oil_ref_lpg_label'),
              '${'★' * p.lpgCngCompat}${'☆' * (5 - p.lpgCngCompat)} ${p.lpgCngCompat}/5',
            ),
            _detailRow(
              ctx.tr('oil_ref_interval_label'),
              ctx.tr('oil_ref_interval').replaceAll('{km}', p.intervalKm),
            ),
            _detailRow(ctx.tr('oil_ref_rating_label'), '${p.rating}/10'),
          ],
        ),
      ),
    );
  }

  static Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
