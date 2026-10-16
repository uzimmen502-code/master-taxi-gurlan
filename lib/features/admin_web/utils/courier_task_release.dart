// «Kuryerdan olish» (B1): kuryer yo'qolsa/javob bermasa admin gilam yoki sut
// vazifasini kuryerdan qaytarib oladi.
//
// QIRRALAR serverda (`functions/index.js` → `CARPET_ADMIN_TRANSITIONS`,
// `CARPET_RELEASE_EDGES`, `AGRO_ADMIN_TRANSITIONS`): ekran ularni FAQAT tugma
// ko'rsatish uchun aks ettiradi; ruxsat va kuryer maydonlarini tozalash
// serverda (44-band). Server rad etsa — xato matni ko'rsatiladi.

const Map<String, String> kCarpetReleaseEdges = {
  'pickup_in_delivery': 'pickup_ready',
  'return_in_delivery': 'return_ready',
};

const Map<String, String> kAgroReleaseEdges = {
  'pickup_in_delivery': 'accepted',
};

/// Gilam: joriy holatdan «kuryerdan olish» maqsad holati (yoki `null`).
String? carpetReleaseTarget(String status) => kCarpetReleaseEdges[status];

/// Sut: joriy holatdan «kuryerdan olish» maqsad holati (yoki `null`).
String? agroReleaseTarget(String status) => kAgroReleaseEdges[status];
