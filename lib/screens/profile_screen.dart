import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _profileImagePath;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadSavedImage();
  }

  Future<void> _loadSavedImage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/profile_image.jpg');
      if (await file.exists()) {
        setState(() => _profileImagePath = file.path);
      }
    } catch (e) {}
  }

  Future<void> _saveImage(File imageFile) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final savedImage = await imageFile.copy('${directory.path}/profile_image.jpg');
      setState(() => _profileImagePath = savedImage.path);
    } catch (e) {}
  }

  Future<void> _pickImageFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) await _saveImage(File(image.path));
  }

  Future<void> _takePhoto() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (image != null) await _saveImage(File(image.path));
  }

  Future<void> _deleteImage() async {
    if (_profileImagePath != null) {
      final file = File(_profileImagePath!);
      if (await file.exists()) await file.delete();
      setState(() => _profileImagePath = null);
    }
  }

  void _showImagePickerDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              const Text('Расмни қаердан олиш?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              ListTile(leading: const Icon(Icons.photo_library), title: const Text('Галереядан'), onTap: () { Navigator.pop(context); _pickImageFromGallery(); }),
              ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Камерадан олиш'), onTap: () { Navigator.pop(context); _takePhoto(); }),
              if (_profileImagePath != null) ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text('Расмни ўчириш', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(context); _deleteImage(); }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профил'), backgroundColor: Colors.green, foregroundColor: Colors.white),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _showImagePickerDialog,
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[200], border: Border.all(color: Colors.green, width: 3)),
                child: ClipOval(
                  child: _profileImagePath != null
                      ? Image.file(File(_profileImagePath!), fit: BoxFit.cover)
                      : const Icon(Icons.person, size: 60, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Профил расмини босинг', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}