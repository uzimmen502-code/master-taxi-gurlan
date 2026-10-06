/**
 * MINIMAL FIRESTORE FAKE — yadro testlari uchun.
 *
 * Nega emulator emas: emulator har testda ~8 soniya ko'tariladi va CI'da
 * Java talab qiladi. Yadroning mantiqi (dedupe, filtr, score, proyeksiya)
 * Firestore'ning o'ziga emas, FAQAT so'rov natijasiga bog'liq — shuning
 * uchun fake yetarli va tez.
 *
 * Qoidalar bo'yicha testlar (`rules.test.js`) ALOHIDA va u haqiqiy
 * emulator talab qiladi: qoidalarni fake bilan sinab bo'lmaydi.
 *
 * Qo'llaydi: collection().doc().get()/set()/update(), where(==, >=,
 * array-contains, array-contains-any, in), limit(), count(), batch(),
 * getAll(), subkolleksiya.
 */

/**
 * Firestore auto-ID — HAQIQIY shaklda: 20 belgi, faqat harf va raqam.
 *
 * DIQQAT: bu ahamiyatsiz tafsilot EMAS. Avval fake `auto_xxx` shaklida
 * ID yasagandi va `_` sababli `matchKey` butun matching'ni yiqitgan edi
 * (`demandId composite kalit uchun xavfsiz emas`). Ya'ni noto'g'ri fake
 * mavjud bo'lmagan nosozlikni ko'rsatdi. Firestore'ning o'zi `_` ishlatmaydi.
 */
const AUTO_ID_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
let autoIdSeq = 0;
function autoId() {
  autoIdSeq += 1;
  let s = '';
  for (let i = 0; i < 16; i += 1) {
    s += AUTO_ID_CHARS[Math.floor(Math.random() * AUTO_ID_CHARS.length)];
  }
  // Ketma-ketlik raqami — testlarda takrorlanmasligi kafolati.
  return `${s}${String(autoIdSeq).padStart(4, '0')}`;
}

/** Oddiy obyekt (map) mi — Date va massiv EMAS. */
function isPlainObject(v) {
  return v !== null && typeof v === 'object'
    && !Array.isArray(v) && !(v instanceof Date)
    && typeof v.toMillis !== 'function';
}

/**
 * `set(..., { merge: true })` — ICHKI MAP'LARNI HAM birlashtiradi.
 *
 * DIQQAT: bu ahamiyatsiz tafsilot EMAS. Avval fake sayoz spread
 * (`{...prev, ...next}`) qilardi, ya'ni
 * `set({status: {courier: 'trial'}}, {merge: true})` butun `status`
 * map'ini ALMASHTIRARDI va `status.taxi` yo'qolardi. Haqiqiy Firestore
 * esa map'larni rekursiv birlashtiradi.
 *
 * Capability modeli (D-13) aynan shunga tayanadi: bitta hujjatda bir
 * nechta xizmat yonma-yon yashaydi va bittasini yozish qolganlarini
 * o'chirmasligi kerak. Sayoz fake bilan test «o'tib» ketardi, lekin
 * production'da kuryerni yozish taksi capability'sini yo'q qilardi.
 *
 * Massiv va Date — Firestore'da ham BUTUNLAY almashtiriladi.
 */
function deepMergeInto(prev, next) {
  const out = deepClone(prev);
  for (const [k, v] of Object.entries(next)) {
    if (isPlainObject(v) && isPlainObject(out[k])) {
      out[k] = deepMergeInto(out[k], v);
    } else {
      out[k] = deepClone(v);
    }
  }
  return out;
}

function deepClone(v) {
  if (v === null || typeof v !== 'object') return v;
  if (v instanceof Date) return new Date(v.getTime());
  if (Array.isArray(v)) return v.map(deepClone);
  const out = {};
  for (const [k, val] of Object.entries(v)) out[k] = deepClone(val);
  return out;
}

/** `a.b.c` yo'li bo'yicha qiymat. */
function getPath(obj, path) {
  let cur = obj;
  for (const part of String(path).split('.')) {
    if (cur === null || cur === undefined) return undefined;
    cur = cur[part];
  }
  return cur;
}

function setPath(obj, path, value) {
  const parts = String(path).split('.');
  let cur = obj;
  for (let i = 0; i < parts.length - 1; i += 1) {
    if (typeof cur[parts[i]] !== 'object' || cur[parts[i]] === null) cur[parts[i]] = {};
    cur = cur[parts[i]];
  }
  cur[parts[parts.length - 1]] = value;
}

function toMs(v) {
  if (v instanceof Date) return v.getTime();
  if (v && typeof v.toMillis === 'function') return v.toMillis();
  return Number(v) || 0;
}

function compare(left, op, right) {
  switch (op) {
    case '==': return left === right;
    case '!=': return left !== right;
    case '>=': return (left instanceof Date || right instanceof Date)
      ? toMs(left) >= toMs(right) : left >= right;
    case '<=': return (left instanceof Date || right instanceof Date)
      ? toMs(left) <= toMs(right) : left <= right;
    case '>': return (left instanceof Date || right instanceof Date)
      ? toMs(left) > toMs(right) : left > right;
    case '<': return (left instanceof Date || right instanceof Date)
      ? toMs(left) < toMs(right) : left < right;
    case 'array-contains': return Array.isArray(left) && left.includes(right);
    case 'array-contains-any':
      return Array.isArray(left) && Array.isArray(right)
        && left.some((x) => right.includes(x));
    case 'in': return Array.isArray(right) && right.includes(left);
    default: throw new Error(`fake: «${op}» operatori qo'llanmaydi`);
  }
}

