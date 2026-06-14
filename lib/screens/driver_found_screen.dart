import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/utils/formatters.dart';

class DriverFoundScreen extends StatelessWidget {
  final Map<String, dynamic> driver;

  const DriverFoundScreen({
    super.key,
    required this.driver,
  });

  // Телефон қилиш
  Future<void> _callDriver(String phone) async {
    final url = Uri.parse('tel:${phoneForCall(phone)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Муваффақият белгиси
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green[50],
                    border: Border.all(
                      color: Colors.green,
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 55,
                    color: Colors.green,
                  ),
                ),

                const SizedBox(height: 24),

                // Сарлавҳа
                const Text(
                  '✅ ҲАЙДОВЧИ ТОПИЛДИ!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),

                const SizedBox(height: 24),

                // Ҳайдовчи карточкаси
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Автомобил
                      _buildInfoRow(
                        icon: Icons.local_taxi,
                        label: 'Автомобил',
                        value: driver['car'] ?? 'Номаълум',
                      ),
                      const Divider(height: 20),

                      // Исм
                      _buildInfoRow(
                        icon: Icons.person,
                        label: 'Ҳайдовчи',
                        value: driver['name'] ?? 'Номаълум',
                      ),
                      const Divider(height: 20),

                      // Рейтинг
                      _buildInfoRow(
                        icon: Icons.star,
                        label: 'Рейтинг',
                        value: '⭐ ${driver['rating'] ?? "0"}',
                      ),
                      const Divider(height: 20),

                      // Давлат рақами
                      _buildInfoRow(
                        icon: Icons.numbers,
                        label: 'Дав. рақами',
                        value: driver['plate'] ?? 'Номаълум',
                      ),
                      const Divider(height: 20),

                      // Масофа
                      _buildInfoRow(
                        icon: Icons.location_on,
                        label: 'Масофа',
                        value: '${driver['distance'] ?? "?"} км',
                      ),
                      const Divider(height: 20),

                      // Келиш вақти
                      _buildInfoRow(
                        icon: Icons.timer,
                        label: 'Келиш вақти',
                        value: '~${driver['time'] ?? "?"} дақ',
                      ),
                      const Divider(height: 20),

                      // Телефон
                      _buildInfoRow(
                        icon: Icons.phone,
                        label: 'Телефон',
                        value: driver['phone'] ?? 'Номаълум',
                        isPhone: true,
                      ),
                      const Divider(height: 20),

                      // Ҳолат
                      _buildInfoRow(
                        icon: Icons.info,
                        label: 'Ҳолат',
                        value: '✅ қабул қилди',
                        valueColor: Colors.green,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Изоҳ
                Text(
                  'Ҳайдовчи сиз билан боғланади',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[600],
                  ),
                ),

                const SizedBox(height: 24),

                // OK тугмаси
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      // Бош экранга қайтиш (барча устки экранларни ёпиш)
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Маълумот қатори
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool isPhone = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 22, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const Spacer(),
        if (isPhone)
          GestureDetector(
            onTap: () => _callDriver(value),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.call,
                  size: 18,
                  color: Colors.blue,
                ),
              ],
            ),
          )
        else
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Colors.black87,
            ),
          ),
      ],
    );
  }
}