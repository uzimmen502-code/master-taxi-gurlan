import 'package:cloud_firestore/cloud_firestore.dart';

/// `entertainment_catalog/{id}` — админ каталоги (B variant).
class EntertainmentVideo {
  const EntertainmentVideo({
    required this.id,
    required this.title,
    required this.storagePath,
    this.downloadUrl = '',
    this.durationSec = 0,
    this.active = true,
    this.sortOrder = 0,
  });

  final String id;
  final String title;
  final String storagePath;
  final String downloadUrl;
  final int durationSec;
  final bool active;
  final int sortOrder;

  factory EntertainmentVideo.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return EntertainmentVideo(
      id: doc.id,
      title: (d['title'] ?? '') as String,
      storagePath: (d['storagePath'] ?? '') as String,
      downloadUrl: (d['downloadUrl'] ?? '') as String,
      durationSec: (d['durationSec'] as num?)?.toInt() ?? 0,
      active: d['active'] != false,
      sortOrder: (d['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  String get durationLabel {
    if (durationSec <= 0) return '';
    final m = durationSec ~/ 60;
    final s = durationSec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