class FakeFirestore {
  constructor(seed = {}) {
    /** @type {Map<string, object>} «collection/doc» -> ma'lumot */
    this.docs = new Map();
    this.reads = 0;
    this.writes = 0;
    for (const [path, data] of Object.entries(seed)) {
      this.docs.set(path, deepClone(data));
    }
  }

  collection(name) { return new FakeCollection(this, name); }

  async getAll(...refs) {
    this.reads += refs.length;
    return refs.map((r) => {
      const data = this.docs.get(r.path);
      return {
        id: r.id,
        exists: data !== undefined,
        data: () => deepClone(data),
        ref: r,
      };
    });
  }

  batch() {
    const ops = [];
    const self = this;
    return {
      set(ref, data, opts) { ops.push({ kind: 'set', ref, data, opts }); return this; },
      update(ref, data) { ops.push({ kind: 'update', ref, data }); return this; },
      delete(ref) { ops.push({ kind: 'delete', ref }); return this; },
      async commit() {
        if (ops.length > 500) throw new Error('fake: batch 500 dan ortiq operatsiya');
        for (const op of ops) {
          if (op.kind === 'set') await op.ref.set(op.data, op.opts);
          else if (op.kind === 'update') await op.ref.update(op.data);
          else self.docs.delete(op.ref.path);
        }
        return ops.length;
      },
    };
  }

  /** Test yordamchisi: kolleksiyadagi hamma hujjat. */
  dump(collectionName) {
    const out = {};
    for (const [path, data] of this.docs) {
      const prefix = `${collectionName}/`;
      if (path.startsWith(prefix) && !path.slice(prefix.length).includes('/')) {
        out[path.slice(prefix.length)] = deepClone(data);
      }
    }
    return out;
  }
}

class FakeCollection {
  constructor(store, name) {
    this.store = store;
    this.name = name;
    this.filters = [];
    this.limitN = null;
  }

  doc(id) {
    const docId = id || autoId();
    return new FakeDoc(this.store, `${this.name}/${docId}`, docId);
  }

  where(field, op, value) {
    const next = new FakeCollection(this.store, this.name);
    next.filters = [...this.filters, { field, op, value }];
    next.limitN = this.limitN;
    return next;
  }

  orderBy() { return this; }

  limit(n) {
    const next = new FakeCollection(this.store, this.name);
    next.filters = this.filters;
    next.limitN = n;
    return next;
  }

  _matchingDocs() {
    const out = [];
    const prefix = `${this.name}/`;
    for (const [path, data] of this.store.docs) {
      if (!path.startsWith(prefix)) continue;
      // Faqat shu kolleksiyaning bevosita hujjatlari (subkolleksiya emas).
      if (path.slice(prefix.length).includes('/')) continue;
      let ok = true;
      for (const f of this.filters) {
        if (!compare(getPath(data, f.field), f.op, f.value)) { ok = false; break; }
      }
      if (!ok) continue;
      const id = path.slice(prefix.length);
      out.push({
        id,
        exists: true,
        data: () => deepClone(data),
        ref: new FakeDoc(this.store, path, id),
      });
      if (this.limitN && out.length >= this.limitN) break;
    }
    return out;
  }

  async get() {
    const docs = this._matchingDocs();
    this.store.reads += docs.length;
    return { docs, size: docs.length, empty: docs.length === 0 };
  }

  count() {
    const self = this;
    return {
      async get() {
        const n = self._matchingDocs().length;
        self.store.reads += 1;
        return { data: () => ({ count: n }) };
      },
    };
  }

  async add(data) {
    const ref = this.doc();
    await ref.set(data);
    return ref;
  }
}

class FakeDoc {
  constructor(store, path, id) {
    this.store = store;
    this.path = path;
    this.id = id;
  }

  collection(name) { return new FakeCollection(this.store, `${this.path}/${name}`); }

  async get() {
    this.store.reads += 1;
    const data = this.store.docs.get(this.path);
    return {
      id: this.id,
      exists: data !== undefined,
      data: () => deepClone(data),
      ref: this,
    };
  }

  async set(data, opts) {
    this.store.writes += 1;
    if (opts && opts.merge) {
      const prev = this.store.docs.get(this.path) || {};
      this.store.docs.set(this.path, deepMergeInto(prev, data));
    } else {
      this.store.docs.set(this.path, deepClone(data));
    }
    return { writeTime: new Date() };
  }

  async update(data) {
    this.store.writes += 1;
    const prev = this.store.docs.get(this.path);
    if (prev === undefined) {
      const e = new Error(`fake: hujjat yo'q — ${this.path}`);
      e.code = 5;
      throw e;
    }
    const next = deepClone(prev);
    for (const [k, v] of Object.entries(data)) setPath(next, k, deepClone(v));
    this.store.docs.set(this.path, next);
    return { writeTime: new Date() };
  }

  async delete() {
    this.store.writes += 1;
    this.store.docs.delete(this.path);
  }
}

module.exports = {
  FakeFirestore, deepClone, deepMergeInto, getPath, compare, autoId,
};
