import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'tracking_map_screen.dart';

class SearchingScreen extends StatefulWidget {
  final String from;
  final String to;
  final String taxiType;

  const SearchingScreen({
    super.key,
    required this.from,
    required this.to,
    required this.taxiType,
  });

  @override
  State<SearchingScreen> createState() => _SearchingScreenState();
}

class _SearchingScreenState extends State<SearchingScreen>
    with SingleTickerProviderStateMixin {
  // Таймер
  Timer? _searchTimer;
  int _secondsElapsed = 0;

  // Босқич
  int _currentStage = 1;
  int _currentRadius = 2;

  // Ҳайдовчилар рўйхати
  List<Map<String, dynamic>> _drivers = [];
  final Set<String> _rejectedDriverIds = {};

  // Сохта ҳайдовчилар базаси (Firestore ишламаса)
  final List<Map<String, dynamic>> _allDrivers = [
    {
      'id': '1', 'name': 'Аҳмад', 'rating': 4.8, 'distance': 0.5,
      'seats': 2, 'parcel': true, 'plate': '01A123AA',
      'phone': '+998 90 123 45 67', 'price': 50000,
    },
    {
      'id': '2', 'name': 'Сардор', 'rating': 4.5, 'distance': 1.2,
      'seats': 1, 'parcel': false, 'plate': '01B456BB',
      'phone': '+998 93 987 65 43', 'price': 40000,
    },
    {
      'id': '3', 'name': 'Жамшид', 'rating': 4.2, 'distance': 1.8,
      'seats': 3, 'parcel': true, 'plate': '01C789CC',
      'phone': '+998 97 555 44 33', 'price': 35000,
    },
    {
      'id': '4', 'name': 'Бобур', 'rating': 4.0, 'distance': 2.0,
      'seats': 4, 'parcel': false, 'plate': '01D012DD',
      'phone': '+998 88 111 22 33', 'price': 30000,
    },
    {
      'id': '5', 'name': 'Достон', 'rating': 4.6, 'distance': 3.2,
      'seats': 2, 'parcel': true, 'plate': '01E345EE',
      'phone': '+998 91 444 55 66', 'price': 45000,
    },
    {
      'id': '6', 'name': 'Шерзод', 'rating': 4.3, 'distance': 4.5,
      'seats': 1, 'parcel': false, 'plate': '01F678FF',
      'phone': '+998 99 777 88 99', 'price': 38000,
    },
    {
      'id': '7', 'name': 'Темур', 'rating': 4.9, 'distance': 5.8,
      'seats': 3, 'parcel': true, 'plate': '01G901GG',
      'phone': '+998 94 333 22 11', 'price': 55000,
    },
    {
      'id': '8', 'name': 'Отабек', 'rating': 4.1, 'distance': 6.5,
      'seats': 4, 'parcel': false, 'plate': '01H234HH',
      'phone': '+998 95 666 77 88', 'price': 32000,
    },
  ];

  bool _isSearching = true;
  String? _acceptedDriverId;

  // Пулсация контроллерлари
  final Map<String, AnimationController> _pulseControllers = {};

  @override
  void initState() {
    super.initState();
    _startSearch();
  }

  void _startSearch() {
    _loadDriversForRadius(2);



    _searchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _secondsElapsed++;
      });

      if (_secondsElapsed == 25 && _currentStage == 1) {
        _moveToStage2();
      }

      if (_secondsElapsed == 50 && _currentStage == 2) {
        _moveToStage3();
      }

      if (_acceptedDriverId != null) {
        timer.cancel();
      }
    });
  }

  void _loadDriversForRadius(int radiusKm) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('drivers')
          .where('isActive', isEqualTo: true)
          .get();

      final allDrivers = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      final maxDistance = radiusKm.toDouble();
      final filtered = allDrivers
          .where((d) =>
      (d['distance'] ?? 99) <= maxDistance &&
          !_rejectedDriverIds.contains(d['id']))
          .toList();

      filtered.sort((a, b) => (a['distance'] ?? 99).compareTo(b['distance'] ?? 99));

      if (!mounted) return;
      setState(() {
        _drivers = filtered;
        _currentRadius = radiusKm;
      });

      for (var driver in filtered) {
        _createPulseController(driver['id'], driver['seats'] ?? 4);
      }
    } catch (e) {
      // Firestore ишламаса, сохта маълумотлар
      final maxDistance = radiusKm.toDouble();
      final filtered = _allDrivers
          .where((d) =>
      d['distance'] <= maxDistance &&
          !_rejectedDriverIds.contains(d['id']))
          .toList();

      if (!mounted) return;
      setState(() {
        _drivers = filtered;
        _currentRadius = radiusKm;
      });

      for (var driver in filtered) {
        _createPulseController(driver['id'], driver['seats'] ?? 4);
      }
    }
  }

  void _createPulseController(String driverId, int seats) {
    if (_pulseControllers.containsKey(driverId)) return;

    final speed = _getPulseSpeed(seats);
    if (speed == null) return;

    final controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: speed),
    );

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.reverse();
      } else if (status == AnimationStatus.dismissed) {
        controller.forward();
      }
    });

    controller.forward();
    _pulseControllers[driverId] = controller;
  }

  int? _getPulseSpeed(int seats) {
    switch (seats) {
      case 1: return 300;
      case 2: return 600;
      case 3: return 900;
      default: return null;
    }
  }

  void _moveToStage2() {
    setState(() => _currentStage = 2);
    _loadDriversForRadius(5);
  }

  void _moveToStage3() {
    setState(() => _currentStage = 3);
    _loadDriversForRadius(7);
  }

  void _onDriverAccept(String driverId) {
    setState(() {
      _acceptedDriverId = driverId;
      _isSearching = false;
    });
    _searchTimer?.cancel();

    final driver = _drivers.firstWhere((d) => d['id'] == driverId);

    if (widget.taxiType == 'marshrut') {
      // МАРШРУТ ТАКСИ — диалог
      _showBookingDialog(driver);
    } else {
      // АЛОҲИДА МАШИНА — харита
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => TrackingMapScreen(
            driver: driver,
            from: widget.from,
          ),
        ),
      );
    }
  }

  void _showBookingDialog(Map<String, dynamic> driver) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('✅ БРОН ҚАБУЛ ҚИЛИНДИ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Ҳайдовчи: ${driver['name']}'),
              Text('Телефон: ${driver['phone']}'),
              Text('Йўлкира: ${driver['price']} сўм'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _onBookSeat(Map<String, dynamic> driver) {
    _onDriverAccept(driver['id']);
  }

  void _cancelSearch() {
    _searchTimer?.cancel();
    for (var c in _pulseControllers.values) {
      c.dispose();
    }
    Navigator.pop(context);
  }

  String _formatTime(int seconds) {
    final min = (seconds ~/ 60).toString().padLeft(2, '0');
    final sec = (seconds % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    for (var c in _pulseControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _cancelSearch,
        ),
        title: const Text('Қидирилмоқда...'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ============ ЮҚОРИ ПАНЕЛЬ ============
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.green, size: 16),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.from.isNotEmpty ? widget.from : 'GPS',
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (widget.to.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.flag, color: Colors.red, size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          widget.to,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildInfoChip(Icons.wifi_tethering, 'Радиус: $_currentRadius км', Colors.blue),
                    _buildInfoChip(Icons.timer, _formatTime(_secondsElapsed), Colors.orange),
                    _buildInfoChip(Icons.person, 'Топилган: ${_drivers.length} та', Colors.green),
                  ],
                ),
              ],
            ),
          ),

          // ============ ҲАЙДОВЧИЛАР РЎЙХАТИ ============
          Expanded(
            child: _drivers.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 60, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text('Ҳайдовчилар топилмади', style: TextStyle(fontSize: 15, color: Colors.grey[500])),
                  const SizedBox(height: 6),
                  Text('Радиус кенгайтирилмоқда...', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _drivers.length,
              itemBuilder: (context, index) {
                final driver = _drivers[index];
                return _buildDriverCard(driver, index + 1);
              },
            ),
          ),

          // ============ БЕКОР ҚИЛИШ ============
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _cancelSearch,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('БЕКОР ҚИЛИШ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============ 2 ҚАТОРЛИ КАРТОЧКА ============
  Widget _buildDriverCard(Map<String, dynamic> driver, int number) {
    final seats = driver['seats'] ?? 4;
    final hasParcel = driver['parcel'] ?? false;
    final controller = _pulseControllers[driver['id']];

    Widget seatsWidget = Text(
      '💺Бўш ўрин:$seats',
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
    );

    if (controller != null) {
      seatsWidget = AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          return Opacity(
            opacity: 0.4 + (controller.value * 0.6),
            child: child,
          );
        },
        child: seatsWidget,
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          children: [
            // 1-ҚАТОР
            Row(
              children: [
                Text('$number.', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 3),
                Text('👤${driver['name']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Text('⭐${driver['rating']}', style: const TextStyle(fontSize: 10)),
                const SizedBox(width: 4),
                seatsWidget,
                const SizedBox(width: 4),
                Text(hasParcel ? '📦Жўнатма' : '📦❌', style: const TextStyle(fontSize: 10)),
                const Spacer(),
                Text('🚗${driver['plate']}', style: const TextStyle(fontSize: 10)),
              ],
            ),
            const SizedBox(height: 6),
            // 2-ҚАТОР
            Row(
              children: [
                Text('📞${driver['phone']}', style: const TextStyle(fontSize: 10)),
                const Spacer(),
                Text('💰${driver['price']} сўм', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: () => _onBookSeat(driver),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    child: const Text('БРОН'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}