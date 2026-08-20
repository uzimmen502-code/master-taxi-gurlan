'use strict';

/**
 * AVA расмий Instagram / Facebook / TikTok — клип active бўлганда жойлаш.
 * Токенлар: settings/tv_social (CF-only) + env fallback.
 */
const axios = require('axios');

const GRAPH = 'https://graph.facebook.com/v21.0';
const TIKTOK = 'https://open.tiktokapis.com/v2';
const SETTINGS_PATH = ['settings', 'tv_social'];
const ORDERED = ['instagram', 'facebook', 'tiktok'];
const STALE_MS = 12 * 60 * 1000;
const IG_POLL_MS = 5000;
const IG_POLL_MAX = 48;

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function axiosMsg(e) {
  const d = e && e.response && e.response.data;
  if (d && d.error) {
    if (typeof d.error === 'string') return d.error;
    return String(d.error.message || d.error.code || JSON.stringify(d.error));
  }
  if (d && d.message) return String(d.message);
  return String((e && e.message) || 'request failed');
}

function str(v, max) {
  return String(v == null ? '' : v).trim().slice(0, max || 400);
}

function requestedNetworks(clip) {
  const raw = Array.isArray(clip.socialNetworks) ? clip.socialNetworks : [];
  const picked = [];
  for (const id of ORDERED) {
    if (raw.map((x) => String(x).toLowerCase()).includes(id)) picked.push(id);
  }
  if (picked.length) return picked;
  if (clip.socialConsent === true) return ORDERED.slice();
  return [];
}

function networkState(clip, net) {
  const sp = clip.socialPost && typeof clip.socialPost === 'object'
      ? clip.socialPost : {};
  const nets = sp.networks && typeof sp.networks === 'object' ? sp.networks : {};
  const row = nets[net] && typeof nets[net] === 'object' ? nets[net] : {};
  return String(row.status || '');
}

function buildCaption(clip, prefix) {
  const lines = [];
  const head = str(prefix, 200);
  if (head) lines.push(head);
  if (str(clip.title, 180)) lines.push(str(clip.title, 180));
  if (str(clip.description, 600)) lines.push(str(clip.description, 600));
  const loc = [str(clip.districtLabel, 80), str(clip.ownerName, 80)]
      .filter(Boolean).join(' · ');
  if (loc) lines.push(loc);
  lines.push('#AVA');
  return lines.join('\n').slice(0, 2100);
}

function publicSettings(s) {
  return {
    facebookPageId: str(s.facebookPageId, 40),
    instagramUserId: str(s.instagramUserId, 40),
    captionPrefix: str(s.captionPrefix, 200),
    pageTokenSet: Boolean(str(s.facebookPageAccessToken, 800)),
    tiktokTokenSet: Boolean(str(s.tiktokAccessToken, 800)),
    tiktokRefreshSet: Boolean(str(s.tiktokRefreshToken, 800)),
    tiktokClientKeySet: Boolean(str(s.tiktokClientKey, 80)),
  };
}

