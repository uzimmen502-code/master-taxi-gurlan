/**
 * ҲИСОБНИ АВТОМАТИК ЎЧИРИШ — сўров, бекор қилиш, режали ижро
 * (docs/hisobni_ochirish_2026-10-24_uz.md; эга қарорлари 2026-10-24).
 *
 * Ҳолатлар (`account_deletions/{uid12}` — ЖОРИЙ ҳолат; клиент ёзмайди, rules'да ёпиқ):
 *   PENDING (кутиш, scheduledFor) → EXECUTING → DONE
 *   PENDING|POSTPONED|FAILED → CANCELLED (фойдаланувчи бекор қилди)
 *   PENDING → POSTPONED (ижро пайтида блок чиқди) → яна PENDING сифатида олинади
 *   EXECUTING → FAILED (5 уринишдан кейин, админ кўради)
 * Ҳар ўтиш `account_deletions/{uid}/events`га ёзилади (16-банд); DONE нусхаси
 * `account_deletion_history/{uid}_{ms}` га тушади (қайта рўйхатдан ўтилса жорий ҳужжат янгиланади).
 *
 * Дарвоза: `settings/account_deletion` { enabled: true, waitDays: 10 }. Йўқ/enabled≠true → ЁПИҚ (fail-closed).
 *
 * Ижро қадамлари — идемпотент, ҳар бири `steps.{name}.done` билан белгиланади, узилишдан кейин давом этади.
 * Бу босқичда: ҳамён сўндирилади, қурилма/Telegram боғланишлари, шахсий ости-коллекциялар, танишувнинг ЎЗ
 * томони (матчлар ва чат ЎЧМАЙДИ — эга қарори), `users` қобиққа айлантирилади, Firebase Auth ўчирилади.
 * КЕЙИНГИ босқич (A1 таҳлили): очиқ контентни яшириш/ўчириш, буюртма ва сафарлардан шахсий майдонларни олиш.
 *
 * Хавфсизлик: блок текшируви сўровда ВА ижрода; текширув аниқ эмас бўлса — блок (`account_deletion_core`).
 * Диагностика кодлари: ACCOUNT_DELETION_DISABLED, ACCOUNT_DELETION_BLOCKED, ACCOUNT_NOT_FOUND,
 * ACCOUNT_DELETION_NOT_PENDING, ACCOUNT_DELETION_IN_PROGRESS.
 */
'use strict';

const core = require('./account_deletion_core');
const settlementLedger = require('./settlement_ledger');
const { createHider } = require('./account_deletion_hide');
const { createContentSteps } = require('./account_deletion_content');

const COL = 'account_deletions';
const HISTORY = 'account_deletion_history';
const CONFIG_PATH = ['settings', 'account_deletion'];
const DEFAULT_WAIT_DAYS = 10;
const MAX_ATTEMPTS = 5;
const LEASE_MS = 15 * 60 * 1000;
const POSTPONE_MS = 24 * 60 * 60 * 1000;
const RETRY_MS = 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

const ACTIVE_STATES = Object.freeze(['PENDING', 'POSTPONED', 'EXECUTING']);

/** `users/{id}` ости-коллекциялари: ШАХСИЙ маълумот, ўчирилади. wallet_ledger ва *_claims ЎЧИРИЛМАЙДИ (молия/идемпотентлик). */
const USER_SUBCOLLECTIONS = Object.freeze([
  'vehicles', 'driverProfiles', 'saved_tv_clips', 'marshrut_state', 'marshrut_block', 'local_taxi_block',
  'dismissed_news', 'relative_join_alerts', 'realty_places', 'realty_prefs', 'realty_matches',
  'realty_alert_meta', 'realty_unlocked', 'assistant_conversations', 'assistant_memory', 'assistant_usage',
  'assistant_packages', 'fcm_tokens',
]);

const clampDays = (v) => {
  const n = Math.trunc(Number(v));
  if (!Number.isFinite(n) || n < 1) return DEFAULT_WAIT_DAYS;
  return Math.min(n, 60);
};

/** Клиентга кўринадиган блок: код ва гуруҳ, ҳужжат ID лари йўқ. */
const publicBlockers = (list) => list.map((b) => ({ code: b.code, area: b.area, count: b.count }));

/**
 * Сервис ясовчи (тест учун: `db`, `auth`, вақт ва ташқи эффектлар киритилади).
 * deps: { db, admin, auth, now?, deleteStoragePrefix?, deleteStoragePath?, hiders?, log? }
 */
