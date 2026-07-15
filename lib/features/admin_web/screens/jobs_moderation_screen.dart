import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_jobs_service.dart';
import '../widgets/jobs_ad_edit_dialog.dart';
import 'jobs_complaints_tab.dart';
import '../../../core/theme/app_theme.dart';

enum _JobsTypeFilter { all, work, service, ad, urgent }

class JobsModerationScreen extends StatefulWidget {
  const JobsModerationScreen({super.key});

  @override
  State<JobsModerationScreen> createState() => _JobsModerationScreenState();
}

class _JobsModerationScreenState extends State<JobsModerationScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'all';
  _JobsTypeFilter _typeFilter = _JobsTypeFilter.all;
  String _query = '';
  late final TabController _tabCtrl;

  static const _blue = AppColors.primary;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteAd(JobAd ad) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Эълонни ўчириш'),
        content: Text('«${ad.titleOrText}» ноқайд ўчирилади.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ўчириш', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final adminPhone =
          context.read<AdminAuthService>().phoneDigits ?? '';
      await context.read<AdminJobsService>().deleteAd(
            adminPhone: adminPhone,
            adId: ad.id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Эълон ўчирилди')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
      );
    }
  }

  List<JobAd> _filter(List<JobAd> ads) {
    final q = _query.trim().toLowerCase();
    return ads.where((ad) {
      if (_statusFilter != 'all' && ad.status != _statusFilter) return false;
      if (!_matchesTypeFilter(ad)) return false;
      if (q.isEmpty) return true;
      return ad.title.toLowerCase().contains(q) ||
          ad.text.toLowerCase().contains(q) ||
          ad.authorName.toLowerCase().contains(q) ||
          ad.authorPhone.toLowerCase().contains(q) ||
          ad.address.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  Future<void> _setStatus(JobAd ad, String status) async {
    final adminPhone =
        context.read<AdminAuthService>().phoneDigits ?? '';
    try {
      await context.read<AdminJobsService>().updateAdStatus(
            adminPhone: adminPhone,
            adId: ad.id,
            status: status,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _statusColor(status),
          content: Text('${_statusLabel(status)}: ${ad.titleOrText}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
      );
    }
  }

  Future<void> _edit(JobAd ad) async {
    final adminPhone =
        context.read<AdminAuthService>().phoneDigits ?? '';
    await showJobsAdEditDialog(
      context: context,
      ad: ad,
      adminPhone: adminPhone,
    );
  }

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
            Tab(text: '📋 Эълонлар'),
            Tab(text: '⚠️ Шикоятлар'),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          children: [
            _adsTab(),
            const JobsComplaintsTab(),
          ],
        ),
      ),
    ]);
  }

  Widget _adsTab() {
    return StreamBuilder<List<JobAd>>(
          stream: context.read<JobsRepository>().watchAllForAdmin(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Хатолик: ${snap.error}'));
            }

            final all = snap.data ?? const <JobAd>[];
            final ads = _filter(all);
            return Column(children: [
              _summary(all),
              _filters(),
              Expanded(
                child: ads.isEmpty
                    ? const Center(child: Text('Эълон топилмади'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                        itemCount: ads.length,
                        itemBuilder: (_, i) => _adCard(ads[i]),
                      ),
              ),
            ]);
          },
        );
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
          child: const Icon(Icons.work_history, color: _blue),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Иш ва хизмат доскаси — назорати',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 3),
              Text(
                'Иш / Хизмат / Эълон матнларини тасдиқлаш, таҳрирлаш ва кузатиш',
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _summary(List<JobAd> ads) {
    int count(String status) => ads.where((a) => a.status == status).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _summaryCard('Жами', ads.length, Colors.blueGrey),
          _summaryCard('Кутяпти', count('pending'), Colors.orange),
          _summaryCard('Фаол', count('active'), Colors.green),
          _summaryCard('Ёпилган', count('completed'), Colors.blue),
          _summaryCard('Блок', count('blocked'), Colors.red),
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

  Widget _filters() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Матн, телефон, исм ёки манзил бўйича қидириш...',
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
        _statusChips(),
        const SizedBox(height: 10),
        _kindChips(),
      ]),
    );
  }

  Widget _statusChips() {
    final items = [
      ('all', 'Барчаси'),
      ('pending', 'Кутяпти'),
      ('active', 'Фаол'),
      ('completed', 'Ёпилган'),
      ('blocked', 'Блок'),
    ];
    return Wrap(
      spacing: 8,
      children: [
        for (final item in items)
          ChoiceChip(
            label: Text(item.$2),
            selected: _statusFilter == item.$1,
            onSelected: (_) => setState(() => _statusFilter = item.$1),
          ),
      ],
    );
  }

  bool _matchesTypeFilter(JobAd ad) {
    switch (_typeFilter) {
      case _JobsTypeFilter.all:
        return true;
      case _JobsTypeFilter.work:
        return ad.kind == AdKind.work;
      case _JobsTypeFilter.service:
        return ad.kind == AdKind.service;
      case _JobsTypeFilter.ad:
        return ad.kind == AdKind.ad;
      case _JobsTypeFilter.urgent:
        return ad.supportsUrgent && ad.isUrgent;
    }
  }

  Widget _kindChips() {
    const items = <(_JobsTypeFilter, String)>[
      (_JobsTypeFilter.all, 'Ҳамма тур'),
      (_JobsTypeFilter.work, '🔨 Иш бор'),
      (_JobsTypeFilter.service, '🛠️ Хизмат'),
      (_JobsTypeFilter.ad, '📢 Эълон'),
      (_JobsTypeFilter.urgent, '🚨 Шошилинч'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          ChoiceChip(
            label: Text(item.$2),
            selected: _typeFilter == item.$1,
            selectedColor: item.$1 == _JobsTypeFilter.urgent
                ? Colors.red.shade100
                : null,
            onSelected: (_) => setState(() => _typeFilter = item.$1),
          ),
      ],
    );
  }

  Widget _adCard(JobAd ad) {
    final color = _statusColor(ad.status);
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
            _badge('${ad.kind.emoji} ${ad.kind.label}', _kindColor(ad.kind)),
            const SizedBox(width: 8),
            _badge(_statusLabel(ad.status), color),
            if (ad.isUrgent) ...[
              const SizedBox(width: 8),
              _badge('Шошилинч', Colors.red),
            ],
            const Spacer(),
            Text(_dateText(ad.createdAt),
                style: const TextStyle(color: Colors.black45, fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          Text(
            ad.title.trim().isEmpty ? '(Сарлавҳа йўқ)' : ad.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(ad.text, style: const TextStyle(height: 1.35)),
          if (ad.priceText.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Нарх: ${ad.priceText}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 6),
          Text(
            'Муддат: ${ad.expiresLabel}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (ad.adminNote.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Admin: ${ad.adminNote}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade800,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (ad.moderatedBy.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Moderator: ${ad.moderatedBy}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _meta(Icons.person, ad.authorName.isEmpty ? 'Номсиз' : ad.authorName),
              _meta(Icons.phone, ad.authorPhone.isEmpty ? 'Телефон йўқ' : ad.authorPhone),
              _meta(Icons.location_on,
                  ad.address.isEmpty ? 'Манзил кўрсатилмаган' : ad.address),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ElevatedButton.icon(
              onPressed: ad.status == 'pending'
                  ? () => _setStatus(ad, 'active')
                  : null,
              icon: Icon(
                ad.status == 'active'
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
                size: 18,
              ),
              label: Text(
                ad.status == 'active' ? 'Тасдиқланган' : 'Тасдиқлаш',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.button,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.tickerShell,
                disabledForegroundColor: AppColors.primaryDark,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _edit(ad),
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Таҳрир'),
            ),
            OutlinedButton.icon(
              onPressed: () => _setStatus(ad, 'completed'),
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Ёпиш'),
            ),
            OutlinedButton.icon(
              onPressed: () => _setStatus(ad, 'blocked'),
              icon: const Icon(Icons.block, size: 18),
              label: const Text('Блок'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
            if (ad.status == 'blocked' || ad.status == 'completed')
              TextButton.icon(
                onPressed: () => _setStatus(ad, 'pending'),
                icon: const Icon(Icons.pending_actions, size: 18),
                label: const Text('Кутилмоқдага қайтариш'),
              ),
            OutlinedButton.icon(
              onPressed: () => _deleteAd(ad),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Ўчириш'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
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

Color _kindColor(AdKind kind) {
  switch (kind) {
    case AdKind.work:
      return const Color(0xFFD84315);
    case AdKind.service:
      return AppColors.primary;
    case AdKind.ad:
      return AppColors.primary;
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'pending':
      return Colors.orange;
    case 'active':
      return AppColors.primary;
    case 'completed':
      return Colors.blue;
    case 'blocked':
      return Colors.red;
    default:
      return Colors.blueGrey;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Кутилмоқда';
    case 'active':
      return 'Фаол';
    case 'completed':
      return 'Ёпилган';
    case 'blocked':
      return 'Блок';
    default:
      return status;
  }
}

String _dateText(DateTime? value) {
  if (value == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year} ${two(value.hour)}:${two(value.minute)}';
}
