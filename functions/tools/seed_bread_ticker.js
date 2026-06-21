/**
 * Non (bread) moduli ekrani uchun begushchaya ticker matnlarini
 * `home_ticker_ads` collectioniga bir martalik qo'shadi (module: 'bread').
 *
 * Ishlatish (root'dan):
 *   node functions/tools/seed_bread_ticker.js
 *
 * Idempotent: agar matn allaqachon module='bread' bilan mavjud bo'lsa,
 * uni qayta qo'shmaydi (text bo'yicha tekshiradi).
 */
const path = require('path');
const admin = require('firebase-admin');

const serviceAccount = require(path.join(__dirname, '..', 'service-account.json'));

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();

const TEXTS = [
  '💍 Тўй учун патирлар қабул қилинмоқда',
  '🎉 100–1000 дона Нон буюртма қилишингиз мумкин',
  '👰🤵 Тўй дастурхони учун махсус безакли Нонлар',
  '🎊 Маросимлар учун катта ҳажмли буюртмалар қабул қилинмоқда',
  '🥖 Тўй маросим нонларини 3-4 кун олдин буюртма бериб қўйинг',
  '📅 Тўй санасини белгиланг, нонларга олдиндан буюртма беринг',
  '🚚 Тўй манзилига тўғридан-тўғри етказиб бериш хизмати',
  '🎁 300 донадан ортиқ буюртмалар учун махсус нарх',
  '💒 Никоҳ, хатна, зиёфат ва бошқа тадбирлар учун махсус нонлар',
  '📦 Корпоратив ва оммавий тадбирлар учун катта буюртмалар қабул қилинади',
  '🥟 Иссиқ сомсалар ҳозир тайёр. Буюртмангизга қўшиб оласизми?',
  '🍕 Янги пиширилган пиццалар сотувда.',
  '🧀 Хачапурининг янги партияси тайёр бўлди.',
  '🌽 Зоғора нонлар ҳозиргина тандирдан чиқди.',
  '🎃 Қовоқли нонларни татиб кўришни тавсия қиламиз.',
  '🥖 Кунжутли патирлар бугунги энг машҳур маҳсулот.',
  '🥩 Гўштли нонларни синаб кўрганмисиз? Ҳозир иссиқ ҳолда мавжуд.',
  '🔥 Буюртмангизга яна 1 та сомса қўшинг.',
  '🥟 Мижозлар патир билан бирга кўпинча сомса ҳам сотиб олишади.',
  '🍕 Бугунги махсус таклиф: янги иссиқ Пицца.',
  '🧀 Янги хачапури рецептини биринчи бўлиб синаб кўринг.',
  '🌽 Зоғора ноннинг янги партияси сотувга чиқди.',
  '🎃 Қовоқли нонлар мавсуми бошланди.',
  '🥩 Гўштли нонлар тугашидан олдин буюртма беринг.',
  '👨‍🍳 Уста ошпаз тавсияси: Кунжутли нон ва сомса.',
  '🎁 Бугунги дегустация маҳсулоти: Қовоқли нон.',
  '🔥 Сўнгги 1 соатда 42 та мижоз гўштли нон буюртма қилди.',
  '🥟 Ҳозирги энг харидоргир маҳсулот — иссиқ сомса.',
  '🧀 Хачапурини татиб кўринг — мижозлар баҳоси 4.9/5.',
  '🌅 Нонушта учун: Зоғора нон + қаймоқ',
  '☀️ Тушлик учун: Сомса ва чой',
  '🌆 Кечки овқат учун: Пицца ёки гўштли нон',
  '🌙 Кечки чой учун: Қовоқли нон + сомса',
];

async function main() {
  const col = db.collection('home_ticker_ads');

  // Mavjud bread ticker matnlarini olib, duplikat qo'shmaslik uchun.
  const existingSnap = await col.where('module', '==', 'bread').get();
  const existingTexts = new Set(existingSnap.docs.map((d) => (d.data().text || '').trim()));

  let added = 0;
  let skipped = 0;
  const batch = db.batch();

  TEXTS.forEach((text, i) => {
    const trimmed = text.trim();
    if (existingTexts.has(trimmed)) {
      skipped++;
      return;
    }
    const ref = col.doc();
    batch.set(ref, {
      text: trimmed,
      audience: 'all',
      module: 'bread',
      active: true,
      priority: 0,
      durationSec: 4,
      scrollSpeed: 45,
      animationStyle: 'auto',
      fontSize: 13,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    added++;
  });

  if (added === 0) {
    console.log('Барча матнлар аллақачон мавжуд — қўшиладиган нарса йўқ.');
    return;
  }

  await batch.commit();
  console.log(`Қўшилди: ${added} та матн. Ўтказиб юборилди (дублика): ${skipped} та.`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('Хатолик:', e);
    process.exit(1);
  });
