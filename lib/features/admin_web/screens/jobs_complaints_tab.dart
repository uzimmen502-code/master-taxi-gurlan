import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_ad.dart';
import '../../../models/job_complaint.dart';
import '../../../repositories/jobs_repository.dart';

/// Админ — ИШ ТОП шикоятлари.
class JobsComplaintsTab extends StatelessWidget {
  const JobsComplaintsTab({super.key});

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
        final list = snap.data ?? const <JobComplaint>[];
        if (list.isEmpty) {
          return const Center(child: Text('Шикоятлар йўқ'));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          itemCount: list.length,
          itemBuilder: (_, i) => _ComplaintCard(
            complaint: list[i],
            repo: repo,
          ),
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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.report, color: Colors.orange, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  complaint.reason,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (complaint.createdAt != null)
                Text(
                  _fmt(complaint.createdAt!),
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
            ]),
            if (complaint.reporterPhone.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Шикоятчи: ${complaint.reporterPhone}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            Text('Эълон ID: ${complaint.adId}',
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
                  return const Text('Эълон ўчирилган ёки топилмади',
                      style: TextStyle(color: Colors.red));
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
                    Wrap(spacing: 8, children: [
                      OutlinedButton.icon(
                        onPressed: () => _openAd(context, ad),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Эълон'),
                      ),
                      if (ad.status == 'active')
                        OutlinedButton.icon(
                          onPressed: () async {
                            await repo.updateAdStatus(
                              adId: ad.id,
                              status: 'blocked',
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Эълон блокланди'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.block, size: 16),
                          label: const Text('Блок'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
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

  void _openAd(BuildContext context, JobAd ad) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ad.titleOrText),
        content: SingleChildScrollView(
          child: Text(
            '${ad.text}\n\n'
            'Муаллиф: ${ad.authorName}\n'
            'Тел: ${ad.authorPhone}\n'
            'Статус: ${ad.status}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Ёпиш'),
          ),
        ],
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
