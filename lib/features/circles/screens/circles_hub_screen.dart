import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../relatives/widgets/tree_link_invite_indicator.dart';
import '../../relatives/screens/relatives_screen.dart';
import '../utils/circle_type_spec.dart';
import 'circles_list_screen.dart';

/// "Mening yaqinlarim" hubi. Faol: Sinfdosh/Kursdosh/Hamkasb + Qarindoshlar.
class CirclesHubScreen extends StatefulWidget {
  const CirclesHubScreen({super.key});

  static const _accent = Color(0xFF6A4C93);

  @override
  State<CirclesHubScreen> createState() => _CirclesHubScreenState();
}

class _CirclesHubScreenState extends State<CirclesHubScreen> {
  String? _userId;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    if (mounted) setState(() => _userId = uid.length >= 12 ? uid : null);
  }

  @override
  Widget build(BuildContext context) {
    final specs = [
      CircleTypeSpec.classmates,
      CircleTypeSpec.coursemates,
      CircleTypeSpec.colleagues,
    ];
    final uid = _userId;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F4F8),
      appBar: AppBar(
        title: const Text('Менинг яқинларим'),
        backgroundColor: CirclesHubScreen._accent,
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
              color: CirclesHubScreen._accent,
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
            color: CirclesHubScreen._accent,
            trailing: uid == null
                ? null
                : TreeLinkInviteCount(
                    userId: uid,
                    builder: (_, count) {
                      if (count <= 0) {
                        return const Icon(Icons.chevron_right, color: Colors.grey);
                      }
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF9800),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$count таклиф',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, color: Colors.grey),
                        ],
                      );
                    },
                  ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RelativesScreen()),
            ),
          ),
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
    this.trailing,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final Widget? trailing;

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
              trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
