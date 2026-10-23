/// Ўзбекистон атрофи — координата чегараси (эга қарори 2026-10-23 бўйича PROPOSED B-11).
///
/// Серверда ва rules'да ҚОТИРИЛГАН нусхалари бор — уч жой бир хил бўлиши шарт, `uz_bounds_parity_test.dart`
/// қулфлайди: `functions/business_directory.js` (`BOUNDS`) ва `firestore.rules`
/// (`wholesaleSellerLocationRequiredOk`). Ўзгартирсангиз — ҳаммасини.
library;

const double kUzLatMin = 36;
const double kUzLatMax = 46;
const double kUzLngMin = 55;
const double kUzLngMax = 74;

/// Нуқта Ўзбекистон атрофи қутисида ва тўғри сонми.
bool inUzbekistanBounds(double? lat, double? lng) =>
    lat != null &&
    lng != null &&
    lat.isFinite &&
    lng.isFinite &&
    lat >= kUzLatMin &&
    lat <= kUzLatMax &&
    lng >= kUzLngMin &&
    lng <= kUzLngMax;
