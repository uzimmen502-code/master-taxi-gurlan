import 'package:flutter/material.dart';

import '../../../models/driver_session.dart';
import '../../../core/theme/app_theme.dart';

/// Р®Т›РѕСЂРё: СЃР°Р»РѕРј + РёСЃРј + Р°РІС‚РѕРјРѕР±РёР»СЊ РјР°СЉР»СѓРјРѕС‚Р»Р°СЂРё + РїСЂРѕС„РёР» С‚СѓРіРјР°СЃРё.
class DriverHeroCard extends StatelessWidget {
  const DriverHeroCard({
    super.key,
    required this.session,
    required this.onProfileTap,
  });

  final DriverSession session;
  final VoidCallback onProfileTap;

  static const _green = AppColors.primaryDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppColors.primaryDark, AppColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: _green.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          child: Text(
            session.name.isNotEmpty ? session.name[0] : 'Р”',
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${session.greeting},',
                  style: const TextStyle(
                      fontSize: AppText.labelSmall, color: Colors.white70)),
              Text(session.honorificName,
                  style: const TextStyle(
                      fontSize: AppText.titleMedium,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              if (session.carModel.isNotEmpty)
                Text('рџљ— ${session.carModel} В· ${session.carPlate}',
                    style: const TextStyle(
                        fontSize: AppText.labelSmall,
                        color: Colors.white70)),
            ],
          ),
        ),
        GestureDetector(
          onTap: onProfileTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
        ),
      ]),
    );
  }
}
