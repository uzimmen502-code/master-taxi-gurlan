import 'package:cloud_firestore/cloud_firestore.dart';

/// Support чат админ томонидан АРХИВГА олинганми (2026-10-20, эга қарори).
///
/// Қоида: `adminArchivedAt != null` ва `updatedAt` ундан КЕЙИН эмас. Мижоз ёки админ янги хабар ёзса
/// `updatedAt` ошади — чат ўзи қайта очилади (серверда ўзгариш керак эмас). Серверда ҳам худди шу қоида
/// (`functions/admin_retract_archive.js` → `isSupportChatArchived`).
bool isSupportChatArchived(Map<String, dynamic> data) {
  final archived = _asMs(data['adminArchivedAt']);
  if (archived == null) return false;
  final updated = _asMs(data['updatedAt']);
  return !(updated != null && updated > archived);
}

int? _asMs(Object? v) {
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is DateTime) return v.millisecondsSinceEpoch;
  return null;
}