function createAccountDeletion(deps) {
  const { db, admin, auth } = deps;
  const now = deps.now || (() => Date.now());
  const hiders = deps.hiders || [];
  const log = deps.log || ((o) => console.log(JSON.stringify({ module: 'account_deletion', ...o })));
  const FV = admin.firestore.FieldValue;
  const TS = admin.firestore.Timestamp;
  const ts = () => FV.serverTimestamp();
  const at = (ms) => TS.fromMillis(ms);
  const fail = (code, message, extra) => Object.assign(new Error(message || code), { code, extra: extra || {} });

  /**
   * `allow` — ИЧКИ синов рўйхати (42-банд INTERNAL): бўш бўлмаса, фақат шу телефонлар (12 хонали) сўров юбора олади.
   * Бўш/йўқ — ҳамма (PUBLIC). Мавжуд сўровларнинг ижроси рўйхатга қарамайди.
   */
  async function readConfig() {
    const snap = await db.collection(CONFIG_PATH[0]).doc(CONFIG_PATH[1]).get();
    const d = snap.exists ? (snap.data() || {}) : {};
    const allow = Array.isArray(d.allow)
      ? [...new Set(d.allow
        .map((x) => String(x == null ? '' : x).replace(/\D/g, ''))
        .filter((x) => x.length >= 9)
        .map((x) => (x.length === 9 ? `998${x}` : x)))]
      : [];
    return { enabled: d.enabled === true, waitDays: clampDays(d.waitDays), allow };
  }

  const allowedFor = (cfg, uid) => cfg.enabled && (cfg.allow.length === 0 || cfg.allow.includes(uid));

  const stateRef = (uid) => db.collection(COL).doc(uid);

  function eventIn(t, uid, type, meta = {}) {
    t.set(stateRef(uid).collection('events').doc(), { type, at: ts(), ...meta });
  }

  async function walletOf(identity) {
    let amount = 0;
    for (const id of identity.userDocIds) {
      const s = await db.collection('users').doc(id).get();
      const b = parseInt(String(((s.data() || {}).bonusBalance) ?? 0), 10) || 0;
      if (b > 0) amount += b;
    }
    return amount;
  }

  /** Пулли хизматлар (қолган қисми ўчиришда сўндирилади — эга қарори, огоҳлантириш билан). */
  async function paidServicesOf(identity) {
    const out = [];
    const nowMs = now();
    const toMs = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : (typeof v === 'number' ? v : 0));
    for (const id of identity.userDocIds) {
      const u = (await db.collection('users').doc(id).get()).data() || {};
      if (toMs((u.realtyPro || {}).expiresAt) > nowMs && !out.includes('realty_pro')) out.push('realty_pro');
      if (Number(u.realtyUnlocksLeft || 0) > 0 && !out.includes('realty_unlocks')) out.push('realty_unlocks');
      if (toMs(u.assistantPaidUntil) > nowMs && !out.includes('assistant_package')) out.push('assistant_package');
    }
    return out;
  }

  // ───────────────────────── Кўриш (ёзмайди) ─────────────────────────

  async function preview(uid) {
    const cfg = await readConfig();
    const identity = await core.resolveIdentity(db, uid);
    const cur = await stateRef(identity.d12).get();
    const state = cur.exists ? cur.data() : null;
    const blockers = identity.userDocIds.length === 0 ? [] : await core.findBlockers(db, identity);
    return {
      enabled: allowedFor(cfg, identity.d12),
      waitDays: cfg.waitDays,
      exists: identity.userDocIds.length > 0,
      blockers: publicBlockers(blockers),
      walletAmount: await walletOf(identity),
      paidServices: await paidServicesOf(identity),
      state: state ? {
        status: state.status,
        scheduledForMs: state.scheduledFor && state.scheduledFor.toMillis ? state.scheduledFor.toMillis() : null,
      } : null,
    };
  }

  // ───────────────────────── Сўров ─────────────────────────

  async function request(uid, { source = 'app', audit = null } = {}) {
    const cfg = await readConfig();
    const identity = await core.resolveIdentity(db, uid);
    if (!allowedFor(cfg, identity.d12)) throw fail('ACCOUNT_DELETION_DISABLED', 'Ҳисобни ўчириш ҳозирча мавжуд эмас.');
    if (identity.userDocIds.length === 0) throw fail('ACCOUNT_NOT_FOUND', 'Ҳисоб топилмади.');
    const blockers = await core.findBlockers(db, identity);
    if (blockers.length > 0) {
      throw fail('ACCOUNT_DELETION_BLOCKED', 'Ҳисобни ҳозир ўчириб бўлмайди.', { blockers: publicBlockers(blockers) });
    }
    const wallet = await walletOf(identity);
    const nowMs = now();
    const scheduledMs = nowMs + cfg.waitDays * DAY_MS;
    const ref = stateRef(identity.d12);
    let duplicate = null;
    await db.runTransaction(async (t) => {
      duplicate = null;
      const snap = await t.get(ref);
      const userSnaps = [];
      for (const id of identity.userDocIds) userSnaps.push(await t.get(db.collection('users').doc(id)));
      if (snap.exists && ACTIVE_STATES.includes((snap.data() || {}).status)) {
        duplicate = snap.data();
        return;
      }
      t.set(ref, {
        uid: identity.d12,
        status: 'PENDING',
        requestedAt: ts(),
        scheduledFor: at(scheduledMs),
        waitDays: cfg.waitDays,
        source,
        userDocIds: identity.userDocIds,
        attempts: 0,
        steps: {},
        walletAtRequest: wallet,
        updatedAt: ts(),
      });
      eventIn(t, identity.d12, 'requested', { source, waitDays: cfg.waitDays, walletAtRequest: wallet });
      if (audit) t.create(db.collection('admin_audit').doc(), { ...audit, targetId: identity.d12, at: ts() });
      for (const s of userSnaps) {
        if (!s.exists) continue; // арвоҳ ҳужжат яратмаймиз
        t.update(s.ref, { deletion: { status: 'PENDING', requestedAt: ts(), scheduledFor: at(scheduledMs) } });
      }
    });
    if (duplicate) {
      const d = duplicate;
      return {
        ok: true, duplicate: true, status: d.status,
        scheduledForMs: d.scheduledFor && d.scheduledFor.toMillis ? d.scheduledFor.toMillis() : null,
      };
    }
    const hide = await runHiders('hide', identity);
    if (hide.failed.length > 0) await ref.update({ hidePending: true, updatedAt: ts() });
    log({ action: 'request', result: 'ok', userId: identity.d12, source, waitDays: cfg.waitDays });
    return { ok: true, duplicate: false, status: 'PENDING', scheduledForMs: scheduledMs };
  }

  // ───────────────────────── Бекор қилиш ─────────────────────────

  async function cancel(uid, { audit = null } = {}) {
    const identity = await core.resolveIdentity(db, uid);
    const ref = stateRef(identity.d12);
    let result = null;
    await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) throw fail('ACCOUNT_DELETION_NOT_PENDING', 'Ўчириш сўрови йўқ.');
      const st = (snap.data() || {}).status;
      if (st === 'EXECUTING') throw fail('ACCOUNT_DELETION_IN_PROGRESS', 'Ўчириш бошланган, бекор қилиб бўлмайди.');
      if (!['PENDING', 'POSTPONED', 'FAILED'].includes(st)) {
        throw fail('ACCOUNT_DELETION_NOT_PENDING', 'Ўчириш сўрови йўқ.');
      }
      const userSnaps = [];
      for (const id of identity.userDocIds) userSnaps.push(await t.get(db.collection('users').doc(id)));
      t.update(ref, { status: 'CANCELLED', cancelledAt: ts(), updatedAt: ts() });
      eventIn(t, identity.d12, 'cancelled', { from: st, ...(audit ? { by: audit.actor } : {}) });
      if (audit) t.create(db.collection('admin_audit').doc(), { ...audit, targetId: identity.d12, at: ts() });
      for (const s of userSnaps) if (s.exists) t.update(s.ref, { deletion: FV.delete() });
      result = { ok: true, status: 'CANCELLED' };
    });
    await runHiders('unhide', identity);
    log({ action: 'cancel', result: 'ok', userId: identity.d12 });
    return result;
  }

  // ───────────────────────── Яшириш/қайтариш (A1 таҳлилидан кейин тўлдирилади) ─────────────────────────

  async function runHiders(kind, identity) {
    const failed = [];
    for (const h of hiders) {
      try {
        await h[kind](identity, { db, admin });
      } catch (e) {
        failed.push(h.name);
        log({ action: kind, result: 'error', errorCode: 'HIDER_FAILED', hider: h.name, userId: identity.d12 });
      }
    }
    return { failed };
  }

  // ───────────────────────── Ижро қадамлари ─────────────────────────

  async function chunkedQueryDelete(col, field, values) {
    let n = 0;
    const vals = [...new Set(values)].filter(Boolean);
    for (let i = 0; i < vals.length; i += 10) {
      const part = vals.slice(i, i + 10);
      // eslint-disable-next-line no-constant-condition
      while (true) {
        const snap = await db.collection(col).where(field, 'in', part).limit(400).get();
        if (snap.empty) break;
        const b = db.batch();
        snap.docs.forEach((d) => b.delete(d.ref));
        await b.commit();
        n += snap.size;
        if (snap.size < 400) break;
      }
    }
    return n;
  }

  const contentSteps = createContentSteps({ db, admin, deleteStoragePrefix: deps.deleteStoragePrefix }).STEPS;

  const STEPS = [
    {
      name: 'forfeit_wallet',
      /** Ҳамён қолдиғи сўндирилади: ҳисоб дафтарига ёзув (passenger_credit == bonusBalance сақланади). */
      async run({ identity, uid }) {
        const forfeited = [];
        for (const id of identity.userDocIds) {
          const userRef = db.collection('users').doc(id);
          const out = await db.runTransaction(async (t) => {
            const snap = await t.get(userRef);
            if (!snap.exists) return { amount: 0 };
            const bal = parseInt(String(((snap.data() || {}).bonusBalance) ?? 0), 10) || 0;
            if (bal <= 0) return { amount: 0, skipped: bal < 0 ? 'negative' : 'zero' };
            const key = `acct_del_forfeit_${id}`;
            const bonusCtx = await settlementLedger.prepareBonusInTx(t, db, id, { idempotencyKey: key });
            if (bonusCtx.jExists) return { amount: 0, idempotent: true };
            t.set(userRef, { bonusBalance: 0, balanceUpdatedAt: ts() }, { merge: true });
            t.set(userRef.collection('wallet_ledger').doc(`account_deletion_${uid}`), {
              type: 'account_deletion_forfeit',
              amount: -bal,
              module: 'account',
              refType: 'account_deletion',
              refId: uid,
              meta: { forfeited: bal },
              createdAt: ts(),
              createdBy: 'system',
            });
            settlementLedger.commitBonusInTx(t, bonusCtx, {
              delta: -bal,
              kind: 'account_deletion_forfeit',
              refType: 'account_deletion',
              refId: uid,
              meta: { module: 'account', forfeited: bal },
              postedBy: 'system',
              postedRole: 'system',
            });
            return { amount: bal };
          });
          forfeited.push({ userDocId: id, ...out });
        }
        return { forfeited };
      },
    },
    {
      name: 'delete_device_and_links',
      async run({ identity }) {
        let devices = 0;
        for (const h of identity.deviceHashes) {
          await db.collection('device_bindings').doc(h).delete();
          devices += 1;
        }
        for (const id of [identity.d12, identity.d9]) {
          await db.collection('device_aliases').doc(id).delete();
          await db.collection('pending_codes').doc(id).delete();
        }
        const telegram = await chunkedQueryDelete('telegram_links', 'uid', identity.ids);
        return { devices, telegram };
      },
    },
    {
      name: 'delete_user_subcollections',
      async run({ identity }) {
        const names = [];
        for (const id of identity.userDocIds) {
          for (const sub of USER_SUBCOLLECTIONS) {
            await db.recursiveDelete(db.collection('users').doc(id).collection(sub));
            names.push(`${id}/${sub}`);
          }
        }
        return { collections: names.length };
      },
    },
    {
      name: 'dating_own_side',
      /**
       * Танишувнинг ЎЗ томони: профил, суратлар, қизиқишлар, блоклар. `dating_matches` ва хабарлар ЎЧМАЙДИ
       * (эга: «чат ўчмасин»). Мантиқ `deleteDatingProfile`дан олинган (у ўзгармайди), матчсиз.
       */
      async run({ identity }) {
        let interests = 0;
        for (const id of [identity.d12, identity.d9]) {
          const prof = await db.collection('dating_profiles').doc(id).get();
          if (prof.exists) {
            const paths = new Set(((prof.data() || {}).photos || [])
              .map((p) => String((p || {}).path || '').trim()).filter(Boolean));
            if (deps.deleteStoragePath) for (const p of paths) await deps.deleteStoragePath(p);
            if (deps.deleteStoragePrefix) await deps.deleteStoragePrefix(`dating/${id}/`);
          }
          await db.recursiveDelete(db.collection('dating_blocks').doc(id).collection('list'));
          await db.collection('dating_blocks').doc(id).delete();
          await db.collection('dating_profiles_public').doc(id).delete();
          await db.collection('dating_profiles').doc(id).delete();
        }
        interests += await chunkedQueryDelete('dating_interests', 'fromId', identity.ids);
        interests += await chunkedQueryDelete('dating_interests', 'toId', identity.ids);
        return { interests };
      },
    },
    ...contentSteps,
    {
      name: 'archive_wallet_ledger',
      /**
       * `users/{id}/wallet_ledger` (молиявий тарих, 3 йил сақланади) архивга КЎЧИРИЛАДИ ва фойдаланувчи йўлидан
       * олинади: рақам қайта берилса янги эга эски тўлов тарихини кўрмасин. Архив: `account_deletion_archive/{uid}/wallet_ledger`.
       * Идемпотент: аввал нусха (merge), кейин ўчириш.
       */
      async run({ identity, uid }) {
        let moved = 0;
        for (const id of identity.userDocIds) {
          const src = db.collection('users').doc(id).collection('wallet_ledger');
          // eslint-disable-next-line no-constant-condition
          while (true) {
            const snap = await src.limit(400).get();
            if (snap.empty) break;
            const b = db.batch();
            for (const d of snap.docs) {
              b.set(db.collection('account_deletion_archive').doc(uid).collection('wallet_ledger').doc(`${id}__${d.id}`),
                { ...d.data(), _archivedFrom: `users/${id}/wallet_ledger/${d.id}`, _archivedAt: ts() }, { merge: true });
              b.delete(d.ref);
            }
            await b.commit();
            moved += snap.size;
            if (snap.size < 400) break;
          }
        }
        return { moved };
      },
    },
    {
      name: 'user_shell',
      /** `users/{id}` ўчирилмайди: «ўчирилган» қобиқ (арвоҳ ҳужжатдан сақлайди; ҳужжат ID да телефон қолади). */
      async run({ identity }) {
        let shells = 0;
        for (const id of identity.userDocIds) {
          const ref = db.collection('users').doc(id);
          const snap = await ref.get();
          if (!snap.exists) continue;
          await ref.set({
            deleted: true,
            deletedAt: ts(),
            role: 'user',
            bonusBalance: 0,
            balanceUpdatedAt: ts(),
          });
          shells += 1;
        }
        return { shells };
      },
    },
    {
      name: 'auth_delete',
      async run({ identity }) {
        let removed = 0;
        try {
          const u = await auth.getUserByPhoneNumber(`+${identity.d12}`);
          await auth.deleteUser(u.uid);
          removed += 1;
        } catch (e) {
          if (!e || e.code !== 'auth/user-not-found') throw e;
        }
        return { removed };
      },
    },
  ];

  // ───────────────────────── Ижро ─────────────────────────

  /** @returns {Promise<{status:string, ...}>} */
  async function execute(uid) {
    const ref = stateRef(uid);
    const nowMs = now();
    let claimed = null;
    await db.runTransaction(async (t) => {
      claimed = null;
      const snap = await t.get(ref);
      if (!snap.exists) return;
      const d = snap.data() || {};
      const dueMs = d.scheduledFor && d.scheduledFor.toMillis ? d.scheduledFor.toMillis() : 0;
      const nextMs = d.nextCheckAt && d.nextCheckAt.toMillis ? d.nextCheckAt.toMillis() : 0;
      const leaseMs = d.leaseUntil && d.leaseUntil.toMillis ? d.leaseUntil.toMillis() : 0;
      const eligible = (d.status === 'PENDING' && dueMs <= nowMs)
        || (d.status === 'POSTPONED' && dueMs <= nowMs && nextMs <= nowMs)
        || (d.status === 'EXECUTING' && leaseMs <= nowMs);
      if (!eligible) return;
      const attempts = (Number(d.attempts) || 0) + 1;
      t.update(ref, {
        status: 'EXECUTING', attempts, leaseUntil: at(nowMs + LEASE_MS), startedAt: d.startedAt || ts(), updatedAt: ts(),
      });
      eventIn(t, uid, 'executing', { attempt: attempts });
      claimed = { ...d, attempts };
    });
    if (!claimed) return { status: 'SKIPPED' };

    try {
      const identity = await core.resolveIdentity(db, uid);
      if (identity.userDocIds.length === 0) {
        // ҳисоб аллақачон йўқ: тугатамиз (қобиқ ҳам йўқ бўлиши мумкин эмас, лекин хавфсиз)
        await finish(ref, uid, claimed, identity, { note: 'no_user_docs' });
        return { status: 'DONE' };
      }
      const blockers = await core.findBlockers(db, identity);
      if (blockers.length > 0) {
        await ref.update({
          status: 'POSTPONED', nextCheckAt: at(now() + POSTPONE_MS), lastBlockers: publicBlockers(blockers),
          leaseUntil: FV.delete(), updatedAt: ts(),
        });
        await ref.collection('events').add({ type: 'postponed', at: ts(), blockers: publicBlockers(blockers) });
        log({ action: 'execute', result: 'postponed', userId: uid, blockers: blockers.map((b) => b.code) });
        return { status: 'POSTPONED', blockers: publicBlockers(blockers) };
      }
      await runHiders('hide', identity);
      const steps = { ...(claimed.steps || {}) };
      for (const step of STEPS) {
        if (steps[step.name] && steps[step.name].done) continue;
        const started = now();
        const result = await step.run({ identity, uid });
        steps[step.name] = { done: true, atMs: now(), durationMs: now() - started, result };
        await ref.update({ [`steps.${step.name}`]: steps[step.name], leaseUntil: at(now() + LEASE_MS), updatedAt: ts() });
      }
      await finish(ref, uid, claimed, identity, {});
      log({ action: 'execute', result: 'done', userId: uid });
      return { status: 'DONE' };
    } catch (e) {
      const attempts = Number(claimed.attempts) || 1;
      const failedFinal = attempts >= MAX_ATTEMPTS;
      await ref.update({
        status: failedFinal ? 'FAILED' : 'POSTPONED',
        nextCheckAt: at(now() + RETRY_MS),
        lastError: String((e && e.message) || e).slice(0, 300),
        leaseUntil: FV.delete(),
        updatedAt: ts(),
      });
      await ref.collection('events').add({
        type: failedFinal ? 'failed' : 'step_error', at: ts(), attempt: attempts,
        error: String((e && e.message) || e).slice(0, 300),
      });
      log({ action: 'execute', result: 'error', errorCode: 'ACCOUNT_DELETION_STEP_FAILED', userId: uid, attempts });
      return { status: failedFinal ? 'FAILED' : 'POSTPONED', error: true };
    }
  }

  async function finish(ref, uid, claimed, identity, extra) {
    const doneMs = now();
    await ref.update({ status: 'DONE', completedAt: ts(), leaseUntil: FV.delete(), updatedAt: ts(), ...extra });
    await ref.collection('events').add({ type: 'done', at: ts() });
    const snap = await ref.get();
    await db.collection(HISTORY).doc(`${uid}_${doneMs}`).set({ ...(snap.data() || {}), archivedAt: ts() });
  }

  /** Муддати келганларни ишлатади (режали функция). */
  async function runDue({ limit = 20 } = {}) {
    const cfg = await readConfig();
    if (!cfg.enabled) return { processed: 0, skipped: 'disabled' };
    const nowTs = at(now());
    const out = [];
    const seen = new Set();
    for (const status of ['PENDING', 'POSTPONED', 'EXECUTING']) {
      const snap = await db.collection(COL).where('status', '==', status).limit(limit).get();
      for (const d of snap.docs) {
        if (seen.has(d.id)) continue;
        seen.add(d.id);
        const sf = d.data().scheduledFor;
        if (sf && sf.toMillis() > nowTs.toMillis()) continue;
        out.push({ uid: d.id, ...(await execute(d.id)) });
        if (out.length >= limit) break;
      }
      if (out.length >= limit) break;
    }
    return { processed: out.length, results: out };
  }

  // ───────────────────────── Админ (docs §8; 41-банд: ҳар амал сабаб билан аудитга) ─────────────────────────

  const ms = (v) => (v && typeof v.toMillis === 'function' ? v.toMillis() : null);
  const LIST_STATUSES = Object.freeze(['PENDING', 'POSTPONED', 'EXECUTING', 'FAILED', 'DONE', 'CANCELLED']);
  const DEFAULT_LIST = Object.freeze(['PENDING', 'POSTPONED', 'EXECUTING', 'FAILED']);
  const STATUS_ORDER = { FAILED: 0, POSTPONED: 1, EXECUTING: 2, PENDING: 3, DONE: 4, CANCELLED: 5 };

  const rowOf = (id, d) => ({
    uid: id,
    status: d.status || '',
    source: d.source || 'app',
    requestedAtMs: ms(d.requestedAt),
    scheduledForMs: ms(d.scheduledFor),
    nextCheckAtMs: ms(d.nextCheckAt),
    completedAtMs: ms(d.completedAt),
    attempts: Number(d.attempts) || 0,
    walletAtRequest: Number(d.walletAtRequest) || 0,
    hidePending: d.hidePending === true,
    lastError: d.lastError ? String(d.lastError).slice(0, 300) : '',
    lastBlockers: Array.isArray(d.lastBlockers)
      ? d.lastBlockers.map((b) => ({ code: String(b.code || ''), area: String(b.area || ''), count: Number(b.count) || 0 }))
      : [],
  });

  /** Сўровлар рўйхати (индекссиз: `status in [...]`, хотирада тартибланади). Фақат ўқийди. */
  async function adminList({ statuses, limit = 100 } = {}) {
    let st = Array.isArray(statuses) && statuses.length > 0 ? statuses.map(String) : [...DEFAULT_LIST];
    st = [...new Set(st)];
    if (st.some((s) => !LIST_STATUSES.includes(s))) throw fail('INVALID_STATUS', 'Ҳолат нотўғри.');
    const lim = Math.max(1, Math.min(200, Math.trunc(Number(limit)) || 100));
    const snap = await db.collection(COL).where('status', 'in', st).limit(lim).get();
    const rows = snap.docs.map((d) => rowOf(d.id, d.data() || {}));
    rows.sort((a, b) => (STATUS_ORDER[a.status] - STATUS_ORDER[b.status])
      || ((b.requestedAtMs || 0) - (a.requestedAtMs || 0)));
    return { rows, truncated: snap.size >= lim };
  }

  /** Тафсилот: ҳолат + қадамлар + охирги 50 воқеа + яширилганлар сони. */
  async function adminDetail(uid) {
    const id = core.phoneForms(uid).d12;
    if (!id) throw fail('ACCOUNT_NOT_FOUND', 'Ҳисоб топилмади.');
    const snap = await stateRef(id).get();
    if (!snap.exists) throw fail('ACCOUNT_DELETION_NOT_PENDING', 'Ўчириш сўрови йўқ.');
    const d = snap.data() || {};
    const ev = await stateRef(id).collection('events').orderBy('at', 'desc').limit(50).get();
    const hidden = await stateRef(id).collection('hidden').where('restored', '==', false).get();
    const steps = {};
    for (const [k, v] of Object.entries(d.steps || {})) steps[k] = { done: !!(v && v.done), atMs: (v && v.atMs) || null };
    return {
      ...rowOf(id, d),
      steps,
      hiddenCount: hidden.size,
      events: ev.docs.map((e) => {
        const x = e.data() || {};
        const { at, type, ...rest } = x;
        return { type: String(type || ''), atMs: ms(at), meta: JSON.parse(JSON.stringify(rest)) };
      }),
    };
  }

  const needReason = (reason) => {
    const r = String(reason == null ? '' : reason).trim().slice(0, 300);
    if (r.length < 3) throw fail('REASON_REQUIRED', 'Сабабни ёзинг.');
    return r;
  };

  const auditOf = (kind, actor, reason) => ({ kind, actor, actorRole: 'admin', reason, source: 'admin_panel' });

  /** Админ бекор қилади (масалан, фойдаланувчи илова орқали эмас, чат орқали сўраган). */
  async function adminCancel(uid, { actor, reason }) {
    const r = needReason(reason);
    return cancel(uid, { audit: auditOf('account_deletion_admin_cancel', actor, r) });
  }

  /** Илова йўқ фойдаланувчи учун қўлда сўров (веб-саҳифа/email йўли). Шахс тасдиғи — админнинг масъулияти. */
  async function adminRequest(phone, { actor, reason }) {
    const r = needReason(reason);
    const uid = core.phoneForms(phone).d12;
    if (!uid) throw fail('ACCOUNT_NOT_FOUND', 'Телефон нотўғри.');
    return request(uid, { source: 'admin', audit: auditOf('account_deletion_admin_request', actor, r) });
  }

  /** FAILED сўровни қайта уриниш учун очади (кутиш муддатини ҚИСҚАРТИРМАЙДИ: PENDING га тегмайди). */
  async function adminRetry(uid, { actor, reason }) {
    const r = needReason(reason);
    const id = core.phoneForms(uid).d12;
    if (!id) throw fail('ACCOUNT_NOT_FOUND', 'Ҳисоб топилмади.');
    const ref = stateRef(id);
    await db.runTransaction(async (t) => {
      const snap = await t.get(ref);
      if (!snap.exists) throw fail('ACCOUNT_DELETION_NOT_PENDING', 'Ўчириш сўрови йўқ.');
      if ((snap.data() || {}).status !== 'FAILED') throw fail('ACCOUNT_DELETION_NOT_FAILED', 'Фақат муваффақиятсиз сўровни қайта юритиш мумкин.');
      t.update(ref, { status: 'POSTPONED', attempts: 0, nextCheckAt: at(now()), updatedAt: ts() });
      eventIn(t, id, 'admin_retry', { by: actor });
      t.create(db.collection('admin_audit').doc(), { ...auditOf('account_deletion_admin_retry', actor, r), targetId: id, at: ts() });
    });
    log({ action: 'admin_retry', result: 'ok', userId: id, actor });
    return { ok: true, status: 'POSTPONED' };
  }

  async function adminGetGate() {
    return readConfig();
  }

  /** Дарвозани ўзгартириш (фақат superadmin; INTERNAL рўйхат ва кутиш кунлари). Аудит: `setAccountDeletion`. */
  async function adminSetGate({ enabled, waitDays, allow, actor, reason }) {
    const r = needReason(reason);
    const { setAccountDeletion } = require('./tools/set_account_deletion');
    try {
      return await setAccountDeletion(db, admin, {
        enabled, waitDays, allow, apply: true, actor, actorRole: 'superadmin', source: 'admin_panel', reason: r,
      });
    } catch (e) {
      throw fail('INVALID_GATE', String((e && e.message) || e).slice(0, 200));
    }
  }

  return {
    preview, request, cancel, execute, runDue, readConfig, STEPS,
    adminList, adminDetail, adminCancel, adminRequest, adminRetry, adminGetGate, adminSetGate,
  };
}

