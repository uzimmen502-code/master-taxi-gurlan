import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';

/// Сут, тухум, гуруч топшириш → кошелёк кредити ва уни қаерда сарфлаш тўғрисида.
///
/// Ҳисоб-китобни **мижоз ўзи иловада киритмайди** — қабул пунктида оператор
/// админ воситаси билан балансга ёзади; бу ерда жараён ва имкониятлар тушунтирилади.
class WalletPartnerProgramScreen extends StatelessWidget {
  const WalletPartnerProgramScreen({super.key, required this.phone});

  final String phone;

  static const _green = Color(0xFF2E7D32);
  static const _brown = Color(0xFF6D4C41);

  @override
  Widget build(BuildContext context) {
    final uid = phoneDigits(phone);
    final phoneOk = uid.length >= 9;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text(
          'Кошелёк ва маҳсулот топшириш',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (!phoneOk)
            _warnCard(
              'Телефон рақамингиз тўлиқ киритилмаган. Профилда телефонни '
              'тўғрилаганингиздан кейин кошелёк ва дафтар ишлайди.',
            ),
          _sectionTitle('Қаерда ҳисоб-китоб қилинади?'),
          _bodyCard(
            icon: Icons.storefront_outlined,
            color: _brown,
            child: const Text(
              'Сут, тухум, гуруч ёки бошқа маҳсулотни қабул пунктида '
              '(оператор ёки админ) вазн ва миқдор бўйича қабул қилади.\n\n'
              'Қабул қилинган сумма сизнинг профилдаги кошелёк балансига '
              'ёзилади. «Охирги операциялар»да бу «Сут/кредит» деб кўринади.\n\n'
              'Иловада алоҳида «сут топшириш» формаси ҳозирча йўқ — '
              'миқдорни админ ёки оператор тасдиқлайди; савол бўлса '
              'профилдаги «Админ билан чат» орқали ёзинг.',
              style: TextStyle(fontSize: 14, height: 1.45),
            ),
          ),
          const SizedBox(height: 18),
          _sectionTitle('Кошелёк пули қаерда ишлайди?'),
          _bullet(
            icon: Icons.restaurant,
            title: 'Тайёр овқат',
            text:
                'Овқат бўлимида буюртма берганда балансдан қисми '
                'автоматик ажратилади (буюртма жамигача).',
          ),
          _bullet(
            icon: Icons.bakery_dining,
            title: 'Нон ва қўшимчалар',
            text:
                'Нон буюртмаси саватида нақд ва кошелёк қанча ишлатилиши '
                'кўрсатилади; кам қолган сумма кошелёкдан аниқ ечилади.',
          ),
          _bullet(
            icon: Icons.local_taxi,
            title: 'Такси',
            text:
                'Сафарда нақддан ортиқ тўласангиз, қайтим кошелёкка тушади; '
                'кейин овқат ёки нонда қайта ишлатишингиз мумкин.',
          ),
          const SizedBox(height: 18),
          _sectionTitle('Алоқа'),
          _bodyCard(
            icon: Icons.chat_bubble_outline,
            color: _green,
            child: Text(
              phoneOk
                  ? 'Телефон: ${phone.trim()}\n\n'
                      'Топшириш жадвали ва нархлар бўйича — '
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
          color: Color(0xFF1B5E20),
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
          Icon(Icons.info_outline, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
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
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _bullet({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _green, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
