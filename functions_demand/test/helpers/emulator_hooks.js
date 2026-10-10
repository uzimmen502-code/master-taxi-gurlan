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

function wrapQuery(q, onGet) {
  return new Proxy(q, {
    get(t, p) {
      if (p === 'get') {
        return async (...a) => { const s = await t.get(...a); await onGet(); return s; };
      }
      if (['where', 'limit', 'orderBy'].includes(p)) return (...a) => wrapQuery(t[p](...a), onGet);
      const v = t[p];
      return typeof v === 'function' ? v.bind(t) : v;
    },
  });
}

/**
 * POYGA: tanlangan kolleksiyadagi SO'ROV (`where`/`limit` → `get`) natijasi
 * qaytgandan KEYIN, chaqiruvchi uni ishlatishidan OLDIN `hook` bir marta.
 */
function dbWithQueryHook(db, collectionName, hook) {
  let fired = false;
  const once = async () => { if (!fired) { fired = true; await hook(); } };
  return new Proxy(db, {
    get(target, prop) {
      if (prop !== 'collection') {
        const v = target[prop];
        return typeof v === 'function' ? v.bind(target) : v;
      }
      return (name) => {
        const col = target.collection(name);
        if (name !== collectionName) return col;
        return new Proxy(col, {
          get(c, p) {
            if (p === 'where' || p === 'limit') return (...a) => wrapQuery(c[p](...a), once);
            const v = c[p];
            return typeof v === 'function' ? v.bind(c) : v;
          },
        });
      };
    },
  });
}

/**
 * POYGA: BIR MARTA `hook` — qaysi biri OLDIN bo'lsa:
 *   - `queryOn` kolleksiyasidagi so'rov natijasi qaytgandan keyin, yoki
 *   - `updateOn` kolleksiyasi hujjatiga `ref.update(...)` dan OLDIN.
 * `updateOn` hujjat havolasi haqiqiy ref'ning Proxy'si — tranzaksiyaga
 * (`tx.get(ref)`) ham beriladi.
 */
function dbWithHooks(db, { queryOn, updateOn }, hook) {
  let fired = false;
  const once = async () => { if (!fired) { fired = true; await hook(); } };
  return new Proxy(db, {
    get(target, prop) {
      if (prop !== 'collection') {
        const v = target[prop];
        return typeof v === 'function' ? v.bind(target) : v;
      }
      return (name) => {
        const col = target.collection(name);
        if (name !== queryOn && name !== updateOn) return col;
        return new Proxy(col, {
          get(c, p) {
            if (name === queryOn && (p === 'where' || p === 'limit')) return (...a) => wrapQuery(c[p](...a), once);
            if (name === updateOn && p === 'doc') {
              return (...a) => new Proxy(c.doc(...a), {
                get(r, rp) {
                  if (rp === 'update') return async (...u) => { await once(); return r.update(...u); };
                  const v = r[rp];
                  return typeof v === 'function' ? v.bind(r) : v;
                },
              });
            }
            const v = c[p];
            return typeof v === 'function' ? v.bind(c) : v;
          },
        });
      };
    },
  });
}

module.exports = { resetEmulator, dbWithHook, dbWithQueryHook, dbWithHooks };
