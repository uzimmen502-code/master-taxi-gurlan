/**
 * Namoyish (demo) yuk e'lonlari — Yuk Birjasi bo'sh ko'rinmasligi uchun.
 *   7 dona «Туман ичида»  → yuk_local_drivers
 *   7 dona «Шаҳарлараро» → yuk_listings
 *
 *   node functions/tools/seed_yuk_demo.js           — yozadi (idempotent: doc id fiksatsiya)
 *   node functions/tools/seed_yuk_demo.js --delete  — BARCHA isDemo yozuvlarni o'chiradi
 *
 * Har bir yozuvda `isDemo: true`:
 *   - ilovada kartada «Намойиш» belgisi chiqadi;
 *   - haqiqiy foydalanuvchilar yetarli bo'lgach `--delete` bilan tozalanadi.
 *
 * Telefon — dispecher raqami (egasi): qo'ng'iroq/chat shu raqamga tushadi.
 * `ownerId` ataylab telefon EMAS (`demo_*`), aks holda e'lonlar egasiga
 * «Меники» bo'lib ko'rinardi (`phonesMatch(ownerId, myPhone)`).
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const keyPath = path.join(__dirname, '..', 'service-account.json');
if (!fs.existsSync(keyPath)) {
  console.error('service-account.json topilmadi:', keyPath);
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
const db = admin.firestore();
db.settings({ preferRest: true });

const DEMO_PHONE = '+998912778777';
const LOCAL_COL = 'yuk_local_drivers';
const INTERCITY_COL = 'yuk_listings';

const NOW = Date.now();
const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;

const ts = (ms) => admin.firestore.Timestamp.fromMillis(ms);

/** Гурлан (Хоразм) markazi atrofi. */
const localDrivers = [
  {
    id: 'demo_local_1',
    ownerName: 'Ойбек Матназаров',
    vehicleType: 'moto',
    plateNumber: '90 A 234 BC',
    capacityKg: 300,
    body: [1.5, 1.0, 0.8],
    acceptRadiusKm: 20,
    loadStatus: 'empty',
    lat: 41.8592,
    lng: 60.3878,
    locationLabel: 'Гурлан марказий бозор',
    rating: 4.9,
    completedLoads: 34,
    onlineMinAgo: 1,
  },
  {
    id: 'demo_local_2',
    ownerName: 'Рустам Юсупов',
    vehicleType: 'labo',
    plateNumber: '90 B 517 AC',
    capacityKg: 800,
    body: [2.2, 1.4, 1.3],
    acceptRadiusKm: 20,
    loadStatus: 'empty',
    lat: 41.8551,
    lng: 60.3902,
    locationLabel: 'Гурлан, Мустақиллик кўчаси',
    rating: 4.8,
    completedLoads: 51,
    onlineMinAgo: 2,
  },
  {
    id: 'demo_local_3',
    ownerName: 'Шавкат Ҳудойберганов',
    vehicleType: 'isuzu',
    plateNumber: '90 C 128 DA',
    capacityKg: 5000,
    body: [4.2, 2.0, 2.0],
    acceptRadiusKm: 50,
    loadStatus: 'empty',
    lat: 41.8635,
    lng: 60.3810,
    locationLabel: 'Гурлан, Ёшлик МФЙ',
    rating: 4.7,
    completedLoads: 22,
    onlineMinAgo: 4,
  },
  {
    id: 'demo_local_4',
    ownerName: 'Фаррух Сафаров',
    vehicleType: 'gazel',
    plateNumber: '90 D 745 BB',
    capacityKg: 1500,
    body: [3.0, 1.8, 1.7],
    acceptRadiusKm: 20,
    loadStatus: 'busy',
    lat: 41.8489,
    lng: 60.3951,
    locationLabel: 'Гурлан, Дўстлик кўчаси',
    rating: 4.6,
    completedLoads: 18,
    onlineMinAgo: 3,
  },
  {
    id: 'demo_local_5',
    ownerName: 'Бахтиёр Раҳимов',
    vehicleType: 'traktor',
    plateNumber: '90 E 061 CA',
    capacityKg: 3000,
    body: [3.5, 1.8, 0.9],
    acceptRadiusKm: 15,
    loadStatus: 'empty',
    lat: 41.8712,
    lng: 60.3702,
    locationLabel: 'Гурлан, Қўшкўпир йўли',
    rating: 4.5,
    completedLoads: 12,
    onlineMinAgo: 6,
  },
  {
    id: 'demo_local_6',
    ownerName: 'Улуғбек Отажонов',
    vehicleType: 'samosval',
    plateNumber: '90 F 392 AB',
    capacityKg: 10000,
    body: [4.0, 2.2, 1.2],
    acceptRadiusKm: 50,
    loadStatus: 'empty',
    lat: 41.8408,
    lng: 60.4080,
    locationLabel: 'Гурлан, Янгибозор йўли',
    rating: 4.8,
    completedLoads: 40,
    onlineMinAgo: 5,
  },
  {
    id: 'demo_local_7',
    ownerName: 'Дилшод Қурбонов',
    vehicleType: 'pickup',
    plateNumber: '90 G 803 CB',
    capacityKg: 1000,
    body: [2.4, 1.5, 1.2],
    acceptRadiusKm: 20,
    loadStatus: 'empty',
    lat: 41.8801,
    lng: 60.3585,
    locationLabel: 'Гурлан, Навоий кўчаси',
    rating: 5.0,
    completedLoads: 9,
    onlineMinAgo: 8,
  },
];

