import '../../models/job_ad.dart';

/// ИШ ТОП — фойдаланувчи панели таблари (Иш бор / Хизмат).
abstract final class JobsTabs {
  static const int count = 2;

  static const int ad = 0;
  static const int service = 1;

  static const List<String> labels = [
    'Иш бор',
    'Хизмат таклифи',
  ];

  static AdKind? kindForIndex(int index) {
    switch (index) {
      case ad:
        return AdKind.ad;
      case service:
        return AdKind.service;
      default:
        return null;
    }
  }

  static int clampIndex(int index) => index.clamp(0, count - 1);
}
