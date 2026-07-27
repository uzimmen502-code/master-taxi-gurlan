import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/procurement_product.dart';
import '../../../models/sell_offer_item.dart';
import '../../../models/sell_submission.dart';
import '../../../repositories/sell_offers_repository.dart';
import '../../../services/collection_service.dart';
import '../../../services/procurement_prices_service.dart';
import '../../../core/theme/app_theme.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_sell_service.dart';

/// Админ — платформага юборилган сотиш таклифлари (jadval ko‘rinishi).
class SellSubmissionsAdminScreen extends StatefulWidget {
  const SellSubmissionsAdminScreen({super.key});

  @override
  State<SellSubmissionsAdminScreen> createState() =>
      _SellSubmissionsAdminScreenState();
}

class _SellSubmissionsAdminScreenState extends State<SellSubmissionsAdminScreen> {
  String _statusFilter = 'pending';
  final _searchCtrl = TextEditingController();
  String _query = '';

  static const _blue = AppColors.primary;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<SellSubmission> _filter(List<SellSubmission> list) {
    final q = _query.trim().toLowerCase();
    return list.where((s) {
      if (_statusFilter != 'all' && s.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      if (s.userPhone.contains(q) || s.userName.toLowerCase().contains(q)) {
        return true;
      }
      for (final it in s.items) {
        if (it.productName.toLowerCase().contains(q) ||
            it.quantityText.toLowerCase().contains(q)) {
          return true;
        }
      }
      return false;
    }).toList(growable: false);
  }

  Future<void> _setStatus(SellSubmission s, String status) async {
    final adminPhone = _adminPhoneForCf();
    if (adminPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Admin telefon topilmadi — qayta kiring'),
        ),
      );
      return;
    }
    try {
      await AdminSellService.updateStatus(
        adminPhone: adminPhone,
        submissionId: s.id,
        status: status,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${SellSubmission.statusLabel(status)}: '
            '${s.userName.isNotEmpty ? s.userName : s.userPhone}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
      );
    }
  }

  Future<void> _forward(SellSubmission s) async {
    final result = await showDialog<_ForwardOptions>(
      context: context,
      builder: (ctx) => _ForwardDialog(submission: s),
    );
    if (result == null || !mounted) return;
    final adminPhone = _adminPhoneForCf();
    if (adminPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Admin telefon topilmadi — qayta kiring'),
        ),
      );
      return;
    }
    try {
      if (s.status == 'pending') {
        await AdminSellService.updateStatus(
          adminPhone: adminPhone,
          submissionId: s.id,
          status: 'reviewed',
        );
      }
      await AdminSellService.forward(
        adminPhone: adminPhone,
        submissionId: s.id,
        forwardAudience: result.audience,
        targetUserIds: result.phones,
        adminNote: result.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.audience == 'all'
                ? 'Taklif barcha foydalanuvchilarga yo\'naltirildi'
                : 'Taklif ${result.phones.length} ta foydalanuvchiga yuborildi',
          ),
          backgroundColor: AppColors.button,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
      );
    }
  }

  String _adminPhoneForCf() {
    final auth = context.read<AdminAuthService>();
    if (auth.phoneDigits != null && auth.phoneDigits!.isNotEmpty) {
      return auth.phoneDigits!;
    }
    final d = phoneDigits(auth.phone ?? '');
    return d.length >= 9 ? d : '';
  }

  Future<void> _createCollection(SellSubmission s) async {
    final adminPhone = _adminPhoneForCf();
    if (adminPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Admin telefon topilmadi — qayta kiring'),
        ),
      );
      return;
    }

    final pricesService = context.read<ProcurementPricesService>();
    late final List<ProcurementProduct> products;
    late final List<_CourierOption> couriers;
    try {
      final results = await Future.wait([
        pricesService.getAll(),
        _loadCouriers(),
      ]);
      products = (results[0] as List<ProcurementProduct>)
          .where((p) => p.active)
          .toList(growable: false);
      couriers = results[1] as List<_CourierOption>;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
      );
      return;
    }
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Харид нархлари каталоги бўш')),
      );
      return;
    }
    if (couriers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Курьерлар рўйхати бўш — аввал курьер қўшинг')),
      );
      return;
    }

    final result = await showDialog<_CollectionTaskInput>(
      context: context,
      builder: (ctx) => _CollectionTaskDialog(
        submission: s,
        products: products,
        couriers: couriers,
      ),
    );
    if (result == null || !mounted) return;

    try {
      final created = await CollectionService.createCollectionTask(
        adminPhone: adminPhone,
        submissionId: s.id,
        items: result.items,
        courierPhone: result.courierPhone,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.button,
          content: Text(
            'Йиғиб олиш вазифаси яратилди · ${formatMoney(created.totalValue)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
      );
    }
  }

  Future<List<_CourierOption>> _loadCouriers() async {
    final snap =
        await FirebaseFirestore.instance.collection('couriers').get();
    final list = snap.docs.map((d) {
      final data = d.data();
      return _CourierOption(
        phone: phoneDigits((data['phone'] ?? d.id) as String? ?? d.id),
        name: (data['name'] ?? '') as String,
      );
    }).where((c) => c.phone.isNotEmpty).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.sell_outlined, color: _blue),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Сотиш таклифлари',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Платформа формаси · омма эълонлари — Иш топ',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Исм, телефон, маҳсулот…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              _statusChip('pending', 'Янги'),
              _statusChip('reviewed', 'Кўрилди'),
              _statusChip('archived', 'Архив'),
              _statusChip('all', 'Барчаси'),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<SellSubmission>>(
            stream: context.read<SellOffersRepository>().watchForAdmin(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Хатолик: ${snap.error}'));
              }
              final all = snap.data ?? const [];
              final filtered = _filter(all);
              if (filtered.isEmpty) {
                return const Center(child: Text('Таклифлар топилмади'));
              }
              return _SubmissionsTable(
                submissions: filtered,
                onStatus: _setStatus,
                onForward: _forward,
                onCollect: _createCollection,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _statusChip(String value, String label) {
    final selected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: _blue.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? _blue : Colors.black87,
      ),
      onSelected: (_) => setState(() => _statusFilter = value),
    );
  }
}

