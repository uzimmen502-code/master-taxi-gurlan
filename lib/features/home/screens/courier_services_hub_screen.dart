import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../bread/screens/bread_screen.dart';
import '../../carpet_wash/screens/carpet_wash_screen.dart';
import '../../food/screens/food_screen.dart';

const _bg = Color(0xFFF6FAF2);
const _titleDark = Color(0xFF1A3A20);
const _brandGreen = Color(0xFF36A63A);
const _cardBorder = Color(0xFFE0E8E0);

/// Kuryer xizmati — Non / Taom / Gilam buyurtma yo‘riqnomasi.
class CourierServicesHubScreen extends StatelessWidget {
  const CourierServicesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(context.tr('courier_hub_title')),
        backgroundColor: _brandGreen,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            context.tr('courier_hub_subtitle'),
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          _ServiceCard(
            imagePath: 'assets/images/services/service_bread.png',
            title: context.tr('courier_hub_bread_title'),
            subtitle: context.tr('courier_hub_bread_subtitle'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BreadScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _ServiceCard(
            imagePath: 'assets/images/services/service_food.png',
            title: context.tr('courier_hub_food_title'),
            subtitle: context.tr('courier_hub_food_subtitle'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FoodScreen()),
            ),
          ),
          const SizedBox(height: 10),
          _ServiceCard(
            imagePath: 'assets/images/services/service_carpet_wash.png',
            title: context.tr('courier_hub_carpet_title'),
            subtitle: context.tr('courier_hub_carpet_subtitle'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CarpetWashScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.imagePath,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String imagePath;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _cardBorder),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  imagePath,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _titleDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade500),
            ],
          ),
        ),
      ),
    );
  }
}
