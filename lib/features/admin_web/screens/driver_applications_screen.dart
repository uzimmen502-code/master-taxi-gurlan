import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/driver_repository.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_driver_requests_service.dart';

/// Админ web — `driver_requests`.
///
/// 3 ustun (статус): Кутаётган | Тасдиқланган | Рад этилган.
/// Ҳар статус ustuni ichida: Маҳаллий | Маршрут | Шаҳарлараро (yonma-yon).
/// Кенг экран: 3 статус ustuni yonma-yon. Тор: PageView (100% kenglik).
class DriverApplicationsScreen extends StatefulWidget {
  const DriverApplicationsScreen({super.key});

  @override
  State<DriverApplicationsScreen> createState() =>
      _DriverApplicationsScreenState();
}

class _StatusColumnMeta {
  const _StatusColumnMeta(this.status, this.title, this.color);
  final String status;
  final String title;
  final Color color;
}

const _statusColumns = [
  _StatusColumnMeta('pending', '🟠 Кутаётган', AppColors.primary),
  _StatusColumnMeta('approved', '🟢 Тасдиқланган', AppColors.primary),
  _StatusColumnMeta('rejected', '🔴 Рад / Чиқарilgan', Color(0xFFD32F2F)),
];

class _DriverApplicationsScreenState extends State<DriverApplicationsScreen> {
  static const _wideBreakpoint = 1100.0;
  late final PageController _pageCtrl;
  int _pageIndex = 0;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= _wideBreakpoint) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _statusColumns.length; i++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: i == 0 ? 12 : 6,
                            right: i == _statusColumns.length - 1 ? 12 : 6,
                            top: 12,
                            bottom: 12,
                          ),
                          child: _StatusColumnPanel(
                            meta: _statusColumns[i],
                            searchQuery: _searchQuery,
                          ),
                        ),
                      ),
                  ],
                );
              }
              return Column(
                children: [
                  _narrowStatusStrip(),
                  Expanded(
                    child: PageView(
                      controller: _pageCtrl,
                      onPageChanged: (i) => setState(() => _pageIndex = i),
                      children: [
                        for (final meta in _statusColumns)
                          SizedBox(
                            width: constraints.maxWidth,
                            child: _StatusColumnPanel(
                              meta: meta,
                              searchQuery: _searchQuery,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _narrowStatusStrip() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_statusColumns.length, (i) {
          final meta = _statusColumns[i];
          final active = i == _pageIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              label: Text(meta.title, style: const TextStyle(fontSize: 12)),
              selected: active,
              onSelected: (_) {
                setState(() => _pageIndex = i);
                _pageCtrl.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                );
              },
              selectedColor: meta.color.withValues(alpha: 0.2),
              checkmarkColor: meta.color,
              labelStyle: TextStyle(
                color: active ? meta.color : Colors.grey.shade700,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('🚗 Ҳайдовчи аризалари',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const Spacer(),
          // Pending count badge — Real-time.
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('driver_requests')
                .where('status', isEqualTo: 'pending')
                .limit(500)
                .snapshots(),
            builder: (ctx, snap) {
              final n = snap.data?.docs.length ?? 0;
              if (n == 0) return const SizedBox.shrink();
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.pending_actions,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text('$n та кутяпти',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ]),
              );
            },
          ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
          decoration: InputDecoration(
            hintText: 'Қидириш: ism, telefon, avto…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
            isDense: true,
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 10),
        const _DriverApprovalModeTile(),
        const SizedBox(height: 10),
        const _ResetTaxiDriversRegistryTile(),
      ]),
    );
  }
}

/// Admin: marshrut/mahalliy/shaharlararo haydovchi bazasini tozalash.
class _ResetTaxiDriversRegistryTile extends StatefulWidget {
  const _ResetTaxiDriversRegistryTile();

  @override
  State<_ResetTaxiDriversRegistryTile> createState() =>
      _ResetTaxiDriversRegistryTileState();
}

class _ResetTaxiDriversRegistryTileState
    extends State<_ResetTaxiDriversRegistryTile> {
  bool _busy = false;

  Future<void> _runReset() async {
    final adminPhone = context.read<AdminAuthService>().phone ?? '';
    if (adminPhone.isEmpty) {
      _snack('Admin telefon topilmadi');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ Ҳайдовчilar bazasini tozalash'),
        content: const Text(
          'Маршрут, маҳаллий ва шаҳарлараро бўйича барча аризалар, '
          'navbat, jadval va intercity ro\'yxatlari o\'chiriladi. '
          'Haydovchilar qayta ro\'yxatdan o\'tishi kerak.\n\n'
          'Davom etish uchun RESET_TAXI_DRIVERS deb yozing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Тозалаш'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final result = await AdminDriverRequestsService().resetTaxiDriversRegistry(
      adminPhone: adminPhone,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.error != null) {
      _snack(result.error!);
      return;
    }
    _snack('Тозаланди: ${result.stats}');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(10),
      child: ListTile(
        leading: Icon(Icons.delete_sweep, color: Colors.red.shade700),
        title: Text(
          'Такси ҳайдовчилар базасини тозалаш',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.red.shade900,
            fontSize: 14,
          ),
        ),
        subtitle: const Text(
          'Маршрут + маҳаллий + шаҳарлараро — yangi ro\'yxatdan o\'tish',
          style: TextStyle(fontSize: 12),
        ),
        trailing: _busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: _runReset,
                child: const Text('Ишга тушириш'),
              ),
      ),
    );
  }
}

class _DriverApprovalModeTile extends StatelessWidget {
  const _DriverApprovalModeTile();

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DriverRepository>();
    return StreamBuilder<String>(
      stream: repo.watchDriverApprovalMode(),
      builder: (context, snap) {
        final mode = snap.data ?? 'manual';
        final manual = mode == 'manual';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: manual ? Colors.orange.shade50 : Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: manual ? Colors.orange.shade200 : Colors.green.shade200,
            ),
          ),
          child: Row(children: [
            Icon(
              manual ? Icons.admin_panel_settings : Icons.flash_on,
              color: manual ? Colors.orange.shade800 : Colors.green.shade700,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                manual
                    ? 'Driver approval: MANUAL — янги ҳайдовчилар админ тасдиғини кутади'
                    : 'Driver approval: AUTO — янги ҳайдовчилар автомат фаоллашади',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      manual ? Colors.orange.shade900 : Colors.green.shade800,
                ),
              ),
            ),
            OutlinedButton(
              onPressed: manual ? null : () => repo.setDriverApprovalMode('manual'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange.shade800,
                side: BorderSide(
                  color: manual ? Colors.orange.shade700 : Colors.orange.shade200,
                ),
              ),
              child: const Text('MANUAL', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: manual ? () => repo.setDriverApprovalMode('auto') : null,
              icon: const Icon(Icons.flash_on, size: 16),
              label: const Text('AUTO', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.button,
                foregroundColor: Colors.white,
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// Бир статус ustuni: сарлавҳа + ичида 3 ustun (Маҳаллий | Маршрут | Шаҳарлараро).
class _StatusColumnPanel extends StatelessWidget {
  const _StatusColumnPanel({
    required this.meta,
    required this.searchQuery,
  });
  final _StatusColumnMeta meta;
  final String searchQuery;

  bool _matchesSearch(Map<String, dynamic> data, String docId) {
    if (searchQuery.isEmpty) return true;
    final q = searchQuery;
    final fields = [
      docId,
      (data['name'] ?? '').toString(),
      (data['phone'] ?? '').toString(),
      (data['car'] ?? '').toString(),
      (data['plate'] ?? '').toString(),
      (data['taxiType'] ?? '').toString(),
    ];
    for (final f in fields) {
      if (f.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final status = meta.status;
    final accent = meta.color;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: status == 'rejected'
            ? FirebaseFirestore.instance
                .collection('driver_requests')
                .where('status', whereIn: ['rejected', 'revoked'])
                .orderBy('createdAt', descending: true)
                .limit(200)
                .snapshots()
            : FirebaseFirestore.instance
                .collection('driver_requests')
                .where('status', isEqualTo: status)
                .orderBy('createdAt', descending: true)
                .limit(200)
                .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ApplicationsEmptyState(
              icon: Icons.error_outline,
              color: Colors.red,
              title: 'Хатолик',
              msg:
                  'Аризаларни юклаб бўлмади: ${snap.error}\n\n`createdAt` index керак бўлиши мумкин.',
            );
          }

          final allDocs = snap.data?.docs ?? const [];
          final docs = searchQuery.isEmpty
              ? allDocs
              : allDocs
                  .where((d) => _matchesSearch(d.data(), d.id))
                  .toList(growable: false);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.layers, color: accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        meta.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        searchQuery.isEmpty
                            ? '${allDocs.length}'
                            : '${docs.length}/${allDocs.length}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: docs.isEmpty
                    ? _ApplicationsEmptyState(
                        icon: status == 'pending'
                            ? Icons.inbox
                            : status == 'approved'
                                ? Icons.check_circle_outline
                                : Icons.block,
                        color: accent,
                        title: searchQuery.isEmpty ? 'Ариза йўқ' : 'Топилмади',
                        msg: searchQuery.isEmpty
                            ? 'Бу статусда ҳозирча ариза йўқ.'
                            : 'Қidiruv bo\'yicha mos ariza yo\'q.',
                      )
                    : _buildGroupedList(docs, status),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGroupedList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String status,
  ) {
    final groups =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{
      'local': [],
      'marshrut': [],
      'intercity': [],
    };
    for (final doc in docs) {
      final type = _normalizeTaxiType(doc.data()['taxiType'] as String?);
      groups[type]!.add(doc);
    }
    return _TaxiTypeColumnsRow(groups: groups, status: status);
  }
}

class _ApplicationsEmptyState extends StatelessWidget {
  const _ApplicationsEmptyState({
    required this.icon,
    required this.color,
    required this.title,
    required this.msg,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String msg;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

const _driverTypeOrder = ['local', 'marshrut', 'intercity'];
const _minTaxiTypeColumnWidth = 150.0;
const _taxiTypeColumnGap = 6.0;

/// Статус ustuni ichidagi 3 ta такси тури ustuni (yonma-yon).
class _TaxiTypeColumnsRow extends StatelessWidget {
  const _TaxiTypeColumnsRow({
    required this.groups,
    required this.status,
  });

  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> groups;
  final String status;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth =
            _minTaxiTypeColumnWidth * 3 + _taxiTypeColumnGap * 2;

        Widget typeColumn(String type) => _ApplicationsTypeSection(
              title: _driverTypeLabel(type),
              color: _driverTypeColor(type),
              docs: groups[type]!,
              status: status,
            );

        if (constraints.maxWidth >= minWidth) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _driverTypeOrder.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: i == 0 ? 0 : _taxiTypeColumnGap / 2,
                        right: i == _driverTypeOrder.length - 1
                            ? 0
                            : _taxiTypeColumnGap / 2,
                      ),
                      child: typeColumn(_driverTypeOrder[i]),
                    ),
                  ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: SizedBox(
            height: constraints.maxHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _driverTypeOrder.length; i++)
                  SizedBox(
                    width: _minTaxiTypeColumnWidth,
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: i < _driverTypeOrder.length - 1
                            ? _taxiTypeColumnGap
                            : 0,
                      ),
                      child: typeColumn(_driverTypeOrder[i]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _normalizeTaxiType(String? type) {
  if (type == 'marshrut') return 'marshrut';
  if (type == 'intercity') return 'intercity';
  return 'local';
}

String _driverTypeLabel(String type) {
  switch (type) {
    case 'marshrut':
      return 'Маршрут такси';
    case 'intercity':
      return 'Шаҳарлараро';
    default:
      return 'Маҳаллий такси';
  }
}

Color _driverTypeColor(String type) {
  switch (type) {
    case 'marshrut':
      return AppColors.primary;
    case 'intercity':
      return AppColors.primary;
    default:
      return AppColors.primaryMid;
  }
}

/// Маҳаллий | Маршрут | Шаҳарлараро — бир статус ustuni ichidagi bitta ustun.
class _ApplicationsTypeSection extends StatelessWidget {
  const _ApplicationsTypeSection({
    required this.title,
    required this.color,
    required this.docs,
    required this.status,
  });

  final String title;
  final Color color;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String status;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.local_taxi, color: color, size: 18),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${docs.length}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (docs.isEmpty)
            const Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Ариза йўқ',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: docs.length,
                itemBuilder: (_, i) => Padding(
                  padding: EdgeInsets.only(bottom: i < docs.length - 1 ? 8 : 0),
                  child: _ApplicationCard(
                    doc: docs[i],
                    status: docs[i].data()['status']?.toString() ?? status,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ApplicationCard extends StatefulWidget {
  const _ApplicationCard({required this.doc, required this.status});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String status;

  @override
  State<_ApplicationCard> createState() => _ApplicationCardState();
}

class _ApplicationCardState extends State<_ApplicationCard> {
  bool _busy = false;
  final _requestsService = AdminDriverRequestsService();

  String _f(String key, [String fallback = '']) {
    final v = widget.doc.data()[key];
    return v?.toString() ?? fallback;
  }

  DateTime? _ts(String key) {
    final v = widget.doc.data()[key];
    if (v is Timestamp) return v.toDate();
    return null;
  }

  Future<void> _approve() async {
    setState(() => _busy = true);
    final auth = context.read<AdminAuthService>();
    final adminPhone = auth.phone ?? '';
    if (adminPhone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text('Admin sessiyasi topilmadi'),
          ),
        );
        setState(() => _busy = false);
      }
      return;
    }

    final result = await _requestsService.approve(
      adminPhone: adminPhone,
      requestId: widget.doc.id,
    );

    if (!mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text(result.error!)),
      );
      setState(() => _busy = false);
      return;
    }

    final msg = result.warnings.isEmpty
        ? '✅ Ариза тасдиқланди: ${_f('name', 'Aризa')}'
        : '✅ Ариза тасдиқланди. Қўшимча: ${result.warnings.join(' | ')}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: result.warnings.isEmpty ? AppColors.primary : Colors.orange,
        duration: const Duration(seconds: 6),
        content: Text(msg),
      ),
    );
    setState(() => _busy = false);
  }

  Future<void> _reject() async {
    final reasonCtrl = TextEditingController();
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Аризани рад этиш'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Рад этиш сабабини киритинг:'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                hintText: 'Masalan: avtomobil talabga javob bermaydi',
                border: OutlineInputBorder(),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Бекор'),
            ),
            TextButton(
              onPressed: () {
                if (reasonCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, reasonCtrl.text.trim());
              },
              child:
                  const Text('Рад этиш', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (reason == null || !mounted) return;

      setState(() => _busy = true);
      final auth = context.read<AdminAuthService>();
      final err = await _requestsService.reject(
        adminPhone: auth.phone ?? '',
        requestId: widget.doc.id,
        reason: reason,
      );
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text(err)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.orange,
            content: Text('Ариза рад этилди: ${_f('name', 'Ариза')}'),
          ),
        );
      }
    } finally {
      reasonCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copyPhone() {
    final phone = _f('phone');
    if (phone.isEmpty) return;
    Clipboard.setData(ClipboardData(text: phone));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Nusxa olindi: $phone'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _driverPhoneId() {
    final fromPhone = phoneDigits(_f('phone'));
    if (fromPhone.length >= 9) return fromPhone;
    return phoneDigits(widget.doc.id);
  }

  bool _isDriverActive(
    Map<String, dynamic>? driver,
    Map<String, dynamic>? intercity,
    String taxiType,
  ) {
    if (taxiType == 'intercity') {
      return intercity?['isActive'] == true;
    }
    return driver?['isOnline'] == true;
  }

  Future<void> _revoke() async {
    final reasonCtrl = TextEditingController();
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Haydovchini chiqarib tashlash'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
              'Haydovchi faol emas. Ruxsatni bekor qilish sababini kiriting:',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                hintText: 'Masalan: navbat vaqtida ishga chiqmadi',
                border: OutlineInputBorder(),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Bekor'),
            ),
            TextButton(
              onPressed: () {
                if (reasonCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, reasonCtrl.text.trim());
              },
              child: const Text(
                'Chiqarib tashlash',
                style: TextStyle(color: Colors.deepOrange),
              ),
            ),
          ],
        ),
      );
      if (reason == null || !mounted) return;

      setState(() => _busy = true);
      final auth = context.read<AdminAuthService>();
      final err = await _requestsService.revoke(
        adminPhone: auth.phone ?? '',
        requestId: widget.doc.id,
        reason: reason,
      );
      if (!mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text(err)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.deepOrange,
            content: Text(
              _normalizeTaxiType(_f('taxiType')) == 'marshrut'
                  ? 'Chiqarildi: ${_f('name', 'Haydovchi')} marshrut navbatidan olib tashlandi'
                  : 'Chiqarib tashlandi: ${_f('name', 'Haydovchi')}',
            ),
          ),
        );
      }
    } finally {
      reasonCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _approvedActivityFooter(
    Map<String, dynamic>? driver,
    Map<String, dynamic>? intercity,
    String taxiType,
  ) {
    final active = _isDriverActive(driver, intercity, taxiType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius:
            const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.circle : Icons.circle_outlined,
                size: 10,
                color: active ? AppColors.primaryDark : Colors.orange.shade800,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  active ? 'Faol (online/panelda)' : 'Faol emas — navbat vaqtida chiqmadi',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: active ? AppColors.primaryDark : Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
          if (!active) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _revoke,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_remove, size: 16),
              label: const Text('Chiqarib tashlash'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.deepOrange.shade800,
                side: BorderSide(color: Colors.deepOrange.shade400),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildApprovedFooter(String taxiType) {
    final phoneId = _driverPhoneId();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('drivers')
          .doc(phoneId)
          .snapshots(),
      builder: (context, driverSnap) {
        final driver = driverSnap.data?.data();
        if (taxiType == 'intercity') {
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('intercity_drivers')
                .doc(phoneId)
                .snapshots(),
            builder: (context, icSnap) {
              return _approvedActivityFooter(
                driver,
                icSnap.data?.data(),
                taxiType,
              );
            },
          );
        }
        return _approvedActivityFooter(driver, null, taxiType);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final docStatus = _f('status', widget.status);
    final color = docStatus == 'pending'
        ? AppColors.primary
        : docStatus == 'approved'
            ? AppColors.primary
            : docStatus == 'revoked'
                ? AppColors.primary
                : const Color(0xFFD32F2F);
    final createdAt = _ts('createdAt');
    final taxiType = _normalizeTaxiType(_f('taxiType'));

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withValues(alpha: 0.2),
              child: Text(
                  (_f('name').isEmpty ? '?' : _f('name').substring(0, 1))
                      .toUpperCase(),
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_f('name', 'Ҳайдовчи номи йўқ'),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(_f('phone', 'Тел йўқ'),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                  ]),
            ),
            if (_f('phone').isNotEmpty)
              IconButton(
                onPressed: _copyPhone,
                icon: const Icon(Icons.copy, size: 16),
                tooltip: 'Telefon nusxasi',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('🚗 Авто', _f('car', '—')),
              _row('🚕 Тур',
                  _driverTypeLabel(_normalizeTaxiType(_f('taxiType')))),
              _row('🔢 Рақам', _f('plate', _f('carNumber', '—'))),
              if (_f('passport').isNotEmpty) _row('📃 Pasport', _f('passport')),
              if (_f('birthYear').isNotEmpty)
                _row('🎂 Туғилган йил', _f('birthYear')),
              if (_f('experience').isNotEmpty)
                _row('📅 Тажриба', _f('experience')),
              if (docStatus == 'rejected' && _f('rejectedReason').isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '⛔ ${_f('rejectedReason')}',
                    style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                  ),
                ),
              if (docStatus == 'revoked' && _f('revokedReason').isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '🚫 Chiqarilgan: ${_f('revokedReason')}',
                    style:
                        TextStyle(fontSize: 11, color: Colors.deepPurple.shade700),
                  ),
                ),
              if (_f('routeLabel').isNotEmpty)
                _row('📍 Маршрут', _f('routeLabel'))
              else if (_f('routeFrom').isNotEmpty || _f('routeTo').isNotEmpty)
                _row(
                  '📍 Маршрут',
                  '${_f('routeFrom')} → ${_f('routeTo')}',
                ),
              if (_normalizeTaxiType(_f('taxiType')) == 'marshrut' &&
                  _f('routeLabel').isEmpty &&
                  _f('routeFrom').isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'в„№пёЏ Маршрут киритилмаган',
                    style: TextStyle(fontSize: 10, color: Colors.orange.shade800),
                  ),
                ),
              if (createdAt != null) ...[
                const SizedBox(height: 6),
                Text('вЏ± ${DateFormat('dd.MM.yyyy HH:mm').format(createdAt)}',
                    style:
                        TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ],
          ),
        ),
        if (docStatus == 'pending')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _reject,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Рад этиш'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _approve,
                  icon: _busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 16),
                  label: const Text('Тасдиқ'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.button,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ]),
          ),
        if (docStatus == 'approved') _buildApprovedFooter(taxiType),
      ]),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 95,
          child: Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}
