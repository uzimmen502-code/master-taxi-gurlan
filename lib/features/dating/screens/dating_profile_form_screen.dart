import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/user_error.dart';
import '../../../models/dating_profile.dart';
import '../services/dating_photo_storage.dart';
import '../services/dating_service.dart';

const datingAccent = Color(0xFFE5446D);

/// Tanishuv profili — yaratish/tahrirlash. Saqlangach status = "tekshiruvda".
class DatingProfileFormScreen extends StatefulWidget {
  const DatingProfileFormScreen({
    super.key,
    required this.uid,
    this.existing,
  });

  final String uid;
  final DatingProfile? existing;

  @override
  State<DatingProfileFormScreen> createState() =>
      _DatingProfileFormScreenState();
}

class _DatingProfileFormScreenState extends State<DatingProfileFormScreen> {
  final _photoStorage = DatingPhotoStorage();
  final _picker = ImagePicker();

  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _aboutCtrl = TextEditingController();
  final _eduCtrl = TextEditingController();
  final _jobCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  String _gender = '';
  String _marital = '';
  final List<DatingPhoto> _photos = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.displayName;
      _cityCtrl.text = e.city;
      _aboutCtrl.text = e.about;
      _eduCtrl.text = e.education;
      _jobCtrl.text = e.job;
      _yearCtrl.text = e.birthYear > 1900 ? '${e.birthYear}' : '';
      _gender = e.gender;
      _marital = e.maritalStatus;
      _photos.addAll(e.photos);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _aboutCtrl.dispose();
    _eduCtrl.dispose();
    _jobCtrl.dispose();
    _yearCtrl.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    if (_photos.length >= 6) {
      _snack(context.tr('dating_photos_max'));
      return;
    }
    final files = await _picker.pickMultiImage(imageQuality: 90);
    if (files.isEmpty) return;
    setState(() => _busy = true);
    try {
      for (final f in files) {
        if (_photos.length >= 6) break;
        final res = await _photoStorage.upload(userId: widget.uid, image: f);
        _photos.add(DatingPhoto(url: res.url, path: res.path));
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        _snack(userErrorMessage(context, e,
            fallbackKey: 'dating_photo_upload_failed'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto(int i) async {
    final ph = _photos[i];
    setState(() => _photos.removeAt(i));
    if (ph.path.isNotEmpty) await _photoStorage.deleteByPath(ph.path);
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().length < 2) {
      _snack(context.tr('dating_name_required'));
      return;
    }
    if (!['male', 'female'].contains(_gender)) {
      _snack(context.tr('dating_gender_required'));
      return;
    }
    final year = int.tryParse(_yearCtrl.text.trim()) ?? 0;
    final nowY = DateTime.now().year;
    if (year < nowY - 80 || year > nowY - 18) {
      _snack(context.tr('dating_year_invalid'));
      return;
    }
    if (_photos.isEmpty) {
      _snack(context.tr('dating_photo_required'));
      return;
    }
    setState(() => _busy = true);
    try {
      await DatingService.saveProfile({
        'displayName': _nameCtrl.text.trim(),
        'gender': _gender,
        'birthYear': year,
        'city': _cityCtrl.text.trim(),
        'about': _aboutCtrl.text.trim(),
        'maritalStatus': _marital,
        'education': _eduCtrl.text.trim(),
        'job': _jobCtrl.text.trim(),
        'photos': _photos.map((p) => p.toMap()).toList(),
      });
      if (mounted) {
        _snack(context.tr('dating_saved_pending'));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) _snack(userErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F6),
      appBar: AppBar(
        title: Text(isEdit
            ? context.tr('dating_edit_profile')
            : context.tr('dating_form_title')),
        backgroundColor: datingAccent,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _photoSection(),
          const SizedBox(height: 16),
          _field(_nameCtrl, context.tr('dating_f_name'), Icons.person_outline),
          const SizedBox(height: 12),
          _genderSelector(),
          const SizedBox(height: 12),
          _field(_yearCtrl, context.tr('dating_f_year'),
              Icons.cake_outlined,
              keyboard: TextInputType.number),
          const SizedBox(height: 12),
          _field(_cityCtrl, context.tr('dating_f_city'),
              Icons.location_city_outlined),
          const SizedBox(height: 12),
          _maritalSelector(),
          const SizedBox(height: 12),
          _field(_eduCtrl, context.tr('dating_f_edu'), Icons.school_outlined),
          const SizedBox(height: 12),
          _field(_jobCtrl, context.tr('dating_f_job'), Icons.work_outline),
          const SizedBox(height: 12),
          _field(_aboutCtrl, context.tr('dating_f_about'),
              Icons.notes_outlined,
              maxLines: 4),
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: datingAccent, foregroundColor: Colors.white),
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(context.tr('save')),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('dating_form_note'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _photoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('dating_photos_title'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _photos.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(_photos[i].url,
                        width: 96, height: 96, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: GestureDetector(
                      onTap: _busy ? null : () => _removePhoto(i),
                      child: Container(
                        decoration: const BoxDecoration(
                            color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close,
                            size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            if (_photos.length < 6)
              GestureDetector(
                onTap: _busy ? null : _addPhotos,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: datingAccent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: datingAccent.withValues(alpha: 0.4)),
                  ),
                  child: _busy
                      ? const Center(
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)))
                      : const Icon(Icons.add_a_photo_outlined,
                          color: datingAccent),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _genderSelector() {
    return Row(
      children: [
        Expanded(
            child: _genderChip('male', context.tr('dating_gender_male'))),
        const SizedBox(width: 10),
        Expanded(
            child: _genderChip('female', context.tr('dating_gender_female'))),
      ],
    );
  }

  Widget _genderChip(String value, String label) {
    final sel = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? datingAccent.withValues(alpha: 0.15) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sel ? datingAccent : Colors.grey.shade300,
              width: sel ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: sel ? datingAccent : Colors.black87)),
      ),
    );
  }

  Widget _maritalSelector() {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: context.tr('dating_marital_label'),
        prefixIcon: const Icon(Icons.favorite_border),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _marital.isEmpty ? '' : _marital,
          isExpanded: true,
          items: [
            DropdownMenuItem(
                value: '', child: Text(context.tr('rel_gender_none'))),
            DropdownMenuItem(
                value: 'single',
                child: Text(context.tr('dating_marital_single'))),
            DropdownMenuItem(
                value: 'divorced',
                child: Text(context.tr('dating_marital_divorced'))),
            DropdownMenuItem(
                value: 'widowed',
                child: Text(context.tr('dating_marital_widowed'))),
          ],
          onChanged: (v) => setState(() => _marital = v ?? ''),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {TextInputType? keyboard, int maxLines = 1}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