function attachTvSocialPublish(exports, deps) {
  const { functions, db, admin, requireCallerRoles } = deps;
  const heavy = functions.runWith({ timeoutSeconds: 540, memory: '512MB' });

  async function loadSettings() {
    const snap = await db.collection(SETTINGS_PATH[0]).doc(SETTINGS_PATH[1]).get();
    const s = snap.exists ? (snap.data() || {}) : {};
    return {
      facebookPageId: str(s.facebookPageId, 40) || str(process.env.META_PAGE_ID, 40),
      facebookPageAccessToken: str(s.facebookPageAccessToken, 800)
          || str(process.env.META_PAGE_ACCESS_TOKEN, 800),
      instagramUserId: str(s.instagramUserId, 40)
          || str(process.env.INSTAGRAM_USER_ID, 40),
      captionPrefix: str(s.captionPrefix, 200),
      tiktokAccessToken: str(s.tiktokAccessToken, 800)
          || str(process.env.TIKTOK_ACCESS_TOKEN, 800),
      tiktokRefreshToken: str(s.tiktokRefreshToken, 800)
          || str(process.env.TIKTOK_REFRESH_TOKEN, 800),
      tiktokClientKey: str(s.tiktokClientKey, 80)
          || str(process.env.TIKTOK_CLIENT_KEY, 80),
      tiktokClientSecret: str(s.tiktokClientSecret, 200)
          || str(process.env.TIKTOK_CLIENT_SECRET, 200),
    };
  }

  async function saveSettingsPatch(patch) {
    await db.collection(SETTINGS_PATH[0]).doc(SETTINGS_PATH[1]).set(
        Object.assign({ updatedAt: admin.firestore.FieldValue.serverTimestamp() }, patch),
        { merge: true },
    );
  }

  async function refreshTikTok(s) {
    if (!s.tiktokRefreshToken || !s.tiktokClientKey || !s.tiktokClientSecret) {
      return s;
    }
    const body = new URLSearchParams({
      client_key: s.tiktokClientKey,
      client_secret: s.tiktokClientSecret,
      grant_type: 'refresh_token',
      refresh_token: s.tiktokRefreshToken,
    });
    const res = await axios.post(`${TIKTOK}/oauth/token/`, body.toString(), {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      timeout: 30000,
    });
    const data = (res.data && res.data.data) || res.data || {};
    const access = str(data.access_token, 800);
    if (!access) throw new Error('TikTok token refresh empty');
    const patch = { tiktokAccessToken: access };
    const refresh = str(data.refresh_token, 800);
    if (refresh) patch.tiktokRefreshToken = refresh;
    await saveSettingsPatch(patch);
    return Object.assign({}, s, patch);
  }

  async function postInstagram(videoUrl, caption, s) {
    if (!s.instagramUserId || !s.facebookPageAccessToken) {
      throw new Error('Instagram User ID ёки Page token йўқ');
    }
    const create = await axios.post(
        `${GRAPH}/${s.instagramUserId}/media`,
        null,
        {
          params: {
            media_type: 'REELS',
            video_url: videoUrl,
            caption,
            share_to_feed: true,
            access_token: s.facebookPageAccessToken,
          },
          timeout: 60000,
        },
    );
    const creationId = create.data && create.data.id;
    if (!creationId) throw new Error('Instagram container id йўқ');
    let last = '';
    for (let i = 0; i < IG_POLL_MAX; i += 1) {
      await sleep(IG_POLL_MS);
      const st = await axios.get(`${GRAPH}/${creationId}`, {
        params: {
          fields: 'status_code,status',
          access_token: s.facebookPageAccessToken,
        },
        timeout: 30000,
      });
      last = String((st.data && st.data.status_code) || '');
      if (last === 'FINISHED' || last === 'PUBLISHED') break;
      if (last === 'ERROR' || last === 'EXPIRED') {
        throw new Error(`Instagram container ${last}: ${(st.data && st.data.status) || ''}`);
      }
    }
    if (last !== 'FINISHED' && last !== 'PUBLISHED') {
      throw new Error(`Instagram тайёр бўлмади (${last || 'timeout'})`);
    }
    const pub = await axios.post(
        `${GRAPH}/${s.instagramUserId}/media_publish`,
        null,
        {
          params: {
            creation_id: creationId,
            access_token: s.facebookPageAccessToken,
          },
          timeout: 60000,
        },
    );
    const id = String((pub.data && pub.data.id) || creationId);
    return { id, url: `https://www.instagram.com/reel/${id}/` };
  }

  async function postFacebook(videoUrl, caption, s) {
    if (!s.facebookPageId || !s.facebookPageAccessToken) {
      throw new Error('Facebook Page ID ёки Page token йўқ');
    }
    const res = await axios.post(
        `${GRAPH}/${s.facebookPageId}/videos`,
        null,
        {
          params: {
            file_url: videoUrl,
            description: caption,
            published: true,
            access_token: s.facebookPageAccessToken,
          },
          timeout: 120000,
        },
    );
    const id = String((res.data && (res.data.id || res.data.post_id)) || '');
    if (!id) throw new Error('Facebook video id йўқ');
    return { id, url: `https://www.facebook.com/${s.facebookPageId}/videos/${id}` };
  }

  async function postTikTok(videoUrl, caption, sIn) {
    let s = sIn;
    if (!s.tiktokAccessToken) throw new Error('TikTok access token йўқ');

    const tryInit = async (token, privacy) => axios.post(
        `${TIKTOK}/post/publish/video/init/`,
        {
          post_info: {
            title: caption.slice(0, 2200),
            privacy_level: privacy,
            disable_duet: false,
            disable_comment: false,
            disable_stitch: false,
          },
          source_info: {
            source: 'PULL_FROM_URL',
            video_url: videoUrl,
          },
        },
        {
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json; charset=UTF-8',
          },
          timeout: 60000,
        },
    );

    let res;
    try {
      res = await tryInit(s.tiktokAccessToken, 'PUBLIC_TO_EVERYONE');
    } catch (e) {
      const msg = axiosMsg(e);
      const code = e && e.response && e.response.status;
      if (code === 401 && s.tiktokRefreshToken) {
        s = await refreshTikTok(s);
        try {
          res = await tryInit(s.tiktokAccessToken, 'PUBLIC_TO_EVERYONE');
        } catch (_) {
          res = await tryInit(s.tiktokAccessToken, 'SELF_ONLY');
        }
      } else if (/privacy_level|unaudited|SELF_ONLY/i.test(msg)) {
        res = await tryInit(s.tiktokAccessToken, 'SELF_ONLY');
      } else {
        throw e;
      }
    }
    const err = res.data && res.data.error;
    if (err && err.code && String(err.code) !== 'ok') {
      throw new Error(err.message || err.code);
    }
    const publishId = str(
        (res.data && res.data.data && res.data.data.publish_id) || '',
        80,
    );
    if (!publishId) throw new Error('TikTok publish_id йўқ');
    return { id: publishId, url: '' };
  }

  async function publishOne(net, videoUrl, caption, s) {
    if (net === 'instagram') return postInstagram(videoUrl, caption, s);
    if (net === 'facebook') return postFacebook(videoUrl, caption, s);
    if (net === 'tiktok') return postTikTok(videoUrl, caption, s);
    throw new Error(`unknown network ${net}`);
  }

  async function claim(clipId, force) {
    const ref = db.collection('tv_clips').doc(clipId);
    return db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return { skip: 'missing' };
      const d = snap.data() || {};
      if (d.status !== 'active') return { skip: 'not_active' };
      const nets = requestedNetworks(d);
      if (!nets.length) return { skip: 'no_networks' };
      const pending = force
          ? nets.filter((n) => networkState(d, n) !== 'posted')
          : nets.filter((n) => networkState(d, n) !== 'posted');
      if (!pending.length) return { skip: 'already_posted' };
      const sp = d.socialPost && typeof d.socialPost === 'object' ? d.socialPost : {};
      let startedMs = 0;
      if (sp.startedAt && typeof sp.startedAt.toMillis === 'function') {
        startedMs = sp.startedAt.toMillis();
      }
      if (
        sp.status === 'posting'
        && startedMs
        && (Date.now() - startedMs) < STALE_MS
        && !force
      ) {
        return { skip: 'in_flight' };
      }
      tx.update(ref, {
        'socialPost.status': 'posting',
        'socialPost.startedAt': admin.firestore.FieldValue.serverTimestamp(),
      });
      return { clip: Object.assign({ id: clipId }, d), nets: pending, allNets: nets };
    });
  }

  async function publishClipSocial(clipId, opts) {
    const force = Boolean(opts && opts.force);
    const claimed = await claim(clipId, force);
    if (claimed.skip) {
      return { skipped: claimed.skip, clipId };
    }
    const clip = claimed.clip;
    const videoUrl = str(clip.videoUrl, 2000);
    const ref = db.collection('tv_clips').doc(clipId);
    if (!videoUrl) {
      await ref.update({
        'socialPost.status': 'error',
        'socialPost.error': 'videoUrl бўш',
        'socialPost.finishedAt': admin.firestore.FieldValue.serverTimestamp(),
      });
      return { skipped: 'no_video', clipId };
    }

    const s = await loadSettings();
    const caption = buildCaption(clip, s.captionPrefix);
    const networks = Object.assign(
        {},
        (clip.socialPost && clip.socialPost.networks) || {},
    );
    const results = {};

    for (const net of claimed.nets) {
      try {
        const posted = await publishOne(net, videoUrl, caption, s);
        networks[net] = {
          status: 'posted',
          id: posted.id || '',
          url: posted.url || '',
          at: admin.firestore.Timestamp.now(),
        };
        results[net] = { ok: true, id: posted.id || '' };
      } catch (e) {
        const msg = axiosMsg(e).slice(0, 400);
        console.error(`[tvSocial] ${clipId} ${net}:`, msg);
        networks[net] = {
          status: 'error',
          error: msg,
          at: admin.firestore.Timestamp.now(),
        };
        results[net] = { ok: false, error: msg };
      }
    }

    const allNets = claimed.allNets || claimed.nets;
    const allPosted = allNets.every((n) =>
      networks[n] && networks[n].status === 'posted');
    const anyPosted = allNets.some((n) =>
      networks[n] && networks[n].status === 'posted');
    const status = allPosted ? 'posted' : (anyPosted ? 'partial' : 'error');
    const errMsg = status === 'error'
        ? (Object.values(results).map((r) => r.error).filter(Boolean)[0] || '')
        : '';
    const patch = {
      'socialPost.status': status,
      'socialPost.finishedAt': admin.firestore.FieldValue.serverTimestamp(),
      'socialPost.networks': networks,
      'socialPost.error': errMsg
          ? errMsg
          : admin.firestore.FieldValue.delete(),
    };
    if (allPosted) {
      patch.socialPostedAt = admin.firestore.FieldValue.serverTimestamp();
    }
    await ref.update(patch);

    if (allPosted && str(clip.shopItemId, 80)) {
      try {
        await db.collection('tv_shop_items').doc(clip.shopItemId).set(
            { socialPostedAt: admin.firestore.FieldValue.serverTimestamp() },
            { merge: true },
        );
      } catch (e) {
        console.error('[tvSocial] shop item stamp', e);
      }
    }
    return { clipId, status, results };
  }

  exports.onTvClipSocialPublish = heavy.firestore
      .document('tv_clips/{clipId}')
      .onWrite(async (change, context) => {
        if (!change.after.exists) return null;
        const after = change.after.data() || {};
        const before = change.before.exists ? (change.before.data() || {}) : {};
        const becameActive = after.status === 'active' && before.status !== 'active';
        const retryAfter = Number(after.socialRetryAt || 0);
        const retryBefore = Number(before.socialRetryAt || 0);
        const retryBump = retryAfter !== retryBefore && retryAfter > 0;
        if (!becameActive && !retryBump) return null;
        try {
          return await publishClipSocial(context.params.clipId, { force: retryBump });
        } catch (e) {
          console.error('[tvSocial] trigger', context.params.clipId, e);
          return null;
        }
      });

  exports.adminGetTvSocialSettings = functions.https.onCall(async (data, context) => {
    await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const s = await loadSettings();
    return { ok: true, settings: publicSettings(s) };
  });

  exports.adminSetTvSocialSettings = functions.https.onCall(async (data, context) => {
    await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const patch = {};
    if (data && data.facebookPageId != null) {
      patch.facebookPageId = str(data.facebookPageId, 40);
    }
    if (data && data.instagramUserId != null) {
      patch.instagramUserId = str(data.instagramUserId, 40);
    }
    if (data && data.captionPrefix != null) {
      patch.captionPrefix = str(data.captionPrefix, 200);
    }
    if (data && data.facebookPageAccessToken != null
        && str(data.facebookPageAccessToken, 800)) {
      patch.facebookPageAccessToken = str(data.facebookPageAccessToken, 800);
    }
    if (data && data.tiktokAccessToken != null && str(data.tiktokAccessToken, 800)) {
      patch.tiktokAccessToken = str(data.tiktokAccessToken, 800);
    }
    if (data && data.tiktokRefreshToken != null && str(data.tiktokRefreshToken, 800)) {
      patch.tiktokRefreshToken = str(data.tiktokRefreshToken, 800);
    }
    if (data && data.tiktokClientKey != null) {
      patch.tiktokClientKey = str(data.tiktokClientKey, 80);
    }
    if (data && data.tiktokClientSecret != null && str(data.tiktokClientSecret, 200)) {
      patch.tiktokClientSecret = str(data.tiktokClientSecret, 200);
    }
    if (!Object.keys(patch).length) {
      throw new functions.https.HttpsError('invalid-argument', 'empty patch');
    }
    await saveSettingsPatch(patch);
    const s = await loadSettings();
    return { ok: true, settings: publicSettings(s) };
  });

  exports.adminPublishTvClipSocial = heavy.https.onCall(async (data, context) => {
    await requireCallerRoles(context, ['admin', 'superadmin'], 'Admin role required');
    const clipId = str(data && data.clipId, 80);
    if (!clipId) {
      throw new functions.https.HttpsError('invalid-argument', 'clipId required');
    }
    try {
      const result = await publishClipSocial(clipId, { force: true });
      return { ok: true, result };
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      console.error('[tvSocial] adminPublish', clipId, e);
      throw new functions.https.HttpsError('internal', axiosMsg(e).slice(0, 180));
    }
  });
}

module.exports = { attachTvSocialPublish };
