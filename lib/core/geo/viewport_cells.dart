import '../../utils/geo_hash.dart';

/// Харита камераси қоплаган `geohash4` катакчалари (кластерсиз ўқиш режаси, docs/biznes_xaritasi_2026-10-23_uz.md).
///
/// Firestore `whereIn` чегараси — 30 қиймат: камера бундан кўп катакчани қопласа ([forBounds] `null`
/// қайтаради) харита «яқинлаштиринг» дейди ва ЎҚИМАЙДИ (36-банд: чексиз ўқиш йўқ).
abstract final class ViewportCells {
  static const int maxCells = 30;

  // geohash precision 4 = 20 бит: узунлик учун 10, кенглик учун 10 бит.
  static const double _cellLat = 180.0 / 1024; // ≈ 0.1758°
  static const double _cellLng = 360.0 / 1024; // ≈ 0.3516°

  /// [south..north] × [west..east] ни қоплайдиган катакчалар; чегарадан катта бўлса `null`.
  /// 180-меридиандан ўтадиган камера (west > east) қўллаб-қувватланмайди — `null`.
  static List<String>? forBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  }) {
    if (!(north >= south) || !(east >= west)) return null;
    final rows = ((north - south) / _cellLat).ceil() + 1;
    final cols = ((east - west) / _cellLng).ceil() + 1;
    // Тез рад: катакчалар сони чегарадан ошиб кетса, ҳисоблаб ўтирмаймиз.
    if (rows * cols > maxCells * 4) return null;

    final cells = <String>{};
    double lat(int r) => r == rows - 1 ? north : south + r * _cellLat;
    double lng(int c) => c == cols - 1 ? east : west + c * _cellLng;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        cells.add(GeoHash.encode(lat(r).clamp(-90.0, 90.0), lng(c).clamp(-180.0, 180.0), precision: 4));
        if (cells.length > maxCells) return null;
      }
    }
    return cells.toList(growable: false);
  }
}
