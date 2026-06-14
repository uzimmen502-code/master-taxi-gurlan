import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'map_picker_screen.dart';
import 'searching_screen.dart';
import 'package:geocoding/geocoding.dart';
class LocalTaxiScreen extends StatefulWidget {
  const LocalTaxiScreen({super.key});

  @override
  State<LocalTaxiScreen> createState() => _LocalTaxiScreenState();
}

class _LocalTaxiScreenState extends State<LocalTaxiScreen> {
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();

  List<String> _fromSuggestions = [];
  List<String> _toSuggestions = [];
  Timer? _debounceTimer;
  bool _isFromFocused = false;
  bool _isToFocused = false;

  String? _selectedTaxiType;
  List<Map<String, String>> _savedPlaces = [];
  bool _isGpsLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedPlaces();
  }

  Future<void> _loadSavedPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('saved_places');
    if (saved != null) {
      final List<dynamic> decoded = jsonDecode(saved);
      setState(() {
        _savedPlaces = decoded.map((item) => Map<String, String>.from(item)).toList();
      });
    }
  }

  Future<void> _savePlaces() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_places', jsonEncode(_savedPlaces));
  }

  Future<void> _addNewPlace() async {
    if (_savedPlaces.length >= 6) {
      _showSnackBar('Максимум 6 та манзил сақлаш мумкин');
      return;
    }

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const MapPickerScreen(title: 'Янги манзил танлаш'),
      ),
    );

    if (result != null) {
      _showNameDialog(result);
    }
  }

  void _showNameDialog(String address) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Манзил номи'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              hintText: 'Масалан: Дўкон, Мактаб',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Бекор қилиш'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  setState(() {
                    _savedPlaces.add({'name': name, 'address': address});
                  });
                  _savePlaces();
                  Navigator.pop(context);
                  _showSnackBar('$name сақланди');
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              child: const Text('Сақлаш'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _searchAddress(String query, bool isFrom) async {
    if (query.length < 2) {
      setState(() {
        if (isFrom) { _fromSuggestions = []; } else { _toSuggestions = []; }
      });
      return;
    }

    final fakeSuggestions = [
      '$query кўчаси, Тошкент',
      '$query-19, Тошкент',
      '$query-20, Тошкент',
      '$query бозори, Тошкент',
      '$query маҳалласи, Тошкент',
    ];

    setState(() {
      if (isFrom) { _fromSuggestions = fakeSuggestions; } else { _toSuggestions = fakeSuggestions; }
    });
  }

  void _onFromChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () => _searchAddress(value, true));
  }

  void _onToChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () => _searchAddress(value, false));
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGpsLoading = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('GPS рухсати берилмади');
          setState(() => _isGpsLoading = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('GPS рухсати рад этилган. Созламалардан рухсат беринг');
        setState(() => _isGpsLoading = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      // Координатани манзилга айлантириш
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final address = '${place.street ?? ''} ${place.subLocality ?? ''}, ${place.locality ?? ''}'.trim();

        setState(() {
          _fromController.text = address.isNotEmpty ? address : '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
          _fromSuggestions = [];
          _isGpsLoading = false;
        });

        _showSnackBar('Жойлашув аниқланди: $address');
      } else {
        setState(() {
          _fromController.text = '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
          _isGpsLoading = false;
        });
        _showSnackBar('Жойлашув аниқланди');
      }
    } catch (e) {
      setState(() => _isGpsLoading = false);
      _showSnackBar('GPS аниқланмади. Қайта уриниб кўринг');
    }
  }

  Future<void> _pickFromMap() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const MapPickerScreen(title: 'Манзил танлаш')),
    );
    if (result != null) {
      setState(() => _toController.text = result);
    }
  }

  void _onSearch() {
    if (_fromController.text.trim().isEmpty && _selectedTaxiType == 'alone') {
      _showGpsDialog();
      return;
    }

    if (_selectedTaxiType == 'marshrut') {
      if (_fromController.text.trim().isEmpty || _toController.text.trim().isEmpty) {
        _showSnackBar('МАРШРУТ ТАКСИ учун "Қаердан" ва "Қаерга" майдонларини тўлдиринг');
        return;
      }
    }

    if (_selectedTaxiType == null) {
      _showSnackBar('Такси турини танланг');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchingScreen(
          from: _fromController.text.trim(),
          to: _toController.text.trim(),
          taxiType: _selectedTaxiType!,
        ),
      ),
    );
  }

  void _showGpsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('📍 Жойлашувингизни аниқланг'),
          content: const Text('"Қаердан" майдони бўш.\nДав этиш учун GPS орқали жойлашувингизни аниқланг.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Орқага')),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _getCurrentLocation().then((_) {
                  if (_fromController.text.trim().isNotEmpty) _onSearchAfterGps();
                });
              },
              icon: const Icon(Icons.gps_fixed),
              label: const Text('GPS'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            ),
          ],
        );
      },
    );
  }

  void _onSearchAfterGps() {
    if (_selectedTaxiType == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchingScreen(
          from: _fromController.text.trim(),
          to: _toController.text.trim(),
          taxiType: _selectedTaxiType!,
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating),
    );
  }

  void _selectTaxiType(String type) {
    setState(() => _selectedTaxiType = type);
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // ============ BUILD ============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🚕 Маҳаллий такси'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFromField(),
            const SizedBox(height: 10),
            _buildToField(),
            const SizedBox(height: 8),
            _buildSavedPlacesGrid(),
            const SizedBox(height: 14),
            _buildTaxiTypeCard(
              icon: Icons.airport_shuttle,
              title: 'МАРШРУТ ТАКСИ',
              subtitle: 'Ҳайдовчи билан келишилади',
              type: 'marshrut',
            ),
            const SizedBox(height: 10),
            _buildTaxiTypeCard(
              icon: Icons.local_taxi,
              title: 'TAXI ХИЗМАТИ',
              subtitle: 'Тариф бўйича',
              type: 'alone',
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _selectedTaxiType != null ? _onSearch : null,
                icon: const Icon(Icons.search, size: 24),
                label: const Text('ҚИДИРИШ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  disabledForegroundColor: Colors.grey[500],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============ ҚАЕРДАН МАЙДОНИ ============
  Widget _buildFromField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // КАТТА ВА СЕМИЗ "Қаердан"
        const Text(
          '🔵 Қаердан',
          style: TextStyle(
            fontSize: 20,       // 1.5 баробар катта
            fontWeight: FontWeight.w900,  // семиз
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _fromController,
          onChanged: _onFromChanged,
          onTap: () => setState(() => _isFromFocused = true),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Манзилни киритинг',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
            prefixIcon: const Icon(Icons.circle, color: Colors.green, size: 10),
            suffixIcon: _isGpsLoading
                ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(6.0), child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(
              onPressed: _getCurrentLocation,
              icon: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.gps_not_fixed, color: Colors.red, size: 22),
                  Icon(Icons.circle, color: Colors.red, size: 10),
                ],
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: Colors.grey[50],
            isDense: true,
          ),
        ),
        if (_fromSuggestions.isNotEmpty && _isFromFocused)
          _buildSuggestionsList(_fromSuggestions, _fromController, () => setState(() => _isFromFocused = false)),
      ],
    );
  }

  // ============ ҚАЕРГА МАЙДОНИ ============
  Widget _buildToField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // КАТТА ВА СЕМИЗ "Қаерга"
        const Text(
          '🔴 Қаерга',
          style: TextStyle(
            fontSize: 20,       // 1.5 баробар катта
            fontWeight: FontWeight.w900,  // семиз
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _toController,
          onChanged: _onToChanged,
          onTap: () => setState(() => _isToFocused = true),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Манзилни киритинг (ихтиёрий)',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
            prefixIcon: const Icon(Icons.circle, color: Colors.red, size: 10),
            suffixIcon: IconButton(
              onPressed: _pickFromMap,
              icon: const Icon(Icons.push_pin, color: Colors.red, size: 22),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: Colors.grey[50],
            isDense: true,
          ),
        ),
        if (_toSuggestions.isNotEmpty && _isToFocused)
          _buildSuggestionsList(_toSuggestions, _toController, () => setState(() => _isToFocused = false)),
      ],
    );
  }

  // ============ САҚЛАНГАН МАНЗИЛЛАР ============
  Widget _buildSavedPlacesGrid() {
    List<Widget> buttons = [];
    for (var place in _savedPlaces) {
      buttons.add(_buildSmallPlaceButton(
        name: place['name'] ?? '?',
        icon: _getPlaceIcon(place['name'] ?? ''),
        color: _getPlaceColor(place['name'] ?? ''),
        onTap: () => setState(() => _fromController.text = place['address'] ?? ''),
        onLongPress: () => _deletePlace(place['name'] ?? ''),
      ));
    }
    if (_savedPlaces.length < 6) {
      buttons.add(_buildSmallPlaceButton(name: '+', icon: Icons.add, color: Colors.green, isAddButton: true, onTap: _addNewPlace));
    }
    return Wrap(spacing: 6, runSpacing: 6, children: buttons);
  }

  Widget _buildSmallPlaceButton({required String name, required IconData icon, required Color color, required VoidCallback onTap, VoidCallback? onLongPress, bool isAddButton = false}) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: isAddButton ? null : onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isAddButton ? Colors.green[50] : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isAddButton ? Colors.green : Colors.grey[300]!, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isAddButton ? Colors.green : Colors.black87)),
          ],
        ),
      ),
    );
  }

  IconData _getPlaceIcon(String name) {
    switch (name.toLowerCase()) {
      case 'уй': return Icons.home;
      case 'иш': return Icons.work;
      case 'дўкон':
      case 'дукон': return Icons.store;
      case 'мактаб': return Icons.school;
      case 'шифо':
      case 'шифохона': return Icons.local_hospital;
      default: return Icons.place;
    }
  }

  Color _getPlaceColor(String name) {
    switch (name.toLowerCase()) {
      case 'уй': return Colors.blue;
      case 'иш': return Colors.orange;
      case 'дўкон':
      case 'дукон': return Colors.purple;
      case 'мактаб': return Colors.red;
      case 'шифо':
      case 'шифохона': return Colors.teal;
      default: return Colors.grey[600]!;
    }
  }

  void _deletePlace(String name) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Манзилни ўчириш'),
          content: Text('"$name" манзилини ўчиришни истайсизми?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Йўқ')),
            ElevatedButton(
              onPressed: () {
                setState(() => _savedPlaces.removeWhere((p) => p['name'] == name));
                _savePlaces();
                Navigator.pop(context);
                _showSnackBar('$name ўчирилди');
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Ҳа'),
            ),
          ],
        );
      },
    );
  }

  // ============ АВТОКОМПЛИТ ============
  Widget _buildSuggestionsList(List<String> suggestions, TextEditingController controller, VoidCallback onSelected) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 180),
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          return ListTile(
            leading: const Icon(Icons.location_on, color: Colors.grey, size: 18),
            title: Text(suggestions[index], style: const TextStyle(fontSize: 13)),
            dense: true,
            onTap: () {
              controller.text = suggestions[index];
              setState(() {
                if (controller == _fromController) { _fromSuggestions = []; } else { _toSuggestions = []; }
              });
              onSelected();
            },
          );
        },
      ),
    );
  }

  // ============ ТАКСИ ТУРИ КАРТОЧКАСИ ============
  Widget _buildTaxiTypeCard({required IconData icon, required String title, required String subtitle, required String type}) {
    final isSelected = _selectedTaxiType == type;

    return GestureDetector(
      onTap: () => _selectTaxiType(type),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? Colors.green : Colors.grey[300]!, width: isSelected ? 2 : 1),
          boxShadow: isSelected ? [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))] : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 36, color: Colors.amber),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // СЕМИЗ МАТН
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,  // семиз
                      color: isSelected ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white70 : Colors.grey[500])),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: Colors.white, size: 26),
          ],
        ),
      ),
    );
  }
}