import 'same_origin_nav_stub.dart'
    if (dart.library.html) 'same_origin_nav_web.dart' as impl;

/// Вебда хостнинг `origin`и билан йўлга ўтади (SPA иккинчи entry учун).
///
/// Масалан: `/admin/` — админ Flutter web, `/` — фойдаланувчи иловаси.
///
/// Қайтариш: агар саҳифани юкламасдан қайтарилган булса `false` (debug админ `/` да).
bool navigateSameOriginPath(String path) => impl.navigateSameOriginPath(path);
