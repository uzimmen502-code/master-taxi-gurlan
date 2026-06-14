import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/news_item.dart';
import '../../../repositories/news_repository.dart';

/// Умумий админ янгиликлари (буюртма хабарларисиз).
class GeneralNewsTab extends StatefulWidget {
  const GeneralNewsTab({super.key});

  @override
  State<GeneralNewsTab> createState() => _GeneralNewsTabState();
}

class _GeneralNewsTabState extends State<GeneralNewsTab> {
  static const _green = AppColors.primaryDark;

  Future<({List<String> audiences, String userId})> _userContext() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? 'user';
    final phone = prefs.getString('user_phone') ?? '';
    return (audiences: ['all', role], userId: phoneDigits(phone));
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<NewsRepository>();
    return FutureBuilder<({List<String> audiences, String userId})>(
      future: _userContext(),
      builder: (ctx, audSnap) {
        final aud = audSnap.data?.audiences ?? const ['all', 'user'];
        final uid = audSnap.data?.userId ?? '';
        return StreamBuilder<List<NewsItem>>(
          stream: repo.watchBroadcastNews(audiences: aud, userId: uid, limit: 50),
          builder: (ctx, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Text('Хатолик: ${snap.error}',
                    style: const TextStyle(color: Colors.red)),
              );
            }
            final items = snap.data ?? const <NewsItem>[];
            if (items.isEmpty) return _emptyState();
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
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.campaign_outlined, color: Colors.grey.shade400, size: 48),
          const SizedBox(height: 12),
          Text('Янги хабар йўқ',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700)),
        ],
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
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_labelFor(n.category),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accent)),
            ),
            const Spacer(),
            Text(_ago(n.createdAt),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
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
            ),
          ],
        ],
      ),
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
    if (diff.inMinutes < 60) return '${diff.inMinutes} дақ.';
    if (diff.inHours < 24) return '${diff.inHours} соат';
    return '${t.day}.${t.month.toString().padLeft(2, '0')}.${t.year}';
  }
}
