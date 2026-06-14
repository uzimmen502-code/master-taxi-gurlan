import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../jobs/jobs_tabs.dart';
import '../../jobs/screens/jobs_screen.dart';
import '../widgets/sell_offer_form.dart';
import '../../../core/theme/app_theme.dart';

/// Бирлашган «Сотаман» — профил «Сотиш» ва Иш топ билан бир xil forma.
class SellOfferScreen extends StatelessWidget {
  const SellOfferScreen({
    super.key,
    required this.phone,
    this.defaultToPlatform = true,
    this.defaultToPublic = false,
  });

  final String phone;
  final bool defaultToPlatform;
  final bool defaultToPublic;

  static const _green = AppColors.primaryDark;
  static const _brown = AppColors.primarySoft;

  @override
  Widget build(BuildContext context) {
    final uid = phoneDigits(phone);
    final phoneOk = uid.length >= 9;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: const Text(
          'Сотаман',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (!phoneOk)
            _warnCard(
              'Телефон рақамингиз тўлиқ киритилмаган. Профилда телефонни '
              'тўғрилаганингиздан кейин таклиф юбориш мумкин.',
            ),
          SellOfferForm(
            phone: phone,
            phoneOk: phoneOk,
            defaultToPlatform: defaultToPlatform,
            defaultToPublic: defaultToPublic,
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: phoneOk
                ? () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const JobsScreen(initialTabIndex: JobsTabs.ad),
                      ),
                    );
                  }
                : null,
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Бошқалар таклифларини кўриш (Иш топ)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _brown,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          _sectionTitle('Қаерда ҳисоб-китоб қилинади?'),
          _bodyCard(
            icon: Icons.storefront_outlined,
            color: _brown,
            child: const Text(
              'Платформага таклиф юборсангиз — қабул пунктида вазн бўйича '
              'қабул қилинади, сумма кошелёкка ёзилади.\n\n'
              '«Сотаман» эълони — бошқа фойдаланувчилар ўзлари боғланади.',
              style: TextStyle(fontSize: 14, height: 1.45),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle('Алоқа'),
          _bodyCard(
            icon: Icons.chat_bubble_outline,
            color: _green,
            child: Text(
              phoneOk
                  ? 'Телефон: ${phone.trim()}\n\n'
                      '«Админ билан чат» ёки қўнғироқ орқали малумот олинг.'
                  : 'Аввал профилда телефон ва манзилни тўлдиринг.',
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        t,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }

  Widget _warnCard(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.orange.shade800, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: Colors.orange.shade900)),
          ),
        ],
      ),
    );
  }

  Widget _bodyCard({
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }
}
