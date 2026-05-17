import 'package:flutter/material.dart';

import '../../../../models/intercity_ride.dart';
import 'seat_pulse.dart';

/// Шаҳарлараро такси reys карточкаси — қаер_белгиси + ҳайдовчи маълумоти,
/// нархи, бўш ўринлар pulse-badge ва "БРОН" тугмаси.
class IntercityRideCard extends StatelessWidget {
  const IntercityRideCard({
    super.key,
    required this.ride,
    required this.number,
    required this.primaryColor,
    required this.lightColor,
    required this.redColor,
    required this.greenColor,
    required this.goldColor,
    required this.textColor,
    required this.onCall,
    required this.onBook,
  });

  final IntercityRide ride;
  final int number;
  final Color primaryColor;
  final Color lightColor;
  final Color redColor;
  final Color greenColor;
  final Color goldColor;
  final Color textColor;
  final VoidCallback onCall;
  final VoidCallback onBook;

  Color _seatsColor() {
    if (ride.availableSeats == 1) return redColor;
    if (ride.availableSeats <= 3) return Colors.orange;
    return greenColor;
  }

  String _formatPrice(int p) {
    final s = p.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    const mandarin = Color(0xFFE65100);
    final seatsColor = _seatsColor();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Stack(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: lightColor,
                child: Text(
                    ride.driverName.isNotEmpty
                        ? ride.driverName.substring(0, 1)
                        : '?',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: primaryColor)),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                      color: primaryColor, shape: BoxShape.circle),
                  child: Center(
                      child: Text('$number',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 7,
                              fontWeight: FontWeight.bold))),
                ),
              ),
            ]),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ride.driverName,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: textColor)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(Icons.star, color: goldColor, size: 13),
                      const SizedBox(width: 2),
                      Text('${ride.rating}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: goldColor)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(5)),
                        child: Text(ride.carNumber,
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600)),
                      ),
                    ]),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_formatPrice(ride.price),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: mandarin)),
              const Text('сўм',
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
            ]),
          ]),
          const SizedBox(height: 8),
          Divider(height: 1, color: Colors.grey.shade100),
          const SizedBox(height: 8),
          Row(children: [
            Flexible(
              child: Text(
                  ride.carNumber.isNotEmpty
                      ? ride.carNumber.split(' ').first
                      : '',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            Text('·',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onCall,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: lightColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.call, size: 15, color: primaryColor),
              ),
            ),
            const Spacer(),
            SeatPulse(seats: ride.availableSeats, color: seatsColor),
            const SizedBox(width: 8),
            SizedBox(
              height: 30,
              child: ElevatedButton(
                onPressed: onBook,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
                child: const Text('БРОН'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