/**
 * Қобиқ «тирилиши»: ўчирилган ҳисоб (`users/{id}.deleted === true`) ўша телефон билан қайта рўйхатдан ўтганда
 * клиент профил майдонларини (phone, name…) шу ҳужжатга ёзади. Шу пайтда `deleted` белгилари олинади ва
 * `createdAt` янгиланади (янги ҳисоб). Киришнинг марказий функциясига ТЕГИЛМАЙДИ (хавфсизлик): алоҳида триггер.
 * @returns {Promise<boolean>} тирилдими
 */
async function reviveShellIfNeeded({ admin, ref, before, after }) {
  if (!before || !after) return false;
  if (before.deleted !== true || after.deleted !== true) return false;
  const phone = typeof after.phone === 'string' ? after.phone.trim() : '';
  if (!phone) return false; // қобиқда телефон майдони йўқ; профил ёзилгач бор
  const FV = admin.firestore.FieldValue;
  await ref.update({
    deleted: FV.delete(),
    deletedAt: FV.delete(),
    revivedAt: FV.serverTimestamp(),
    createdAt: FV.serverTimestamp(),
  });
  return true;
}

/** Callable'лар ва режали функция (index.js `attachAccountDeletion(exports, {...})`). */
function attachAccountDeletion(exportsObj, deps) {
  const { functions, db, admin, callerPhone, canonicalUid, requireCallerRoles } = deps;
  const HttpsError = functions.https.HttpsError;
  const svc = createAccountDeletion({
    db,
    admin,
    auth: admin.auth(),
    hiders: [createHider({ db, admin })],
    deleteStoragePath: async (p) => { try { await admin.storage().bucket().file(p).delete(); } catch (_) { /* noop */ } },
    deleteStoragePrefix: async (prefix) => {
      try {
        const [files] = await admin.storage().bucket().getFiles({ prefix });
        await Promise.all(files.map((f) => f.delete().catch(() => {})));
      } catch (e) { console.error('account_deletion storage:', e && e.message ? e.message : e); }
    },
  });

  const userMessage = {
    ACCOUNT_DELETION_DISABLED: 'Ҳисобни ўчириш ҳозирча мавжуд эмас. Кейинроқ уриниб кўринг.',
    ACCOUNT_DELETION_BLOCKED: 'Ҳисобни ҳозир ўчириб бўлмайди: тугамаган ишлар бор.',
    ACCOUNT_NOT_FOUND: 'Ҳисоб топилмади.',
    ACCOUNT_DELETION_NOT_PENDING: 'Ўчириш сўрови йўқ.',
    ACCOUNT_DELETION_IN_PROGRESS: 'Ўчириш бошланган, бекор қилиб бўлмайди.',
    ACCOUNT_DELETION_NOT_FAILED: 'Фақат муваффақиятсиз сўровни қайта юритиш мумкин.',
    REASON_REQUIRED: 'Сабабни ёзинг.',
    INVALID_STATUS: 'Ҳолат нотўғри.',
    INVALID_GATE: 'Дарвоза қиймати нотўғри.',
  };
  const argErrors = new Set(['REASON_REQUIRED', 'INVALID_STATUS', 'INVALID_GATE']);

  function requireUid(context) {
    if (!context || !context.auth) throw new HttpsError('unauthenticated', 'Authentication required');
    const uid = canonicalUid(callerPhone(context));
    if (!uid || uid.length < 12) throw new HttpsError('unauthenticated', 'Phone token required');
    return uid;
  }

  function mapError(e) {
    if (e instanceof HttpsError) return e;
    if (e && e.code && userMessage[e.code]) {
      const code = e.code;
      let status = 'failed-precondition';
      if (code === 'ACCOUNT_NOT_FOUND') status = 'not-found';
      else if (argErrors.has(code)) status = 'invalid-argument';
      return new HttpsError(status, userMessage[code], { code, ...(e.extra || {}) });
    }
    console.error(JSON.stringify({ module: 'account_deletion', result: 'error', errorCode: 'INTERNAL', message: String((e && e.message) || e).slice(0, 200) }));
    return new HttpsError('internal', 'Хатолик. Қайта уриниб кўринг.', { code: 'INTERNAL' });
  }

  function wrap(fn) {
    return async (data, context) => {
      const uid = requireUid(context);
      try {
        return await fn(uid, data || {});
      } catch (e) {
        throw mapError(e);
      }
    };
  }

  /** Админ callable: роль серверда текширилади (`requireCallerRoles`), actor = админнинг каноник телефони. */
  function wrapAdmin(roles, fn) {
    return async (data, context) => {
      const actor = await requireCallerRoles(context, roles, 'Admin role required');
      try {
        return await fn(actor, data || {});
      } catch (e) {
        throw mapError(e);
      }
    };
  }
  const ADMIN_ROLES = ['admin', 'superadmin'];
  const SUPER_ONLY = ['superadmin'];

  exportsObj.previewAccountDeletion = functions.https.onCall(wrap((uid) => svc.preview(uid)));
  exportsObj.requestAccountDeletion = functions.https.onCall(wrap((uid) => svc.request(uid, { source: 'app' })));
  exportsObj.cancelAccountDeletion = functions.https.onCall(wrap((uid) => svc.cancel(uid)));

  // Админ панел («Ҳисобни ўчириш» бўлими): рўйхат/тафсилот/бекор қилиш — admin|superadmin;
  // қўлда сўров, қайта юритиш ва дарвоза — фақат superadmin. Ҳар ўзгартирувчи амал сабаб билан admin_audit'га тушади.
  exportsObj.adminListAccountDeletions = functions.https.onCall(wrapAdmin(ADMIN_ROLES,
    (actor, d) => svc.adminList({ statuses: d.statuses, limit: d.limit })));
  exportsObj.adminGetAccountDeletion = functions.https.onCall(wrapAdmin(ADMIN_ROLES,
    (actor, d) => svc.adminDetail(d.uid)));
  exportsObj.adminCancelAccountDeletion = functions.https.onCall(wrapAdmin(ADMIN_ROLES,
    (actor, d) => svc.adminCancel(d.uid, { actor, reason: d.reason })));
  exportsObj.adminRequestAccountDeletion = functions.https.onCall(wrapAdmin(SUPER_ONLY,
    (actor, d) => svc.adminRequest(d.phone, { actor, reason: d.reason })));
  exportsObj.adminRetryAccountDeletion = functions.https.onCall(wrapAdmin(SUPER_ONLY,
    (actor, d) => svc.adminRetry(d.uid, { actor, reason: d.reason })));
  exportsObj.adminGetAccountDeletionGate = functions.https.onCall(wrapAdmin(ADMIN_ROLES,
    () => svc.adminGetGate()));
  exportsObj.adminSetAccountDeletionGate = functions.https.onCall(wrapAdmin(SUPER_ONLY,
    (actor, d) => svc.adminSetGate({ enabled: d.enabled, waitDays: d.waitDays, allow: d.allow, actor, reason: d.reason })));

  exportsObj.onUserShellRevived = functions.firestore
    .document('users/{userId}')
    .onUpdate(async (change) => {
      try {
        const revived = await reviveShellIfNeeded({
          admin, ref: change.after.ref, before: change.before.data(), after: change.after.data(),
        });
        if (revived) console.log(JSON.stringify({ module: 'account_deletion', action: 'shell_revived', userId: change.after.id }));
      } catch (e) {
        console.error(JSON.stringify({ module: 'account_deletion', result: 'error', errorCode: 'SHELL_REVIVE_FAILED', userId: change.after.id }));
      }
      return null;
    });

  exportsObj.executeAccountDeletions = functions
    .runWith({ timeoutSeconds: 540, memory: '512MB' })
    .pubsub.schedule('every 60 minutes')
    .timeZone('Asia/Tashkent')
    .onRun(async () => {
      await svc.runDue({ limit: 10 });
      return null;
    });
  return svc;
}

module.exports = {
  createAccountDeletion, attachAccountDeletion, reviveShellIfNeeded, USER_SUBCOLLECTIONS, ACTIVE_STATES, COL, HISTORY,
};
