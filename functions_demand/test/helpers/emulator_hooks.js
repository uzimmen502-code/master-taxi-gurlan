/**
 * Emulator testlari uchun umumiy yordamchilar (Admin SDK, haqiqiy tranzaksiya).
 *
 *   - resetEmulator: loyiha hujjatlarini butunlay o'chiradi va seed yozadi
 *   - dbWithHook: POYGA testlari — tanlangan kolleksiya hujjati `.get()` bilan
 *     o'qilganda BIR MARTA `hook`ni ishga tushiradi (ikki chaqiruv orasiga
 *     boshqa chaqiruvni aniq joyga qo'yish uchun; tasodifiy taymingsiz)
 */
'use strict';

async function resetEmulator(db, seedDocs) {
  const url = `http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/`
    + `${process.env.GCLOUD_PROJECT}/databases/(default)/documents`;
  const res = await fetch(url, { method: 'DELETE' });
  if (!res.ok) throw new Error(`emulator tozalanmadi: ${res.status}`);
  await Promise.all(Object.entries(seedDocs).map(([p, d]) => db.doc(p).set(d)));
}

function dbWithHook(db, collectionName, hook) {
  let fired = false;
  return new Proxy(db, {
    get(target, prop) {
      if (prop !== 'collection') {
        const v = target[prop];
        return typeof v === 'function' ? v.bind(target) : v;
      }
      return (name) => {
        const col = target.collection(name);
        if (name !== collectionName) return col;
        return {
          doc: (id) => {
            const ref = col.doc(id);
            return {
              id: ref.id,
              get: async () => {
                if (!fired) { fired = true; await hook(); }
                return ref.get();
              },
            };
          },
        };
      };
    },
  });
}

module.exports = { resetEmulator, dbWithHook };
