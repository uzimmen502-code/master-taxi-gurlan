import 'package:flutter/material.dart';

import '../../relatives/screens/relatives_screen.dart';
import '../utils/circle_type_spec.dart';
import 'circles_list_screen.dart';

/// "Mening yaqinlarim" hubi. Faol: Sinfdosh/Kursdosh/Hamkasb (umumiy dvigatel).
/// Qarindosh + Tanishuv — alohida modul (tez orada).
class CirclesHubScreen extends StatelessWidget {
  const CirclesHubScreen({super.key});

  static const _accent = Color(0xFF6A4C93);

  @override
  Widget build(BuildContext context) {
    final specs = [
      CircleTypeSpec.classmates,
      CircleTypeSpec.coursemates,
      CircleTypeSpec.colleagues,
    ];
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
          for (final spec in specs) ...[
            _CircleCard(
              emoji: spec.emoji,
              title: spec.title,
              subtitle: spec.subtitle,
              color: _accent,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CirclesListScreen(spec: spec),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _CircleCard(
            emoji: '👨‍👩‍👧',
            title: 'Қариндошларим',
            subtitle: 'Шахсий рўйхат + туғилган кун эслатмаси',
            color: _accent,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RelativesScreen()),
            ),
          ),
          const SizedBox(height: 18),
          const _SoonHeader(),
          const SizedBox(height: 8),
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
