import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/news_item.dart';
import 'inbox_time.dart';

/// Умумий янгиликнинг тўлиқ матни. Аввал янгилик рўйхатда бутун матни билан
/// катта карта эди ва босилмасди; энди рўйхатда бир қатор, тўлиғи шу ерда.
class NewsDetailScreen extends StatelessWidget {
  const NewsDetailScreen({super.key, required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final n = item;
    final now = DateTime.now();
    final day = inboxDayLabel(n.createdAt,
        now: now, today: context.tr('inbox_today'), yesterday: context.tr('inbox_yesterday'));
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('inbox_filter_news')),
        backgroundColor: c.surface,
        foregroundColor: c.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AvaSpace.screen),
        children: [
          Text('$day, ${inboxClock(n.createdAt)}', style: AvaText.caption.copyWith(color: c.ink3)),
          const SizedBox(height: 6),
          if (n.title.trim().isNotEmpty)
            Text(n.title.trim(), style: AvaText.sectionTitle.copyWith(color: c.ink, fontSize: 18)),
          if (n.imageUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AvaRadius.card),
              child: Image.network(n.imageUrl,
                  fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          ],
          if (n.body.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            SelectableText(n.body.trim(), style: AvaText.body.copyWith(color: c.inkRow, height: 1.45)),
          ],
          if (n.ctaLabel.isNotEmpty && n.ctaUrl.isNotEmpty) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _open(n.ctaUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(n.ctaLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