/** `from`/`to` — IntercityPlaces kanonik (kirill) qiymatlari. */
const intercityListings = [
  {
    id: 'demo_yuk_1',
    type: 'truck',
    from: 'Хоразм • Гурлан',
    to: 'Тошкент',
    vehicleType: 'fura',
    ownerName: 'Азамат Жуманиёзов',
    capacity: 20000,
    freeSpace: 8000,
    price: 2500000,
    comment: 'Йўлда, бўш жой бор. Юк олиб кетаман.',
    stars: 4.9,
    createdHoursAgo: 2,
  },
  {
    id: 'demo_yuk_2',
    type: 'cargo',
    from: 'Хоразм • Гурлан',
    to: 'Урганч',
    vehicleType: 'bort',
    ownerName: 'Ислом Абдуллаев',
    cargo: 'Пахта хом ашёси',
    weight: 3000,
    price: 400000,
    comment: 'Эрталабгача етказилиши керак.',
    stars: 4.7,
    createdHoursAgo: 4,
  },
  {
    id: 'demo_yuk_3',
    type: 'truck',
    from: 'Урганч',
    to: 'Нукус',
    vehicleType: 'isoterm',
    ownerName: 'Санжар Ҳасанов',
    capacity: 8000,
    freeSpace: 3000,
    price: 900000,
    comment: 'Совутгичли фургон, тез бузиладиган юк учун.',
    stars: 4.8,
    createdHoursAgo: 6,
  },
  {
    id: 'demo_yuk_4',
    type: 'cargo',
    from: 'Хоразм • Хива',
    to: 'Самарқанд',
    vehicleType: 'furgon',
    ownerName: 'Гулнора Раҳимова',
    cargo: 'Мебель (уй кўчиш)',
    weight: 1200,
    price: 1800000,
    comment: 'Эҳтиёткорона юклаш керак.',
    stars: 5.0,
    createdHoursAgo: 9,
  },
  {
    id: 'demo_yuk_5',
    type: 'truck',
    from: 'Хоразм • Гурлан',
    to: 'Бухоро',
    vehicleType: 'isuzu',
    ownerName: 'Мурод Сапаров',
    capacity: 5000,
    freeSpace: 5000,
    price: 1200000,
    comment: 'Бўш кетаман, йўл-йўлакай юк оламан.',
    stars: 4.6,
    createdHoursAgo: 12,
  },
  {
    id: 'demo_yuk_6',
    type: 'cargo',
    from: 'Хоразм • Гурлан',
    to: 'Тошкент',
    stops: ['Навоий'],
    vehicleType: 'fura',
    ownerName: 'Ботир Эшонов',
    cargo: 'Қовун-тарвуз (мавсумий)',
    weight: 15000,
    price: 3000000,
    comment: 'Тунда юклаш, ертўладан.',
    stars: 4.9,
    createdHoursAgo: 18,
  },
  {
    id: 'demo_yuk_7',
    type: 'truck',
    from: 'Нукус',
    to: 'Хоразм • Гурлан',
    vehicleType: 'samosval',
    ownerName: 'Жамшид Аллабергенов',
    capacity: 12000,
    freeSpace: 12000,
    price: 700000,
    comment: 'Қурилиш материали ташийман (шағал, қум).',
    stars: 4.5,
    createdHoursAgo: 22,
  },
];