class _SubmissionsTable extends StatelessWidget {
  const _SubmissionsTable({
    required this.submissions,
    required this.onStatus,
    required this.onForward,
    required this.onCollect,
  });

  final List<SellSubmission> submissions;
  final Future<void> Function(SellSubmission, String) onStatus;
  final Future<void> Function(SellSubmission) onForward;
  final Future<void> Function(SellSubmission) onCollect;

  static const _headerBg = Color(0xFFE3F2FD);
  static const _border = Color(0xFFE0E0E0);
  static const _groupBorder = Color(0xFFBDBDBD);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 960),
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(88),
                  1: FixedColumnWidth(220),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(1.2),
                  4: FixedColumnWidth(100),
                  5: FixedColumnWidth(96),
                  6: FixedColumnWidth(152),
                },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                border: TableBorder(
                  horizontalInside: BorderSide(color: _border.withValues(alpha: 0.7)),
                  verticalInside: const BorderSide(color: _border),
                ),
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: _headerBg),
                    children: _headerCells(),
                  ),
                  for (var gi = 0; gi < submissions.length; gi++)
                    ..._rowsForSubmission(
                      submissions[gi],
                      isLastGroup: gi == submissions.length - 1,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _headerCells() {
    const style = TextStyle(fontWeight: FontWeight.w800, fontSize: 13);
    return const [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Text('Vaqt', style: style),
      ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Text('Kim', style: style),
      ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Text('Маҳсулот', style: style),
      ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Text('Миқdor', style: style),
      ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Text('Narx', style: style, textAlign: TextAlign.right),
      ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Text('Holat', style: style),
      ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text('Amal', style: style, textAlign: TextAlign.center),
      ),
    ];
  }

  List<TableRow> _rowsForSubmission(
    SellSubmission s, {
    required bool isLastGroup,
  }) {
    final items = s.items.isEmpty
        ? const [
            SellOfferItem(
              productName: '—',
              quantityText: '—',
              priceOffered: 0,
              isRecurring: false,
            ),
          ]
        : s.items;
    final rows = <TableRow>[];

    for (var i = 0; i < items.length; i++) {
      final isFirst = i == 0;
      final isLastItem = i == items.length - 1;
      rows.add(
        TableRow(
          decoration: BoxDecoration(
            color: i.isOdd ? const Color(0xFFFAFAFA) : Colors.white,
            border: isLastItem && !isLastGroup
                ? const Border(bottom: BorderSide(color: _groupBorder, width: 1.5))
                : null,
          ),
          children: [
            _cell(isFirst ? _vaqtCell(s.createdAt) : const SizedBox.shrink()),
            _cell(isFirst ? _kimCell(s) : const SizedBox.shrink()),
            _cell(Text(items[i].productName, style: _bodyStyle)),
            _cell(Text(items[i].quantityText, style: _bodyStyle)),
            _cell(
              Text(
                items[i].priceOffered > 0
                    ? formatPrice(items[i].priceOffered)
                    : '—',
                style: _bodyStyle.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.right,
              ),
            ),
            _cell(isFirst ? _holatCell(s) : const SizedBox.shrink()),
            _cell(isFirst ? _amalCell(s) : const SizedBox.shrink()),
          ],
        ),
      );
    }
    return rows;
  }

  static const _bodyStyle = TextStyle(fontSize: 13, height: 1.25);

  Widget _cell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: child,
    );
  }

  Widget _vaqtCell(DateTime date) {
    final d =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
    final t =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(d, style: _bodyStyle.copyWith(fontWeight: FontWeight.w700)),
        Text(t, style: _bodyStyle.copyWith(color: Colors.black45, fontSize: 11)),
      ],
    );
  }

  Widget _kimCell(SellSubmission s) {
    final name = s.userName.trim().isNotEmpty ? s.userName.trim() : 'Номsiz';
    final phone = s.userPhone.trim();
    final address = s.pickupAddress.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(name, style: _bodyStyle.copyWith(fontWeight: FontWeight.w700)),
        if (phone.isNotEmpty)
          Text(
            phone,
            style: _bodyStyle.copyWith(color: Colors.black54, fontSize: 11),
          ),
        if (address.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            address,
            style: _bodyStyle.copyWith(fontSize: 11, height: 1.25),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (s.hasPickupGps) ...[
          const SizedBox(height: 4),
          InkWell(
            onTap: () {
              final url = s.mapsUrl;
              if (url == null) return;
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: Text(
              '📍 ${s.pickupLat!.toStringAsFixed(5)}, '
              '${s.pickupLng!.toStringAsFixed(5)} · Xarita',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.blue.shade800,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ] else if (address.isEmpty)
          Text(
            'Мanzil йўқ',
            style: _bodyStyle.copyWith(
              fontSize: 10,
              color: Colors.orange.shade800,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }

  Widget _holatCell(SellSubmission s) {
    final status = s.status;
    final (Color bg, Color fg) = switch (status) {
      'reviewed' => (Colors.green, Colors.green.shade800),
      'archived' => (Colors.grey, Colors.grey.shade800),
      _ => (Colors.orange, Colors.orange.shade800),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bg.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            SellSubmission.statusLabel(status),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
        if (s.isForwarded) ...[
          const SizedBox(height: 4),
          Text(
            '📤 ${s.forwardAudienceLabel}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.blue.shade800,
            ),
          ),
        ],
        if (s.inCollection) ...[
          const SizedBox(height: 4),
          Tooltip(
            message: s.collectionTaskId.isEmpty
                ? 'Йиғиб олишда'
                : 'Vazifa: ${s.collectionTaskId}',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '🧺 Йиғишда'
                '${s.collectionTaskId.isEmpty ? '' : ' · ${s.collectionTaskId.substring(0, s.collectionTaskId.length > 6 ? 6 : s.collectionTaskId.length)}…'}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.teal.shade800,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _amalCell(SellSubmission s) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (s.status == 'pending')
          IconButton(
            tooltip: 'Кўрилди',
            icon: const Icon(Icons.check_circle_outline, color: AppColors.primary),
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => onStatus(s, 'reviewed'),
          ),
        if (s.status != 'archived' && !s.inCollection)
          IconButton(
            tooltip: 'Йиғиб олиш вазифаси',
            icon: Icon(Icons.shopping_basket_outlined, color: Colors.teal.shade700),
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => onCollect(s),
          ),
        if (s.status != 'archived' && !s.isForwarded)
          IconButton(
            tooltip: 'Foydalanuvchilarga yo\'naltirish',
            icon: const Icon(Icons.send_outlined, color: AppColors.primary),
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => onForward(s),
          ),
        if (s.status != 'archived')
          IconButton(
            tooltip: 'Архив',
            icon: Icon(Icons.archive_outlined, color: Colors.grey.shade700),
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => onStatus(s, 'archived'),
          ),
        if (s.status == 'archived')
          IconButton(
            tooltip: 'Янгига қайтар',
            icon: const Icon(Icons.restore, color: Colors.orange),
            iconSize: 20,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => onStatus(s, 'pending'),
          ),
      ],
    );
  }
}

class _CourierOption {
  const _CourierOption({required this.phone, required this.name});

  final String phone;
  final String name;

  String get label => name.isEmpty ? phone : '$name · $phone';
}

class _CollectionTaskInput {
  const _CollectionTaskInput({required this.items, required this.courierPhone});

  final List<Map<String, dynamic>> items;
  final String courierPhone;
}

class _ItemRowState {
  _ItemRowState({this.product, String qty = '', String price = ''})
      : qtyCtrl = TextEditingController(text: qty),
        priceCtrl = TextEditingController(text: price);

  ProcurementProduct? product;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;

  num get qty => num.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0;

  int get unitPrice =>
      int.tryParse(priceCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

  int get lineTotal => (qty * unitPrice).round();

  void dispose() {
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }
}

/// Сотиш таклифидан йиғиб олиш вазифаси яратиш диалоги.
class _CollectionTaskDialog extends StatefulWidget {
  const _CollectionTaskDialog({
    required this.submission,
    required this.products,
    required this.couriers,
  });

  final SellSubmission submission;
  final List<ProcurementProduct> products;
  final List<_CourierOption> couriers;

  @override
  State<_CollectionTaskDialog> createState() => _CollectionTaskDialogState();
}

class _CollectionTaskDialogState extends State<_CollectionTaskDialog> {
  final List<_ItemRowState> _rows = [];
  _CourierOption? _courier;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final it in widget.submission.items) {
      final product = _matchProduct(it.productName);
      final qty = _leadingNumber(it.quantityText);
      _rows.add(
        _ItemRowState(
          product: product,
          qty: qty ?? '',
          price: product != null ? product.price.toString() : '',
        ),
      );
    }
    if (_rows.isEmpty) _rows.add(_ItemRowState());
    if (widget.couriers.length == 1) _courier = widget.couriers.first;
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  ProcurementProduct? _matchProduct(String name) {
    final n = name.trim().toLowerCase();
    if (n.isEmpty) return null;
    for (final p in widget.products) {
      final l = p.label.trim().toLowerCase();
      if (l == n || n.contains(l) || l.contains(n)) return p;
    }
    return null;
  }

  static String? _leadingNumber(String text) {
    final m = RegExp(r'[\d]+([.,][\d]+)?').firstMatch(text);
    return m?.group(0)?.replaceAll(',', '.');
  }

  int get _total => _rows.fold(0, (acc, r) => acc + r.lineTotal);

  void _submit() {
    if (_courier == null) {
      setState(() => _error = 'Курьер танланг');
      return;
    }
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      if (r.product == null) {
        setState(() => _error = '${i + 1}-қатор: маҳсулот танланг');
        return;
      }
      if (r.qty <= 0) {
        setState(() => _error = '${i + 1}-қатор: миқдор нотўғри');
        return;
      }
      items.add({
        'code': r.product!.code,
        'label': r.product!.label,
        'unit': r.product!.unit,
        'qty': r.qty,
        'unitPrice': r.unitPrice,
      });
    }
    if (items.isEmpty) {
      setState(() => _error = 'Камида битта маҳсулот керак');
      return;
    }
    Navigator.pop(
      context,
      _CollectionTaskInput(items: items, courierPhone: _courier!.phone),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.submission;
    return AlertDialog(
      title: const Text('Йиғиб олиш вазифаси'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${s.userName.isNotEmpty ? s.userName : s.userPhone}'
                '${s.pickupAddress.isNotEmpty ? ' · ${s.pickupAddress}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (s.items.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Таклиф: ${s.items.map((e) => '${e.productName} (${e.quantityText})').join(', ')}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
              const SizedBox(height: 14),
              for (var i = 0; i < _rows.length; i++) _itemRow(i),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _rows.add(_ItemRowState())),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Қатор қўшиш'),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<_CourierOption>(
                initialValue: _courier,
                decoration: const InputDecoration(
                  labelText: 'Курьер',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final c in widget.couriers)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _courier = v),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Жами:',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${formatMoney(_total)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.shopping_basket_outlined, size: 18),
          label: const Text('Яратиш'),
        ),
      ],
    );
  }

  Widget _itemRow(int index) {
    final row = _rows[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<ProcurementProduct>(
              initialValue: row.product,
              decoration: const InputDecoration(
                labelText: 'Маҳсулот',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final p in widget.products)
                  DropdownMenuItem(
                    value: p,
                    child: Text('${p.label} (${p.unit})'),
                  ),
              ],
              onChanged: (p) {
                setState(() {
                  row.product = p;
                  if (p != null) row.priceCtrl.text = p.price.toString();
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: row.qtyCtrl,
              decoration: InputDecoration(
                labelText: 'Миқдор',
                suffixText: row.product?.unit,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: row.priceCtrl,
              decoration: const InputDecoration(
                labelText: 'Нарх (сўм)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              row.lineTotal > 0 ? formatPrice(row.lineTotal) : '—',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          IconButton(
            tooltip: 'Ўчириш',
            icon: const Icon(Icons.close, size: 18),
            onPressed: _rows.length <= 1
                ? null
                : () {
                    setState(() {
                      _rows.removeAt(index).dispose();
                    });
                  },
          ),
        ],
      ),
    );
  }
}

class _ForwardOptions {
  const _ForwardOptions({
    required this.audience,
    required this.phones,
    required this.note,
  });

  final String audience;
  final List<String> phones;
  final String note;
}

class _ForwardDialog extends StatefulWidget {
  const _ForwardDialog({required this.submission});

  final SellSubmission submission;

  @override
  State<_ForwardDialog> createState() => _ForwardDialogState();
}

class _ForwardDialogState extends State<_ForwardDialog> {
  String _audience = 'all';
  final _phonesCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _phonesCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  List<String> _parsePhones() {
    return _phonesCtrl.text
        .split(RegExp(r'[,;\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = widget.submission.items.length;
    return AlertDialog(
      title: const Text('Foydalanuvchilarga yo\'naltirish'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.submission.userName.isNotEmpty ? widget.submission.userName : widget.submission.userPhone}'
                ' · $itemCount ta mahsulot',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: _audience,
                onChanged: (v) => setState(() => _audience = v ?? 'all'),
                child: Column(
                  children: const [
                    RadioListTile<String>(
                      title: Text('Barcha foydalanuvchilar'),
                      subtitle: Text('Xabarlar bo\'limida ko\'rinadi'),
                      value: 'all',
                    ),
                    RadioListTile<String>(
                      title: Text('Tanlangan telefonlar'),
                      subtitle: Text('Vergul bilan ajrating'),
                      value: 'selected',
                    ),
                  ],
                ),
              ),
              if (_audience == 'selected') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _phonesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Telefon raqamlar',
                    hintText: '901234567, 909876543',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Admin izohi (ixtiyoriy)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Bekor'),
        ),
        FilledButton.icon(
          onPressed: () {
            final phones = _parsePhones();
            if (_audience == 'selected' && phones.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Kamida bitta telefon kiriting')),
              );
              return;
            }
            Navigator.pop(
              context,
              _ForwardOptions(
                audience: _audience,
                phones: phones,
                note: _noteCtrl.text.trim(),
              ),
            );
          },
          icon: const Icon(Icons.send, size: 18),
          label: const Text('Yo\'naltirish'),
        ),
      ],
    );
  }
}
