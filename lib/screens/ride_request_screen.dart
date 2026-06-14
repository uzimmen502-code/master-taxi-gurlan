import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/directions_service.dart';
import '../models/ride_model.dart';
import '../models/driver_model.dart';
import 'ride_tracking_screen.dart';

class RideRequestScreen extends StatefulWidget {
  final LatLng pickupLocation;
  final String pickupAddress;
  final LatLng destinationLocation;
  final String destinationAddress;
  final int passengers;

  const RideRequestScreen({
    super.key,
    required this.pickupLocation,
    required this.pickupAddress,
    required this.destinationLocation,
    required this.destinationAddress,
    required this.passengers,
  });

  @override
  State<RideRequestScreen> createState() => _RideRequestScreenState();
}

class _RideRequestScreenState extends State<RideRequestScreen> {
  final DirectionsService _directionsService = DirectionsService();

  DirectionsResult? _directionsResult;
  bool _isLoading = true;
  String _selectedRideType = 'economy';

  double _economyPrice = 0;
  double _comfortPrice = 0;

  List<DriverModel> _nearbyDrivers = [];
  DriverModel? _selectedDriver;

  @override
  void initState() {
    super.initState();
    _loadDirections();
    _generateNearbyDrivers();
  }

  Future<void> _loadDirections() async {
    final result = await _directionsService.getDirections(
      originLat: widget.pickupLocation.latitude,
      originLng: widget.pickupLocation.longitude,
      destLat: widget.destinationLocation.latitude,
      destLng: widget.destinationLocation.longitude,
    );

    if (result != null) {
      setState(() {
        _directionsResult = result;
        _calculatePrices(result.distance);
        _isLoading = false;
      });
    } else {
      setState(() {
        _calculatePrices(5.2);
        _isLoading = false;
      });
    }
  }

  void _calculatePrices(double distance) {
    _economyPrice = 5000 + (distance * 1500);
    _comfortPrice = 10000 + (distance * 2500);
  }

  void _generateNearbyDrivers() {
    _nearbyDrivers = [
      DriverModel(
        id: '1',
        name: 'Сардор',
        phone: '+998901234567',
        carModel: 'Lacetti',
        carNumber: '01A123AA',
        rating: 4.8,
        isAvailable: true,
        latitude: widget.pickupLocation.latitude + 0.002,
        longitude: widget.pickupLocation.longitude + 0.002,
      ),
      DriverModel(
        id: '2',
        name: 'Баҳодир',
        phone: '+998909876543',
        carModel: 'Cobalt',
        carNumber: '01B456BB',
        rating: 4.9,
        isAvailable: true,
        latitude: widget.pickupLocation.latitude - 0.001,
        longitude: widget.pickupLocation.longitude + 0.003,
      ),
      DriverModel(
        id: '3',
        name: 'Акмал',
        phone: '+998934567890',
        carModel: 'Gentra',
        carNumber: '01C789CC',
        rating: 4.7,
        isAvailable: true,
        latitude: widget.pickupLocation.latitude + 0.003,
        longitude: widget.pickupLocation.longitude - 0.001,
      ),
    ];
  }

  String _formatPrice(double price) {
    return '${price.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} сўм';
  }

  void _requestRide() {
    if (_selectedDriver == null && _nearbyDrivers.isNotEmpty) {
      _selectedDriver = _nearbyDrivers.first;
    }

    if (_selectedDriver == null) {
      _showErrorDialog('Ҳайдовчи топилмади');
      return;
    }

    final ride = RideModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: 'current_user',
      driverId: _selectedDriver!.id,
      type: _selectedRideType == 'economy' ? RideType.economy : RideType.comfort,
      status: RideStatus.pending,
      pickup: LocationModel(
        latitude: widget.pickupLocation.latitude,
        longitude: widget.pickupLocation.longitude,
        address: widget.pickupAddress,
      ),
      destination: LocationModel(
        latitude: widget.destinationLocation.latitude,
        longitude: widget.destinationLocation.longitude,
        address: widget.destinationAddress,
      ),
      distance: _directionsResult?.distance ?? 5.2,
      duration: _directionsResult?.duration ?? 15,
      price: _selectedRideType == 'economy' ? _economyPrice : _comfortPrice,
      createdAt: DateTime.now(),
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => RideTrackingScreen(
          ride: ride,
          driver: _selectedDriver!,
        ),
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Хатолик'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentPrice = _selectedRideType == 'economy' ? _economyPrice : _comfortPrice;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF3E2723)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Такси чақириш',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF3E2723),
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE65100)))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Манзиллар
            _buildLocationCard(),
            const SizedBox(height: 20),

            // Тариф танлаш
            const Text(
              'Тариф танланг',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF3E2723),
              ),
            ),
            const SizedBox(height: 12),

            _buildTariffCard(
              type: 'economy',
              title: 'Эконом',
              subtitle: 'Бошқа йўловчилар билан',
              price: _economyPrice,
              isSelected: _selectedRideType == 'economy',
            ),
            const SizedBox(height: 12),

            _buildTariffCard(
              type: 'comfort',
              title: 'Комфорт',
              subtitle: 'Алоҳида машина',
              price: _comfortPrice,
              isSelected: _selectedRideType == 'comfort',
            ),
            const SizedBox(height: 20),

            // Яқин атрофдаги ҳайдовчилар
            if (_nearbyDrivers.isNotEmpty) ...[
              const Text(
                'Яқин атрофдаги ҳайдовчилар',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3E2723),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _nearbyDrivers.length,
                  itemBuilder: (context, index) {
                    final driver = _nearbyDrivers[index];
                    return _buildDriverCard(driver);
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Жами нарх
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Жами:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3E2723),
                    ),
                  ),
                  Text(
                    _formatPrice(currentPrice),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE65100),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Такси чақириш тугмаси
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _requestRide,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'ТАКСИ ЧАҚИРИШ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.pickupAddress,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.destinationAddress,
                  style: const TextStyle(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Масофа: ${_directionsResult?.distanceText ?? '~5 км'}',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              Text(
                'Вақт: ${_directionsResult?.durationText ?? '~15 дақ'}',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTariffCard({
    required String type,
    required String title,
    required String subtitle,
    required double price,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedRideType = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE65100).withOpacity(0.05) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFE65100) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFFE65100) : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Container(
                margin: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFE65100),
                ),
              )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? const Color(0xFFE65100) : const Color(0xFF3E2723),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _formatPrice(price),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isSelected ? const Color(0xFFE65100) : const Color(0xFF3E2723),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverCard(DriverModel driver) {
    final isSelected = _selectedDriver?.id == driver.id;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDriver = driver;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${driver.name} танланди'),
            duration: const Duration(seconds: 1),
            backgroundColor: const Color(0xFFE65100),
          ),
        );
      },
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE65100).withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFE65100) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, color: Color(0xFFE65100)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 12),
                          Text(' ${driver.rating}', style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              driver.carModel,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
            Text(
              driver.carNumber,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}