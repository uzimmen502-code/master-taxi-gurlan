import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_ad.dart';
import '../../../repositories/jobs_repository.dart';

class JobsModerationScreen extends StatefulWidget {
  const JobsModerationScreen({super.key});

  @override
  State<JobsModerationScreen> createState() => _JobsModerationScreenState();
}

class _JobsModerationScreenState extends State<JobsModerationScreen> {
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'all';
  AdKind? _kindFilter;
  String _query = '';

  static const _blue = Color(0xFF0D47A1);

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<JobAd> _filter(List<JobAd> ads) {
    final q = _query.trim().toLowerCase();
    return ads.where((ad) {
      if (_statusFilter != 'all' && ad.status != _statusFilter) return false;
      if (_kindFilter != null && ad.kind != _kindFilter) return false;
      if (q.isEmpty) return true;
      return ad.title.toLowerCase().contains(q) ||
          ad.text.toLowerCase().contains(q) ||
          ad.authorName.toLowerCase().contains(q) ||
          ad.authorPhone.toLowerCase().contains(q) ||
          ad.address.toLowerCase().contains(q);
    }).toList(growable: false);
  }

  Future<void> _setStatus(JobAd ad, String status) async {
    final repo = context.read<JobsRepository>();
    try {
      await repo.updateAdStatus(adId: ad.id, status: status);
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
    await showDialog<void>(
      context: context,
      builder: (_) => _JobAdEditDialog(ad: ad),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _header(),
      Expanded(
        child: StreamBuilder<List<JobAd>>(
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
          child: const Icon(Icons.work_history, color: _blue),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Иш топ назорати',
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
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _statusChips()),
          const SizedBox(width: 12),
          Expanded(child: _kindChips()),
        ]),
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

  Widget _kindChips() {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Ҳамма тур'),
          selected: _kindFilter == null,
          onSelected: (_) => setState(() => _kindFilter = null),
        ),
        for (final kind in AdKind.values)
          ChoiceChip(
            label: Text('${kind.emoji} ${kind.label}'),
            selected: _kindFilter == kind,
            onSelected: (_) => setState(() => _kindFilter = kind),
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
              onPressed: () => _setStatus(ad, 'active'),
              icon: const Icon(Icons.check_circle, size: 18),
              label: const Text('Тасдиқлаш'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
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

class _JobAdEditDialog extends StatefulWidget {
  const _JobAdEditDialog({required this.ad});

  final JobAd ad;

  @override
  State<_JobAdEditDialog> createState() => _JobAdEditDialogState();
}

class _JobAdEditDialogState extends State<_JobAdEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _text;
  late final TextEditingController _price;
  late AdKind _kind;
  late String _status;
  late bool _urgent;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.ad.title);
    _text = TextEditingController(text: widget.ad.text);
    _price = TextEditingController(text: widget.ad.priceText);
    _kind = widget.ad.kind;
    _status = widget.ad.status;
    _urgent = widget.ad.isUrgent;
  }

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_text.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Асосий матн бўш бўла олмайди'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<JobsRepository>().updateAd(
            adId: widget.ad.id,
            text: _text.text.trim(),
            isUrgent: _urgent,
            type: _kind.key,
            status: _status,
            title: _title.text.trim(),
            priceText: _price.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text('Эълон янгиланди'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Эълонни таҳрирлаш'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, minWidth: 360),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<AdKind>(
              value: _kind,
              decoration: const InputDecoration(labelText: 'Тури'),
              items: [
                for (final kind in AdKind.values)
                  DropdownMenuItem(
                    value: kind,
                    child: Text('${kind.emoji} ${kind.label}'),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _kind = v);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Сарлавҳа',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _text,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Асосий матн',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _price,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Нарх / шартнома',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'Статус'),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Кутилмоқда')),
                DropdownMenuItem(value: 'active', child: Text('Фаол')),
                DropdownMenuItem(value: 'completed', child: Text('Ёпилган')),
                DropdownMenuItem(value: 'blocked', child: Text('Блок')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _status = v);
              },
            ),
            if (_kind == AdKind.work)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Шошилинч'),
                value: _urgent,
                onChanged: (v) => setState(() => _urgent = v),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Бекор'),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text('Сақлаш'),
        ),
      ],
    );
  }
}

extension _JobAdAdminText on JobAd {
  String get titleOrText => title.trim().isEmpty ? text : title;
}

Color _kindColor(AdKind kind) {
  switch (kind) {
    case AdKind.work:
      return const Color(0xFFD84315);
    case AdKind.service:
      return const Color(0xFF6A1B9A);
    case AdKind.ad:
      return const Color(0xFF0277BD);
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'pending':
      return Colors.orange;
    case 'active':
      return Colors.green;
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
