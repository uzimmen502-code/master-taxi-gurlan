import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/news_item.dart';
import '../../../repositories/news_repository.dart';
import '../../../repositories/user_repository.dart';

/// Админ томонидан юбориладиган янгилик/хабарлар экрани.
///
/// Бу — фойдаланувчи кўрадиган "ўқиш" экрани.
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  static const _green = Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _markRead();
  }

  Future<void> _markRead() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final uid = phoneDigits(phone);
    if (uid.length < 9) return;
    try {
      await context.read<UserRepository>().markNewsRead(uid);
    } catch (_) {}
  }

  Future<List<String>> _audiences() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? 'user';
    return ['all', role];
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<NewsRepository>();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text('🔔 Янгилик ва хабарлар'),
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<String>>(
        future: _audiences(),
        builder: (ctx, audSnap) {
          final aud = audSnap.data ?? const ['all', 'user'];
          return StreamBuilder<List<NewsItem>>(
            stream: repo.watchAll(audiences: aud, limit: 50),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Хатолик: ${snap.error}',
                        style: const TextStyle(color: Colors.red)),
                  ),
                );
              }
              final items = snap.data ?? const <NewsItem>[];
              if (items.isEmpty) {
                return _emptyState();
              }
              // Priority + createdAt бўйича.
              final sorted = [...items]
                ..sort((a, b) {
                  if (a.priority != b.priority) {
                    return b.priority.compareTo(a.priority);
                  }
                  return b.createdAt.compareTo(a.createdAt);
                });
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _newsCard(sorted[i]),
              );
            },
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.campaign_outlined, color: Colors.grey.shade400, size: 38),
            ),
            const SizedBox(height: 16),
            Text('Янги хабар йўқ',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            Text('Янги хабарлар келганда шу йерда кўрасиз',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  Widget _newsCard(NewsItem n) {
    final accent = _accentFor(n.category);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_iconFor(n.category), size: 12, color: accent),
              const SizedBox(width: 4),
              Text(_labelFor(n.category),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accent)),
            ]),
          ),
          const Spacer(),
          Text(_ago(n.createdAt),
              style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ]),
        const SizedBox(height: 10),
        Text(n.title,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, height: 1.3)),
        const SizedBox(height: 6),
        Text(n.body, style: const TextStyle(fontSize: 13, height: 1.4)),
        if (n.ctaLabel.isNotEmpty && n.ctaUrl.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _openUrl(n.ctaUrl),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(n.ctaLabel),
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ]),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Color _accentFor(String cat) {
    switch (cat) {
      case 'emergency':
        return Colors.red.shade700;
      case 'warning':
        return Colors.orange.shade700;
      case 'promo':
        return Colors.purple.shade700;
      case 'update':
        return Colors.blue.shade700;
      default:
        return _green;
    }
  }

  IconData _iconFor(String cat) {
    switch (cat) {
      case 'emergency':
        return Icons.report;
      case 'warning':
        return Icons.warning_amber;
      case 'promo':
        return Icons.local_offer;
      case 'update':
        return Icons.system_update_alt;
      default:
        return Icons.info;
    }
  }

  String _labelFor(String cat) {
    switch (cat) {
      case 'emergency':
        return 'ШОШИЛИНЧ';
      case 'warning':
        return 'Огоҳлантириш';
      case 'promo':
        return 'Акция';
      case 'update':
        return 'Янгилaниш';
      default:
        return 'Маълумот';
    }
  }

  String _ago(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'ҳозиргина';
    if (diff.inMinutes < 60) return '${diff.inMinutes} дақ. олдин';
    if (diff.inHours < 24) return '${diff.inHours} соат олдин';
    if (diff.inDays < 7) return '${diff.inDays} кун олдин';
    return '${t.day}.${t.month.toString().padLeft(2, '0')}.${t.year}';
  }
}
