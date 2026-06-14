import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/message_thread_group.dart';
import '../../../models/news_item.dart';

/// «Хабарлар» — битта мурожаат/тема тарихи.
class DialogNewsDetailScreen extends StatelessWidget {
  const DialogNewsDetailScreen({super.key, required this.group});

  final MessageThreadGroup group;

  static const _green = AppColors.primaryDark;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(group.title),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (group.subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                group.subtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
          ...group.messages.map(_messageTile),
        ],
      ),
    );
  }

  Widget _messageTile(NewsItem n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: _green, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    n.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
                Text(
                  _dateTime(n.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
            if (n.body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                n.body,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
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

  String _dateTime(DateTime t) {
    return '${t.day.toString().padLeft(2, '0')}.'
        '${t.month.toString().padLeft(2, '0')}.${t.year} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}
