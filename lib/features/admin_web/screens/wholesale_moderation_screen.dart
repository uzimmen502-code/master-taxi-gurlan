import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../wholesale/models/wholesale_product.dart';
import '../../wholesale/models/wholesale_seller.dart';
import '../../wholesale/repositories/wholesale_products_repository.dart';
import '../../wholesale/repositories/wholesale_sellers_repository.dart';
import '../services/admin_auth_service.dart';

/// Улгуржи/кичик улгуржи бозор — admin модерацияси.
/// `JobsModerationScreen`нинг live-stream карта-рўйхат андозаси асосида.
/// Cloud Function йўқ — ёзувлар тўғридан-тўғри `firestore.rules`даги
/// admin whitelist-патч орқали чекланади.
class WholesaleModerationScreen extends StatefulWidget {
  const WholesaleModerationScreen({super.key});

  @override
  State<WholesaleModerationScreen> createState() =>
      _WholesaleModerationScreenState();
}

class _WholesaleModerationScreenState extends State<WholesaleModerationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _sellersRepo = WholesaleSellersRepository();
  final _productsRepo = WholesaleProductsRepository();
  String _productStatusFilter = 'all';

  static const _blue = AppColors.primary;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  String get _adminId => context.read<AdminAuthService>().phoneDigits ?? '';

  void _showResult(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: error ? Colors.red : null,
        content: Text(text),
      ),
    );
  }

  Future<String?> _promptNote(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Изоҳ (ихтиёрий)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Бекор қилиш'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Тасдиқлаш'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ҳа', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ─── Сотувчилар ───────────────────────────────────────────────────

  Future<void> _approveSeller(WholesaleSeller s) async {
    try {
      await _sellersRepo.approve(s.phone, adminId: _adminId);
      _showResult('Тасдиқланди: ${s.companyName}');
    } catch (e) {
      _showResult('Хатолик: $e', error: true);
    }
  }

  Future<void> _rejectSeller(WholesaleSeller s) async {
    final note = await _promptNote('«${s.companyName}»ни рад этиш');
    if (note == null || !mounted) return;
    try {
      await _sellersRepo.reject(s.phone, adminId: _adminId, note: note);
      _showResult('Рад этилди: ${s.companyName}');
    } catch (e) {
      _showResult('Хатолик: $e', error: true);
    }
  }

  Widget _sellersTab() {
    return StreamBuilder<List<WholesaleSeller>>(
      stream: _sellersRepo.watchAllForAdmin(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Хатолик: ${snap.error}'));
        }
        final all = snap.data ?? const <WholesaleSeller>[];
        int count(String s) => all.where((e) => e.approvalStatus == s).length;
        return Column(children: [
          const _AutoApproveBar(
            settingsField: 'wholesaleSellerAutoApprove',
            onLabel: 'АВТО тасдиқ: ЁҚИҚ — янги сотувчилар дарҳол тасдиқланади',
            offLabel:
                'ҚЎЛДА тасдиқ — янги сотувчилар admin тасдиғини кутади',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              _summaryCard('Жами', all.length, Colors.blueGrey),
              _summaryCard('Кутяпти', count(WholesaleSeller.statusPending),
                  Colors.orange),
              _summaryCard('Тасдиқланган',
                  count(WholesaleSeller.statusApproved), AvaLight.ok),
              _summaryCard(
                  'Рад этилган', count(WholesaleSeller.statusRejected), Colors.red),
            ]),
          ),
          Expanded(
            child: all.isEmpty
                ? const Center(child: Text('Сотувчи топилмади'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                    itemCount: all.length,
                    itemBuilder: (_, i) => _sellerCard(all[i]),
                  ),
          ),
        ]);
      },
    );
  }

  Widget _sellerCard(WholesaleSeller s) {
    final color = _sellerStatusColor(s.approvalStatus);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _badge(_sellerStatusLabel(s.approvalStatus), color),
            if (s.sellerType.isNotEmpty) ...[
              const SizedBox(width: 8),
              _badge(WholesaleSeller.typeLabel(s.sellerType), Colors.blueGrey),
            ],
            const Spacer(),
            Text(_dateText(s.createdAt),
                style: const TextStyle(color: Colors.black45, fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          Text(
            s.companyName.isEmpty ? '(Ном йўқ)' : s.companyName,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          if (s.ownerName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(s.ownerName, style: const TextStyle(color: Colors.black54)),
          ],
          const SizedBox(height: 6),
          _meta(Icons.phone, s.phone),
          if (s.adminNote.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Admin: ${s.adminNote}',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                    fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ElevatedButton.icon(
              onPressed: s.isPending ? () => _approveSeller(s) : null,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Тасдиқлаш'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.button,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.tickerShell,
                disabledForegroundColor: AppColors.primaryDark,
              ),
            ),
            OutlinedButton.icon(
              onPressed: s.isPending ? () => _rejectSeller(s) : null,
              icon: const Icon(Icons.block, size: 18),
              label: const Text('Рад этиш'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ]),
        ]),
      ),
    );
  }

  // ─── Маҳсулотлар ──────────────────────────────────────────────────

  Future<void> _approveProduct(WholesaleProduct p) async {
    try {
      await _productsRepo.approve(p.id, adminId: _adminId);
      _showResult('Фаоллаштирилди: ${p.title}');
    } catch (e) {
      _showResult('Хатолик: $e', error: true);
    }
  }

  Future<void> _rejectProduct(WholesaleProduct p) async {
    final note = await _promptNote('«${p.title}»ни ёпиш/рад этиш');
    if (note == null || !mounted) return;
    try {
      await _productsRepo.reject(p.id, adminId: _adminId, note: note);
      _showResult('Ёпилди: ${p.title}');
    } catch (e) {
      _showResult('Хатолик: $e', error: true);
    }
  }

  Future<void> _deleteProduct(WholesaleProduct p) async {
    final ok = await _confirm(
        'Маҳсулотни ўчириш', '«${p.title}» бутунлай ўчирилади.');
    if (!ok) return;
    try {
      await _productsRepo.delete(p.id);
      _showResult('Ўчирилди: ${p.title}');
    } catch (e) {
      _showResult('Хатолик: $e', error: true);
    }
  }

  Widget _productsTab() {
    return StreamBuilder<List<WholesaleProduct>>(
      stream: _productsRepo.watchAllForAdmin(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Хатолик: ${snap.error}'));
        }
        final all = snap.data ?? const <WholesaleProduct>[];
        final filtered = _productStatusFilter == 'all'
            ? all
            : all.where((p) => p.status == _productStatusFilter).toList();
        int count(String s) => all.where((e) => e.status == s).length;
        return Column(children: [
          const _AutoApproveBar(
            settingsField: 'wholesaleProductAutoApprove',
            onLabel: 'АВТО тасдиқ: ЁҚИҚ — янги маҳсулотлар дарҳол фаол',
            offLabel:
                'ҚЎЛДА тасдиқ — янги маҳсулотлар «Кутилмоқда»га тушади',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Wrap(spacing: 10, runSpacing: 10, children: [
              _summaryCard('Жами', all.length, Colors.blueGrey),
              _summaryCard('Кутяпти', count(WholesaleProduct.statusPending),
                  Colors.orange),
              _summaryCard(
                  'Фаол', count(WholesaleProduct.statusActive), AvaLight.ok),
              _summaryCard('Ёпилган', count(WholesaleProduct.statusInactive),
                  Colors.blueGrey),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Wrap(spacing: 8, children: [
              for (final item in const [
                ('all', 'Барчаси'),
                (WholesaleProduct.statusPending, 'Кутяпти'),
                (WholesaleProduct.statusActive, 'Фаол'),
                (WholesaleProduct.statusInactive, 'Ёпилган'),
              ])
                ChoiceChip(
                  label: Text(item.$2),
                  selected: _productStatusFilter == item.$1,
                  onSelected: (_) =>
                      setState(() => _productStatusFilter = item.$1),
                ),
            ]),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('Маҳсулот топилмади'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _productCard(filtered[i]),
                  ),
          ),
        ]);
      },
    );
  }

  Widget _productCard(WholesaleProduct p) {
    final color = _productStatusColor(p.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _badge(_productStatusLabel(p.status), color),
            const Spacer(),
            Text(_dateText(p.createdAt),
                style: const TextStyle(color: Colors.black45, fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (p.imageUrls.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  p.imageUrls.first,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 56,
                    height: 56,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  p.title.isEmpty ? '(Ном йўқ)' : p.title,
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  p.priceTiers.length > 1
                      ? p.priceTiers.map((t) => t.label(p.unit)).join(' · ')
                      : 'Нарх: ${p.basePrice} · МОҚ: ${p.moq} ${p.unit}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          _meta(Icons.storefront, p.sellerCompanyName.isEmpty
              ? 'Сотувчи номаълум'
              : p.sellerCompanyName),
          if (p.adminNote.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Admin: ${p.adminNote}',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                    fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ElevatedButton.icon(
              onPressed: p.isPending ? () => _approveProduct(p) : null,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Фаоллаштириш'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.button,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.tickerShell,
                disabledForegroundColor: AppColors.primaryDark,
              ),
            ),
            OutlinedButton.icon(
              onPressed: p.isActive || p.isPending
                  ? () => _rejectProduct(p)
                  : null,
              icon: const Icon(Icons.block, size: 18),
              label: const Text('Ёпиш/Рад этиш'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
            OutlinedButton.icon(
              onPressed: () => _deleteProduct(p),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Ўчириш'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ]),
        ]),
      ),
    );
  }

  // ─── Умумий виджетлар ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _header(),
      Container(
        color: Colors.white,
        child: TabBar(
          controller: _tabCtrl,
          labelColor: _blue,
          indicatorColor: _blue,
          tabs: const [
            Tab(text: '🧾 Сотувчилар'),
            Tab(text: '📦 Маҳсулотлар'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          children: [_sellersTab(), _productsTab()],
        ),
      ),
    ]);
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.warehouse_outlined, color: _blue),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'УЛГУРЖИ БОЗОР — назорати',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 3),
              Text(
                'Сотувчиларни тасдиқлаш ва маҳсулот эълонларини модерация қилиш',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ]),
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
      child: Row(children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withValues(alpha: 0.1),
          child: Text('$value',
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style:
              TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: Colors.black45),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(color: Colors.black54)),
    ]);
  }
}

