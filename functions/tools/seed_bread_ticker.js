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
  '💍 Тўй учун па­тир­лар қабул қи­лин­моқ­да',
  '🎉 100–1000 дона Нон буюртма қи­ли­шин­гиз мумкин',
  '👰🤵 Тўй дас­тур­хо­ни учун махсус безакли Нонлар',
  '🎊 Ма­ро­сим­лар учун катта ҳажмли буюр­тма­лар қабул қи­лин­моқ­да',
  '🥖 Тўй маросим нон­ла­ри­ни 3-4 кун олдин буюртма бериб қўйинг',
  '📅 Тўй са­на­си­ни бел­ги­ланг, нон­лар­га ол­дин­дан буюртма беринг',
  '🚚 Тўй ман­зи­ли­га тўғ­ри­дан-тўғри етказиб бериш хизмати',
  '🎁 300 донадан ортиқ буюр­тма­лар учун махсус нарх',
  '💒 Никоҳ, хатна, зиёфат ва бошқа тад­бир­лар учун махсус нонлар',
  '📦 Кор­по­ра­тив ва оммавий тад­бир­лар учун катта буюр­тма­лар қабул қи­ли­на­ди',
  '🥟 Иссиқ сом­са­лар ҳозир тайёр. Буюр­тман­гиз­га қўшиб ола­сиз­ми?',
  '🍕 Янги пи­ши­рил­ган пиц­ца­лар сотувда.',
  '🧀 Ха­ча­пу­ри­нинг янги пар­тия­си тайёр бўлди.',
  '🌽 Зоғора нонлар ҳо­зир­ги­на тан­дир­дан чиқди.',
  '🎃 Қовоқли нон­лар­ни татиб кўришни тавсия қиламиз.',
  '🥖 Кун­жут­ли па­тир­лар бугунги энг машҳур маҳ­су­лот.',
  '🥩 Гўштли нон­лар­ни синаб кўр­ган­ми­сиз? Ҳозир иссиқ ҳолда мавжуд.',
  '🔥 Буюр­тман­гиз­га яна 1 та сомса қўшинг.',
  '🥟 Ми­жоз­лар патир билан бирга кўпинча сомса ҳам сотиб олишади.',
  '🍕 Бугунги махсус таклиф: янги иссиқ Пицца.',
  '🧀 Янги ха­ча­пу­ри ре­цеп­ти­ни биринчи бўлиб синаб кўринг.',
  '🌽 Зоғора ноннинг янги пар­тия­си сотувга чиқди.',
  '🎃 Қовоқли нонлар мавсуми бош­лан­ди.',
  '🥩 Гўштли нонлар ту­га­ши­дан олдин буюртма беринг.',
  '👨‍🍳 Уста ошпаз тав­сия­си: Кун­жут­ли нон ва сомса.',
  '🎁 Бугунги де­гус­та­ция маҳ­су­ло­ти: Қовоқли нон.',
  '🔥 Сўнгги 1 соатда 42 та мижоз гўштли нон буюртма қилди.',
  '🥟 Ҳозирги энг ха­ри­дор­гир маҳ­су­лот — иссиқ сомса.',
  '🧀 Ха­ча­пу­ри­ни татиб кўринг — ми­жоз­лар баҳоси 4.9/5.',
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

module.exports.TEXTS = TEXTS;

if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((e) => {
      console.error('Хатолик:', e);
      process.exit(1);
    });
}