async function seedLocal() {
  const batch = db.batch();
  for (const d of localDrivers) {
    const created = ts(NOW - (7 - localDrivers.indexOf(d)) * DAY);
    batch.set(db.collection(LOCAL_COL).doc(d.id), {
      ownerId: d.id,
      ownerName: d.ownerName,
      phone: DEMO_PHONE,
      vehicleType: d.vehicleType,
      plateNumber: d.plateNumber,
      capacityKg: d.capacityKg,
      bodyLengthM: d.body[0],
      bodyWidthM: d.body[1],
      bodyHeightM: d.body[2],
      acceptRadiusKm: d.acceptRadiusKm,
      loadStatus: d.loadStatus,
      lat: d.lat,
      lng: d.lng,
      locationLabel: d.locationLabel,
      workStartMinutes: 0,
      workEndMinutes: 24 * 60,
      rating: d.rating,
      completedLoads: d.completedLoads,
      updatedAt: created,
      createdAt: created,
      expiresAt: ts(NOW + 180 * DAY),
      isDemo: true,
    }, { merge: true });
  }
  await batch.commit();
  return localDrivers.length;
}

async function seedIntercity() {
  const batch = db.batch();
  for (const l of intercityListings) {
    const created = NOW - l.createdHoursAgo * HOUR;
    batch.set(db.collection(INTERCITY_COL).doc(l.id), {
      type: l.type,
      from: l.from,
      to: l.to,
      stops: l.stops || [],
      vehicleType: l.vehicleType,
      ownerId: l.id,
      ownerName: l.ownerName,
      phone: DEMO_PHONE,
      status: 'active',
      cargo: l.cargo || null,
      // Огирлик бирлиги: `unit: 'kg'` (эскилари тонна деб ўқилади).
      unit: 'kg',
      weight: l.weight != null ? l.weight : null,
      capacity: l.capacity != null ? l.capacity : null,
      freeSpace: l.freeSpace != null ? l.freeSpace : null,
      price: l.price,
      comment: l.comment,
      stars: l.stars,
      createdAt: ts(created),
      // Намойиш эълони 48 соатда ёпилиб қолмаслиги учун узоқ муддат
      // (`expirePendingTrips` faqat expiresAt < now бўлганда ёпади).
      expiresAt: ts(NOW + 180 * DAY),
      updatedAt: ts(created),
      isDemo: true,
    }, { merge: true });
  }
  await batch.commit();
  return intercityListings.length;
}

async function deleteDemo(col) {
  const snap = await db.collection(col).where('isDemo', '==', true).get();
  if (snap.empty) return 0;
  const batch = db.batch();
  for (const doc of snap.docs) batch.delete(doc.ref);
  await batch.commit();
  return snap.size;
}

async function main() {
  if (process.argv.includes('--delete')) {
    const local = await deleteDemo(LOCAL_COL);
    const intercity = await deleteDemo(INTERCITY_COL);
    console.log(JSON.stringify({ deleted: { local, intercity } }, null, 2));
    return;
  }
  const local = await seedLocal();
  const intercity = await seedIntercity();
  console.log(JSON.stringify({ seeded: { local, intercity } }, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