String _dateText(DateTime? d) {
  if (d == null) return '';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

Color _sellerStatusColor(String status) {
  switch (status) {
    case WholesaleSeller.statusPending:
      return Colors.orange;
    case WholesaleSeller.statusApproved:
      return AppColors.primary;
    case WholesaleSeller.statusRejected:
      return Colors.red;
    default:
      return Colors.blueGrey;
  }
}

String _sellerStatusLabel(String status) {
  switch (status) {
    case WholesaleSeller.statusPending:
      return 'Кутяпти';
    case WholesaleSeller.statusApproved:
      return 'Тасдиқланган';
    case WholesaleSeller.statusRejected:
      return 'Рад этилган';
    default:
      return status;
  }
}

Color _productStatusColor(String status) {
  switch (status) {
    case WholesaleProduct.statusPending:
      return Colors.orange;
    case WholesaleProduct.statusActive:
      return AppColors.primary;
    case WholesaleProduct.statusInactive:
      return Colors.blueGrey;
    default:
      return Colors.blueGrey;
  }
}

String _productStatusLabel(String status) {
  switch (status) {
    case WholesaleProduct.statusPending:
      return 'Кутяпти';
    case WholesaleProduct.statusActive:
      return 'Фаол';
    case WholesaleProduct.statusInactive:
      return 'Ёпилган';
    default:
      return status;
  }
}

/// `settings/app.{settingsField}` — ҚЎЛДА / АВТО тасдиқ (`JobsModerationScreen`
/// даги `_JobsAutoApproveBar` андозаси, лекин CF ўрнига тўғридан-тўғри ёзув —
/// `settings/{docId}` учун `isAdmin()` рухсати аллақачон мавжуд).
class _AutoApproveBar extends StatefulWidget {
  const _AutoApproveBar({
    required this.settingsField,
    required this.onLabel,
    required this.offLabel,
  });

  final String settingsField;
  final String onLabel;
  final String offLabel;

  @override
  State<_AutoApproveBar> createState() => _AutoApproveBarState();
}

class _AutoApproveBarState extends State<_AutoApproveBar> {
  bool _busy = false;

  Future<void> _setAuto(bool enabled) async {
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance.collection('settings').doc('app').set({
        widget.settingsField: enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
      stream:
          FirebaseFirestore.instance.collection('settings').doc('app').snapshots(),
      builder: (context, snap) {
        final auto = snap.data?.data()?[widget.settingsField] == true;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: auto ? AvaLight.okSoft : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: auto ? AvaLight.ok : Colors.orange.shade200,
            ),
          ),
          child: Row(children: [
            Icon(
              auto ? Icons.flash_on : Icons.admin_panel_settings,
              color: auto ? AvaLight.ok : Colors.orange.shade800,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                auto ? widget.onLabel : widget.offLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: auto ? AvaLight.ok : Colors.orange.shade900,
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
          ]),
        );
      },
    );
  }
}
