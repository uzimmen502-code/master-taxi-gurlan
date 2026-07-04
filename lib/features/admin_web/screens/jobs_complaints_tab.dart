import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_ad.dart';
import '../../../models/job_complaint.dart';
import '../../../repositories/jobs_repository.dart';
import '../services/admin_auth_service.dart';
import '../services/admin_jobs_service.dart';
import '../widgets/jobs_ad_edit_dialog.dart';

/// Admin — ИШ ТОП shikoyatlari.
class JobsComplaintsTab extends StatefulWidget {
  const JobsComplaintsTab({super.key});

  @override
  State<JobsComplaintsTab> createState() => _JobsComplaintsTabState();
}

class _JobsComplaintsTabState extends State<JobsComplaintsTab> {
  bool _onlyOpen = true;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<JobsRepository>();
    return StreamBuilder<List<JobComplaint>>(
      stream: repo.watchComplaints(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Хатолик: ${snap.error}',
                  style: const TextStyle(color: Colors.red)),
            ),
          );
        }
        final all = snap.data ?? const <JobComplaint>[];
        final list = _onlyOpen
            ? all.where((c) => !c.resolved).toList(growable: false)
            : all;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
              child: Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('Ochiq (${all.where((c) => !c.resolved).length})'),
                    selected: _onlyOpen,
                    onSelected: (_) => setState(() => _onlyOpen = true),
                  ),
                  ChoiceChip(
                    label: Text('Barchasi (${all.length})'),
                    selected: !_onlyOpen,
                    onSelected: (_) => setState(() => _onlyOpen = false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(
                        _onlyOpen
                            ? 'Ochiq shikoyatlar yo\'q'
                            : 'Shikoyatlar yo\'q',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _ComplaintCard(
                        complaint: list[i],
                        repo: repo,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({
    required this.complaint,
    required this.repo,
  });

  final JobComplaint complaint;
  final JobsRepository repo;

  Future<void> _resolve(BuildContext context) async {
    final adminPhone =
        context.read<AdminAuthService>().phoneDigits ?? '';
    if (adminPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Admin telefon topilmadi'),
        ),
      );
      return;
    }
    try {
      await context.read<AdminJobsService>().resolveComplaint(
            adminPhone: adminPhone,
            complaintId: complaint.id,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shikoyat hal qilindi deb belgilandi')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Xatolik: $e')),
      );
    }
  }

  Future<void> _blockAd(BuildContext context, JobAd ad) async {
    final adminPhone =
        context.read<AdminAuthService>().phoneDigits ?? '';
    try {
      await context.read<AdminJobsService>().updateAdStatus(
            adminPhone: adminPhone,
            adId: ad.id,
            status: 'blocked',
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E\'lon bloklandi')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Xatolik: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = complaint.resolved;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: resolved ? Colors.grey.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                resolved ? Icons.check_circle : Icons.report,
                color: resolved ? Colors.green : Colors.orange,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  complaint.reason,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    decoration:
                        resolved ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (complaint.createdAt != null)
                Text(
                  _fmt(complaint.createdAt!),
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
            ]),
            if (resolved) ...[
              const SizedBox(height: 6),
              Text(
                'Hal qilindi: ${complaint.resolvedBy.isNotEmpty ? complaint.resolvedBy : "admin"}',
                style: TextStyle(fontSize: 12, color: Colors.green.shade700),
              ),
            ],
            if (complaint.reporterPhone.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Shikoyatchi: ${complaint.reporterPhone}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Text('E\'lon ID: ${complaint.adId}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 10),
            FutureBuilder<JobAd?>(
              future: repo.getAdById(complaint.adId),
              builder: (context, adSnap) {
                final ad = adSnap.data;
                if (adSnap.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }
                if (ad == null) {
                  return const Text('E\'lon o\'chirilgan yoki topilmadi',
                      style: TextStyle(color: Colors.red));
                }
                if (!JobAd.isJobsBoardType(ad.type)) {
                  return const Text(
                    'Bu Onlayn BOZOR e\'loni — Ish top moderatsiyasida emas',
                    style: TextStyle(color: Colors.orange),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ad.titleOrText,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${ad.authorName} • ${ad.authorPhone}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                        onPressed: () => showJobsAdEditDialog(
                          context: context,
                          ad: ad,
                          adminPhone: context
                                  .read<AdminAuthService>()
                                  .phoneDigits ??
                              '',
                        ),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Tahrirlash'),
                      ),
                      if (ad.status == 'active')
                        OutlinedButton.icon(
                          onPressed: () => _blockAd(context, ad),
                          icon: const Icon(Icons.block, size: 16),
                          label: const Text('Blok'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                        ),
                      if (!resolved)
                        ElevatedButton.icon(
                          onPressed: () => _resolve(context),
                          icon: const Icon(Icons.done, size: 16),
                          label: const Text('Hal qilindi'),
                        ),
                    ]),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d.$m $h:$min';
  }
}
