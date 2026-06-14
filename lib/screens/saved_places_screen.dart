import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/saved_place.dart';
import '../l10n/app_localizations.dart';
import 'map_picker_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  List<SavedPlace> _savedPlaces = [];
  bool _isLoading = true;

  // Стандарт жойлар
  static const String _homeAddress = 'Чилонзор, 19-квартал';
  static const String _workAddress = 'Миробод, А.Темур кўчаси';
  static const LatLng _homeLatLng = LatLng(41.2995, 69.2401);
  static const LatLng _workLatLng = LatLng(41.3111, 69.2797);

  @override
  void initState() {
    super.initState();
    _loadSavedPlaces();
  }

  Future<void> _loadSavedPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedPlacesJson = prefs.getString('saved_places');

    setState(() {
      if (savedPlacesJson != null) {
        final List<dynamic> decoded = jsonDecode(savedPlacesJson);
        _savedPlaces = decoded.map((item) => SavedPlace.fromJson(item)).toList();
      } else {
        // Стандарт жойларни қўшиш
        _savedPlaces = [
          SavedPlace(
            id: 'home',
            name: 'Уй',
            address: _homeAddress,
            lat: _homeLatLng.latitude,
            lng: _homeLatLng.longitude,
            icon: '🏠',
            isDefault: true,
          ),
          SavedPlace(
            id: 'work',
            name: 'Иш',
            address: _workAddress,
            lat: _workLatLng.latitude,
            lng: _workLatLng.longitude,
            icon: '💼',
            isDefault: true,
          ),
        ];
        _savePlacesToStorage();
      }
      _isLoading = false;
    });
  }

  Future<void> _savePlacesToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_savedPlaces.map((p) => p.toJson()).toList());
    await prefs.setString('saved_places', encoded);
  }

  Future<void> _addNewPlace() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MapPickerScreen(),
      ),
    );

    if (result != null && result is Map) {
      _showAddPlaceDialog(
        result['address'] ?? '',
        result['latitude'] ?? 41.2995,
        result['longitude'] ?? 69.2401,
      );
    }
  }

  void _showAddPlaceDialog(String address, double lat, double lng) {
    final TextEditingController nameController = TextEditingController();
    String selectedIcon = '📍';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Янги манзил қўшиш'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Манзил: $address', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: 'Ном беринг (мас: Мактаб)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Иконка танланг:'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  children: [
                    _buildIconOption('🏠', 'Уй', selectedIcon, () {
                      setState(() => selectedIcon = '🏠');
                    }),
                    _buildIconOption('💼', 'Иш', selectedIcon, () {
                      setState(() => selectedIcon = '💼');
                    }),
                    _buildIconOption('🏫', 'Мактаб', selectedIcon, () {
                      setState(() => selectedIcon = '🏫');
                    }),
                    _buildIconOption('🏥', 'Шифохона', selectedIcon, () {
                      setState(() => selectedIcon = '🏥');
                    }),
                    _buildIconOption('🛒', 'Бозор', selectedIcon, () {
                      setState(() => selectedIcon = '🛒');
                    }),
                    _buildIconOption('☕', 'Кафе', selectedIcon, () {
                      setState(() => selectedIcon = '☕');
                    }),
                    _buildIconOption('📍', 'Бошқа', selectedIcon, () {
                      setState(() => selectedIcon = '📍');
                    }),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Бекор қилиш'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    setState(() {
                      _savedPlaces.add(SavedPlace(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: nameController.text,
                        address: address,
                        lat: lat,
                        lng: lng,
                        icon: selectedIcon,
                      ));
                    });
                    _savePlacesToStorage();
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('Сақлаш'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIconOption(String icon, String label, String selectedIcon, VoidCallback onTap) {
    final isSelected = icon == selectedIcon;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade100 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  void _editPlace(SavedPlace place) {
    if (place.isDefault) {
      _showErrorDialog('Стандарт манзилларни ўзгартириб бўлмайди');
      return;
    }

    final TextEditingController nameController = TextEditingController(text: place.name);
    String selectedIcon = place.icon;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Манзилни таҳрирлаш'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Манзил: ${place.address}', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: 'Ном беринг',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  children: [
                    _buildIconOption('🏠', 'Уй', selectedIcon, () {
                      setState(() => selectedIcon = '🏠');
                    }),
                    _buildIconOption('💼', 'Иш', selectedIcon, () {
                      setState(() => selectedIcon = '💼');
                    }),
                    _buildIconOption('🏫', 'Мактаб', selectedIcon, () {
                      setState(() => selectedIcon = '🏫');
                    }),
                    _buildIconOption('🏥', 'Шифохона', selectedIcon, () {
                      setState(() => selectedIcon = '🏥');
                    }),
                    _buildIconOption('🛒', 'Бозор', selectedIcon, () {
                      setState(() => selectedIcon = '🛒');
                    }),
                    _buildIconOption('☕', 'Кафе', selectedIcon, () {
                      setState(() => selectedIcon = '☕');
                    }),
                    _buildIconOption('📍', 'Бошқа', selectedIcon, () {
                      setState(() => selectedIcon = '📍');
                    }),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Бекор қилиш'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    setState(() {
                      final index = _savedPlaces.indexWhere((p) => p.id == place.id);
                      if (index != -1) {
                        _savedPlaces[index] = SavedPlace(
                          id: place.id,
                          name: nameController.text,
                          address: place.address,
                          lat: place.lat,
                          lng: place.lng,
                          icon: selectedIcon,
                          isDefault: place.isDefault,
                        );
                      }
                    });
                    _savePlacesToStorage();
                    Navigator.pop(context);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('Сақлаш'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _deletePlace(SavedPlace place) {
    if (place.isDefault) {
      _showErrorDialog('Стандарт манзилларни ўчириб бўлмайди');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Манзилни ўчириш'),
        content: Text('${place.name} манзилини ўчирмоқчимисиз?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Бекор қилиш'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _savedPlaces.removeWhere((p) => p.id == place.id);
              });
              _savePlacesToStorage();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Ўчириш'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Огоҳлантириш'),
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
    final loc = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          loc.translate('saved_places'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.blue),
            onPressed: _addNewPlace,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedPlaces.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text('Ҳеч қандай манзил сақланмаган'),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _addNewPlace,
              icon: const Icon(Icons.add),
              label: const Text('Янги манзил қўшиш'),
            ),
          ],
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _savedPlaces.length,
        itemBuilder: (context, index) {
          final place = _savedPlaces[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    place.icon,
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              title: Text(
                place.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                place.address,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!place.isDefault)
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                      onPressed: () => _editPlace(place),
                    ),
                  if (!place.isDefault)
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                      onPressed: () => _deletePlace(place),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}