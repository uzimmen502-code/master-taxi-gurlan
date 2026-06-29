import 'package:flutter/material.dart';

import 'class_circles_screen.dart';

/// "Mening yaqinlarim" hubi. MVP — faqat Sinfdoshlar faol; qolganlari "tez orada".
class CirclesHubScreen extends StatelessWidget {
  const CirclesHubScreen({super.key});

  static const _accent = Color(0xFF6A4C93);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      appBar: AppBar(
        title: const Text('Менинг яқинларим'),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CircleCard(
            emoji: '🎓',
            title: 'Синфдошларим',
            subtitle: 'Мактаб + битирган йил бўйича давра',
            color: _accent,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ClassCirclesScreen()),
            ),
          ),
          const SizedBox(height: 16),
          const _SoonHeader(),
          const SizedBox(height: 8),
          const _SoonCard(emoji: '👨‍👩‍👧', title: 'Қариндошларим'),
          const _SoonCard(emoji: '🎓', title: 'Курсдошларим'),
          const _SoonCard(emoji: '💼', title: 'Ҳамкасбларим'),
          const _SoonCard(emoji: '❤️', title: 'Танишув ва мулоқот'),
        ],
      ),
    );
  }
}

class _CircleCard extends StatelessWidget {
  const _CircleCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12.5, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoonHeader extends StatelessWidget {
  const _SoonHeader();

  @override
  Widget build(BuildContext context) {
    return Text('Тез орада',
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade500));
  }
}

class _SoonCard extends StatelessWidget {
  const _SoonCard({required this.emoji, required this.title});

  final String emoji;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: Card(
        elevation: 0,
        color: Colors.grey.shade100,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          leading: Text(emoji, style: const TextStyle(fontSize: 22)),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: const Icon(Icons.lock_clock, size: 18, color: Colors.grey),
        ),
      ),
    );
  }
}
