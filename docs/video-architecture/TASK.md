# AVA Video Architecture — Gap Analysis & Cost-Driven Roadmap

**Date:** 2026-10-01
**Platforms:** Android (production), iOS (in-app only; App Store not live)
**Baseline commit:** 5801954 (feat/home-redesign)
**Cost source of truth:** `docs/video-architecture/cost_model.py` — every dollar figure
in this document is printed by that script. Do not hand-edit numbers; change a
parameter, re-run, paste.

---

## 0. Cost Model Output (single source of truth)

Run: `python docs/video-architecture/cost_model.py`

Parameters: views/DAU/day=20, MB/view=5, feed loads/DAU/day=5, docs/page=20,
egress $0.12/GB, write $1.80/1M, read $0.60/1M, R2 storage $0.015/GB, 30-day month,
GB=1000 MB (decimal).

### Monthly cost by line item

| Line item | 10k DAU | 100k DAU | 1M DAU |
|-----------|--------:|---------:|-------:|
| Views / month | 6,000,000 | 60,000,000 | 600,000,000 |
| Egress volume | 30 TB | 300 TB | 3.0 PB |
| **CURRENT (Firebase Storage + unbatched Firestore)** | | | |
| Egress (Firebase) | $3,600 | $36,000 | **$360,000** |
| View writes (×3) | $32.40 | $324.00 | $3,240 |
| Stats writes (×1) | $10.80 | $108.00 | $1,080 |
| Feed reads (20 docs/load) | $18.00 | $180.00 | $1,800 |
| R2 storage (processed, 12-mo) | $13.50 | $135.00 | $1,350 |
| **= Baseline total** | **$3,675** | **$36,747** | **$367,470** |
| **OPTIMIZED (R2+CF egress=0, merged events, JSON feed)** | | | |
| Egress (R2 via Cloudflare) | $0 | $0 | $0 |
| Aggregated writes (ingest + flush) | $13.91 | $139.10 | $1,391 |
| Feed JSON reads | $0 | $0 | $0 |
| R2 storage | $13.50 | $135.00 | $1,350 |
| **= Optimized total** | **$27.41** | **$274.10** | **$2,741** |

### Cost per 1,000 views (independent of DAU)

| Component | Firebase baseline | R2 + optimized |
|-----------|------------------:|---------------:|
| Egress | $0.6000 | $0 |
| Feed reads | $0.0030 | $0 |
| Writes | $0.0072 | $0.0018 |
| **Total** | **$0.6102** | **$0.0018** |

**Headline:** egress is **98% of the baseline** ($360,000 of $367,470 at 1M DAU).
Per 1,000 views, egress alone ($0.6000) is 98% of the Firebase cost ($0.6102).
The artifact's own target was ≤$0.007/1,000 views (infra, CDN excluded) — the
current Firebase path is **87× over target**; R2+Cloudflare ($0.0018) clears it.

This single fact sets the entire priority order (Section 5).

---

## 1. Current State by Layer

### 1.1 Upload
- **Code:** `TvStorageService.uploadVideo()` → Firebase Storage, path
  `tv_clips/{ownerPhone}/{ts}_{uuid}.mp4` (tv_storage_service.dart:27-56).
- **Works.** No change required. Upload stays on Firebase Storage even after the
  R2 migration (see 5.1) — only *processed outputs* move to R2.

### 1.2 Processing (FFmpeg)
- **Code:** `onTvClipCreatedV2` / `onTvClipVideoReplacedV2` Firestore triggers
  (index.js:12682, 12691) → `transcodeTvClipVideo()` (index.js:12357).
- 2nd-gen function, 540s timeout, 4 CPU, 4 GiB, us-central1 (index.js:12674-12680).
- All 3 variants (720/480/360) in **one** FFmpeg pass via `filter_complex split`
  (index.js:12424-12430) — source decoded once.
- Ladder: 720p CRF23/3000k, 480p CRF24/1500k, 360p CRF27/600k
  (TV_CLIP_VARIANT_SPECS, index.js:11879-11883).
- HLS: 3s segments, `single_file` (index.js:12154-12272; TV_CLIP_HLS_SEGMENT_SECONDS=3).
- **Status:** ✅ Works.

### 1.3 Fast-track 360p
- `fastTrack360pIfPossible()` runs a separate 360p-only pass **before** the main
  pass and writes `processingStatus: 'ready'` immediately (index.js:12420,
  12007-12058). Author/viewers can watch at 360p before the full ladder finishes.
- **Status:** ✅ Works — this is the mechanism that makes a clip playable early.

### 1.4 Playback URL selection
- `urlForQuality()` (tv_clip.dart:232-234):
  ```
  if (!kIsWeb && hlsUrl.isNotEmpty) return hlsUrl;   // Android+iOS: HLS if present
  return videoVariants[quality] ?? videoUrl;          // else MP4 variant, else raw
  ```
- **Feed currently plays HLS** when `hlsUrl` is set (all newly transcoded clips),
  falling back to the per-quality MP4, then to the raw upload.
- **Status:** ✅ HLS in production.

### 1.5 Caching / CDN
- Cache-Control `public, max-age=31536000, immutable` set on all video objects
  (tv_storage_service.dart:15; index.js:11819). Immutable is safe because every
  re-transcode writes a new `{runId}` path (index.js:12304).
- **But:** served from Firebase Storage us-central1 directly — **no edge cache,
  full egress on every view.** This is the $360,000 line.
- **Status:** ❌ No CDN.

### 1.6 View / Like / Stats writes
- `recordView()` (tv_clips_repository.dart:536-571): a transaction doing up to
  **3 writes** — `views/{viewerId}` dedup doc, `clip.viewCount++`,
  `profile.totalViewCount++`. Deduped 1/viewer/24h.
- `recordPlaybackStats()` (tv_clips_repository.dart:577-609): **1 write** with
  increment fields (views, watchedMs, bufferMs, bufferEvents, firstFrameMsSum,
  firstFrameSamples, completedViews, skippedViews). One per playback, not deduped.
- **Status:** ⚠️ Up to 4 writes per playback; all land on the hot `tv_clips/{id}`
  document (contention). See 5.2.

### 1.7 Feed pagination
- `fetchNearby()` / `fetchByRegion()` / `fetchAllActive()` — Firestore queries
  (tv_clips_repository.dart:85, 159, 331). Each returns up to 20 docs =
  **20 reads per page load** (billed per returned document). This is the $1,800 line.
- **Status:** ⚠️ Works, but reads scale with views.

### 1.8 Moderation / readiness guard
- `processingStatus` ∈ {processing, ready, error}; `canStartPlayback == 'ready'`
  (tv_clip.dart:203). `TvPlayerPool.prepare(url, {isReady})` refuses to build a
  controller when not ready (tv_player_pool.dart:79-90).
- **Status:** ✅ Implemented (v4.0).

### 1.9 Prefetch (Android)
- `TvSegmentPrefetcher` (native Media3 SimpleCache via MethodChannel
  `uz.ava.gurlan/tv_media_cache`) + `TvNetworkQualityService` adaptive timeout
  (tv_segment_prefetcher.dart; tv_network_quality_service.dart).
- **Status:** ✅ Android only (see Section 7 for iOS).

---

## 2. Gap Summary

| Layer | Status | Note |
|-------|--------|------|
| Upload | ✅ Works | Stays on Firebase Storage |
| FFmpeg / ladder / HLS | ✅ Works | One-pass, 3s segments |
| Fast-track 360p | ✅ Works | Early playable |
| Playback URL (HLS) | ✅ Works | HLS in feed |
| Readiness guard | ✅ Works | v4.0 |
| Android prefetch | ✅ Works | Media3 cache |
| **CDN / egress** | ❌ **Missing** | **$360k/mo at 1M — priority #1** |
| View/stats writes | ⚠️ 4 writes/view | Hot-doc contention — priority #2 |
| Feed reads | ⚠️ 20/load | priority #3 |
| iOS prefetch | ❌ Missing | Deferred to App Store launch |

---

## 3. Server-Side Aggregation Design (view + stats)

**Problem:** per playback, up to 4 writes hit `tv_clips/{id}` (3 from `recordView`,
1 from `recordPlaybackStats`). At 1M DAU that's view writes $3,240 + stats $1,080 =
**$4,320/mo**, and all increments contend on one document.

**Design — merge into one event, aggregate server-side:**

1. **Client:** on playback end (`TvPlaybackAnalyticsRecorder.detach`), emit ONE
   event to an append-only collection `tv_clip_events/{autoId}`:
   `{clipId, viewerId, ownerPhone, watchedMs, bufferMs, bufferEvents, firstFrameMs,
     completed, skipped, ts}`. One write per playback (was 4).

2. **Server (Pub/Sub + scheduled Cloud Function, every 5 min):**
   - Read the new events since last cursor.
   - Dedup views server-side (viewer+clip within 24h) using a compact
     `tv_clip_viewers/{clipId}/{viewerId}` doc (replaces the client-side `views/`
     subcollection transaction).
   - Sum per clip → one `increment()` batch per clip: `viewCount`, `likeCount`
     (if like events folded in), and all `playbackStats.*` sums.
   - Flush per active clip per interval. Writes now scale with **active clips ×
     intervals**, not views.

3. **Cost — re-derived 2026-10-02, and it changes the design.** Two facts the first
   estimate missed:
   - **A Firestore DELETE is billed as a write.** A Firestore-backed queue therefore
     costs *two* writes per event (insert + delete) before any aggregation gain.
   - **The `views/{viewerId}` dedup document cannot be merged** — one doc per viewer
     per clip. It is the floor under every variant.

   From `cost_model.py` (write cost per month):

   | | 10k DAU | 100k DAU | 1M DAU |
   |---|--------:|---------:|-------:|
   | A — today (3× distinct + 1× stats) | $38.34 | $383.40 | $3,834 |
   | B — Firestore queue + aggregator | $33.89 | $338.90 | $3,389 |
   | C — Pub/Sub queue + aggregator | $12.33 | $123.34 | $1,233 |
   | D — sample stats 10% (client only) | $28.62 | $286.20 | $2,862 |
   | E — D + drop the profile write | $19.44 | $194.40 | $1,944 |

   **B is nearly pointless** (−12%): the queue's own insert+delete eats the gain. If
   the queue is built it must be **Pub/Sub** (C), where the queue costs no Firestore
   writes at all (~$5/mo of Pub/Sub traffic at 1M DAU).

   **E needs no queue, no aggregator and no new infrastructure** and still takes half
   the cost out — `STATS_SAMPLE_RATE` on the client plus deriving
   `tv_public_profiles.totalViewCount` in the nightly reconciliation.

   At 10k DAU the whole line is $38/mo, so Phase 2 is a **latency and contention**
   fix, not a cost fix (as §5.2 already said). C only earns its complexity somewhere
   past ~100k DAU.

4. **Likes:** keep the authoritative `likes/{clipId}_{uid}` doc for correctness
   (needed for "did I like this"); fold the counter delta into the same aggregator
   so `likeCount` stops being a hot write.

**Stats fidelity preserved:** `playbackStats.*` are *sum* fields — summing them in
the aggregator is exactly equivalent to per-view increments. The KPI dashboard reads
the same aggregated document.

---

## 4. Feed JSON Design (+ author sees own clip immediately)

**Problem:** feed query returns 20 docs/load = 20 reads = $1,800/mo at 1M DAU, and
read latency ~100–200ms.

**Design:**
1. **Builder** (scheduled Cloud Function, every 1–2 min): query active clips per
   region/category, write paginated JSON to `feed/{region}_{cat}_{ver}/page-N.json`
   (R2 or Hosting), TTL 30–60s.
2. **Client:** fetch JSON from CDN, filter already-seen locally. Firestore reads for
   the shared feed → **0**.
3. **Author's own clip — no builder wait:** the feed the author sees =
   pre-built JSON (shared) **＋** a small live query `fetchByOwner(myPhone, limit 5)`
   (already exists, tv_clips_repository.dart:426), merged client-side at the top.
   The author's just-published clip (already `ready` via fast-track 360p) appears
   instantly; everyone else sees it after the next builder run (≤1–2 min). The own
   query is 1 user × ≤5 docs — negligible reads.
4. The existing local preview (`_showLocalPreview`, tv_publish_screen.dart:394) stays
   as the instant post-publish confirmation; the live own-query is what puts the clip
   in the actual feed.

---

## 5. Roadmap — priority from the cost model

The script makes the order unambiguous: kill the $360k egress first; everything
else is 1–2 orders of magnitude smaller.

### 5.1 Priority #1 — R2 + Cloudflare for processed outputs (new clips, flagged)
**Why:** removes **$360,000/mo** at 1M DAU (98% of cost); brings per-1,000-views
from $0.6102 to $0.0018.

**Status: implemented on `feat/r2-output` (not deployed).** See §10 for the branch
stack.

- **Upload unchanged:** stays on Firebase Storage (`TvStorageService`). No Worker,
  no presigned R2 upload — de-risks the change and reuses tested code.
- **Processing writes to R2:** inside `transcodeTvClipVideo`, when the feature flag
  is on, the MP4 variants + HLS go to R2 `processed/{clipId}/{runId}/` — **R2 only,
  never both**. Firestore stores the resulting `https://video.ava-uz.com/processed/…`
  URLs. Implemented as a `StorageOutput` abstraction (`functions/tv_clip_output.js`)
  with two backends: `FirebaseStorageOutput` (current) and `R2Output` (S3 API).
- **Flag:** R2 is used when **either** holds — `settings/app.tvR2Output` (boolean,
  default `false`) **or** the clip owner is listed in `server_config/tv_r2.owners`
  (array). The allowlist matches on `ownerPhone` (clip docs carry no uid) and
  compares digits only, so `+998 94 113-33-55` and `998941133355` are the same
  person. Both empty/false by default; a failed read resolves to `false`.
- **Why the allowlist is not in `settings/app`:** that document is world-readable
  (`firestore.rules:1389` — `allow read: if docId != 'courier' && docId !=
  'tv_social'`), so a list of phone numbers there would be public. `server_config/`
  is not matched by any rule, and there is no catch-all `match /{document=**}`, so
  Firestore denies it by default — Admin SDK still reads it. **This needs no
  `firestore.rules` change**, which matters: rules currently carry the undeployed
  `districtId` rule (see `docs/vazifalar.md`, В-8), so a rules deploy is not free.
- **Where the files are** is recorded on the clip as `variantBackend`
  (`'r2'|'firebase'`). Cleanup and deletion follow *that*, not the current flag —
  otherwise flipping the flag off would orphan every R2 clip.
- **No fallback (deliberate):** if an R2 write fails, the error propagates and the
  clip becomes `processingStatus: 'error'`. Silently falling back to Firebase would
  leave clips half in R2 and half in Storage — unfixable later. Same if the flag is
  on but the secrets are missing.
- **Secrets** (Google Secret Manager; never in code or git) — **three**, bound to all
  five affected functions: `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`,
  `CLOUDFLARE_API_TOKEN`. The Cloudflare **zone id is not a secret** and lives as a
  plain constant (`CF_ZONE_ID` in `tv_clip_output.js`) — it is public in the
  dashboard and grants nothing by itself; only the token does.
  ⚠️ Deploy fails until all three exist — even with the flag off.
- **Deleting a clip must also remove it from the CDN.** Objects are served
  `immutable, max-age=31536000`, so deleting from R2 is *not* enough — Cloudflare's
  edge would keep serving a deleted clip for up to a year. On delete the pipeline
  now: resolves the backend → deletes the Firebase prefixes (always, for legacy and
  mixed clips) → lists and deletes `processed/{clipId}/` in R2 → purges those exact
  URLs via the Cloudflare API. Re-transcode does the same for the superseded run
  (the live run is untouched, so playback is never interrupted).
- **Purge is retried and never blocks deletion.** Up to 3 attempts per 30-URL batch
  with backoff; 429 and 5xx are retried, other 4xx are not (a bad token will not fix
  itself). Deletion is already done by then, so a failed purge only logs — loudly,
  including a `purge TO'LIQ EMAS: n/m` line, because the consequence is a deleted
  clip still reachable on the CDN. Purge-by-URL is used, not purge-by-prefix
  (Enterprise-only); the exact key list comes from the R2 listing, so it is complete.
- **Cloudflare (one-time, owner/DevOps):** `video.ava-uz.com` → Cloudflare →
  **single R2 origin** (no Storage fallback origin — mixing origins breaks the
  immutable-cache guarantee and complicates invalidation). Cache Rule must include
  **`.ts`** — the pipeline emits `single_file` MPEG-TS segments, not `.m4s`, and
  those are the largest objects. Smart Tiered Cache; WAF rate-limit.
- **Rollout — done. `settings/app.tvR2Output = true` since 2026-10-02:** every new
  clip from every user now goes to R2 + `video.ava-uz.com`. Existing clips stay on
  Firebase Storage and keep working — their URLs are in Firestore, and cleanup and
  deletion follow each clip's own `variantBackend`. Reversible at any time by setting
  the flag back to `false`; no deploy needed and already-migrated clips are
  unaffected. (A percentage ramp was considered and dropped — a boolean is simpler
  and the blast radius is one clip at a time.)

### 5.2 Priority #2 — view/stats aggregation — **variant E implemented 2026-10-02**

Built (commits `606509e`, `5221254`); **server half not yet deployed** — see 11.6.

- **`playbackStats` is sampled** at `kTvPlaybackStatsSampleRate` = 10%
  (`lib/features/tv_market/utils/tv_playback_sampling.dart`). Every metric it feeds
  is an *average*, so a uniform sample does not shift it — proven over 200k draws in
  `test/features/tv_market/tv_playback_sampling_test.dart`.
- **`tv_public_profiles.totalViewCount` moved to the server.** The third write (and
  second read) is gone from `recordView`. `reconcileTvProfileViews` recomputes it
  nightly at 03:30 Tashkent as *live clips' `viewCount` + `deletedViewCount`*.
- **`deletedViewCount`** is accumulated by `onTvClipDeleted`; without it a profile's
  total would jump backwards whenever an owner deleted a clip.
- **First-run seeding:** today's `totalViewCount` was built incrementally by clients
  and already includes views of clips that have since been deleted. On the first run
  the field is seeded as `max(0, oldTotal − liveSum)` so no profile's total drops.
- **Transition is self-healing:** older app versions still increment
  `totalViewCount` themselves (the rule still allows it); the next nightly pass
  simply corrects the value.
- **The audit script was adapted** (`functions/tools/audit_avagram_usage.js`), which
  mattered because it is the input to the "should we drop video?" decision: averages
  come from `playbackStats`, absolute counts now come from `viewCount` (exact,
  deduped), and total watch time and traffic are estimated as *average × viewCount*
  and labelled as estimates. `PLAYBACK_STATS_SAMPLE_RATE` must match the Dart
  constant — a test enforces it, same pattern as `TV_CLIP_MAX_SECONDS`.

The client half only takes effect in the next app release.

### 5.2b Why not the queue (Section 3)
**Why:** removes hot-document contention — the real user-visible win is write latency.
On cost, see the re-derived table in §3: at 1M DAU the best queue variant is
$3,834 → $1,233/mo, but at 10k DAU the whole line is $38/mo, so cost is not the
reason to do this yet. Start with variant E (client-side, no infrastructure); build
the Pub/Sub queue (C) only once the DAU justifies it.

### 5.3 Priority #3 — feed JSON (Section 4)
**Why:** $1,800 → $0/mo at 1M, feed latency ~200ms → ~50ms. Author-own-clip query
keeps instant visibility.

> Note: at 10k–100k DAU the absolute savings from #2 and #3 are small (tens to low
> hundreds of dollars). Their value there is latency/contention, not cost. #1 is
> worth doing at **every** tier ($3,600/mo even at 10k DAU).

---

## 6. R2 vs Firebase — the egress delta (from script)

| | 10k DAU | 100k DAU | 1M DAU |
|---|-------:|---------:|-------:|
| Firebase egress | $3,600 | $36,000 | $360,000 |
| R2 via Cloudflare egress | $0 | $0 | $0 |
| **Monthly saving** | **$3,600** | **$36,000** | **$360,000** |

- R2 egress is **$0** when served through Cloudflare (peering). R2's `$0.015/GB` is
  the **at-rest storage** rate, not egress.
- Cloudflare enterprise pricing at PB scale is negotiated separately and is the one
  genuine unknown — but even a conservative CF bill would have to exceed $360k/mo to
  lose, which is implausible. **Get a written CF quote before 300k DAU.**

---

## 7. iOS (deferred to App Store launch)

### 7.1 Audit

| Feature | Android | iOS | Code |
|---------|---------|-----|------|
| Player | video_player (Media3/ExoPlayer) | video_player (AVPlayer) | tv_clip.dart:232 |
| HLS playback | ✅ | ✅ (AVPlayer plays HLS) | shared path |
| Segment prefetch | ✅ Media3 SimpleCache | ❌ no-op | tv_segment_prefetcher.dart:25-26 |
| MP4 local cache | ✅ | ⚠️ same code, untested | tv_clip_cache_service.dart |
| Network quality / start bitrate / "save traffic" | ✅ | ✅ (Connectivity, shared) | tv_network_quality_service.dart |
| Playback analytics (first frame, rebuffer) | ✅ | ✅ (shared recorder) | tv_playback_analytics_recorder.dart |

`TvSegmentPrefetcher._supported = !kIsWeb && TargetPlatform.android`
(tv_segment_prefetcher.dart:25-26) → on iOS every prefetch call is a **no-op**: the
iOS player streams each clip from the network with no pre-warmed segments. HLS still
plays (AVPlayer), analytics and bitrate selection still work; only prefetch/caching
is missing.

### 7.2 Deferred tasks (do when iOS ships on the App Store)
- Configure AVPlayer `preferredForwardBufferDuration` from Dart (platform channel)
  so NEXT buffers ahead.
- Port `AvaMediaCache` to iOS (URLSession interception + on-disk HLS segment cache)
  to match Android's pre-warmed segments.
- Then enable the same adaptive-timeout prefetch logic already in
  `TvNetworkQualityService`.

Rationale for deferral: no iOS users on production until App Store launch; the R2+CF
work (5.1) benefits iOS automatically once URLs point at `video.ava-uz.com`.

---

## 8. Measuring the upload→ready time

The earlier "4–5 min" figure was **not measured** and does not reconcile with the
stage sum (upload ~10–30s + FFmpeg ~20–120s + metadata <1s ≈ 1–3 min). Do not quote
a number until it is measured.

**What exists:** `transcodeTvClipVideo` already logs per-stage seconds
(`download Xs`, `hls Xs`, `JAMI Xs / 540s budjet`, index.js:12409, 12602, 12607).
That covers server processing only.

**Proposal to measure end-to-end (no product code here — design only):**
1. Write Firestore timestamps at each boundary on the clip doc:
   `uploadedAt` (client, upload complete) → `processingStartedAt` →
   `fastTrack360pReadyAt` → `processingReadyAt` (full ladder).
2. Author-perceived "ready" = `fastTrack360pReadyAt − uploadedAt` (this is when the
   author can actually watch; the full ladder finishing later doesn't block playback).
3. Aggregate p50/p90 of each delta in the KPI dashboard.
4. Separately, client-side: time from publish tap to the clip appearing playable in
   the feed (covers upload + the own-clip query from Section 4).

Only after collecting these can "upload→ready" be stated as a measured p50/p90.

---

## 9. Out of scope (later)
- Backfill old clips Storage → R2 (bulk) and decommission the Storage video bucket.
- Automatic moderation classifier → external API.
- iOS native segment cache (Section 7.2), post-launch.
- Personalized recommendation feed (replaces the region/category JSON pools).

---

## 10. Branch layout

```
feat/home-redesign              ← production's functions are already THIS
 └── feat/r2-output             R2 backend behind the flag (not pushed, not deployed)

main
 └── feat/clip-run-id   b2af583 runId hand-ported onto main — SUPERSEDED, see 10.1
```

### 10.1 Why `feat/r2-output` sits on `feat/home-redesign`, not on `main`

The first plan was to decouple R2 from the UI release by hand-porting the `{runId}`
work onto `main` (`feat/clip-run-id`) and stacking R2 on that. **A read-only check of
production invalidated it.** Twelve most-recently-updated clips:

```
variantRun bor    : 12/12
variantLadder bor : 12/12   (ladder = 3)
R2 (video.ava-uz) : 0/12
```

Production is already running `feat/home-redesign`'s functions — runId *and* the
short-edge ladder v3. Deploying from a `main`-based branch would have **rolled back**
the ladder, the watermark/share copy and the social changes. There was nothing to
decouple: the coupling already exists in production.

So `feat/r2-output` was rebuilt on `feat/home-redesign`. `feat/clip-run-id` is kept
only as an optional "catch `main` up to production" branch; it is not on the R2 path.

> Process risk worth addressing separately: **production was deployed from a feature
> branch, and `main` is behind it.** Until that is reconciled, "deploy from main" is
> not safe for functions.

### 10.2 What `feat/clip-run-id` deliberately left behind

(Still accurate for that branch; irrelevant to the R2 path now that the base is
`feat/home-redesign`, which contains all of it.)

`19f7d1f` bundles two independent pipeline changes. Only the first was ported:

| | Ported to `feat/clip-run-id` | Why / why not |
|---|---|---|
| **runId / versioned paths** | ✅ yes | What R2 needs; server-only, invisible to the client |
| **Ladder rework** (`tvClipScaleExpr`, `TV_CLIP_LADDER_VERSION`, short-edge scaling, CRF/maxrate) | ❌ no | Changes encoded output (406×720 @2140k → 720×1280 @3000k). It was validated on-device **together with** the client ABR patches (`AvaBandwidthMeter`, `AvaTrackSelection`), which are not in the production client. Shipping it server-only could push a 3000k variant to a client tuned for the old ladder. It ships with its own client half, via `feat/home-redesign`. |
| **Watermark / share copy** (`renderShareCopyIfPossible`) | ❌ no | Does not exist on `main`; it came from `1c461cc`, which drags a 3-commit chain through `tv_social_publish.js` (`bafe6db` → `c578e02` → `1c461cc`) — an unrelated feature area |

Also included (approved separately, 4 lines): `onTvClipDeleted` and
`deleteTvClipMedia` now delete the `tv_clip_hls/{clipId}/` prefix too. They only
deleted `tv_clip_variants/`, so every deleted clip left its HLS segments — the
largest files — in Storage forever.

### 10.3 Merge path and the one remaining conflict risk

Intended path: `feat/r2-output` → `feat/home-redesign` → `main`. Because R2 now sits
directly on `feat/home-redesign`, that first merge is a fast-forward — **no conflict**.

The remaining risk is `feat/clip-run-id`. If it is ever merged to `main` *and*
`feat/home-redesign` is merged too, both sides will contain independently-written
runId code and `functions/index.js` will conflict around the TV pipeline
(`fastTrack360pIfPossible`, `packageTvClipHls`, `transcodeTvClipVideo`,
`onTvClipDeleted`, `deleteTvClipMedia`).

**Resolution rule: take the `feat/home-redesign` side wholesale** — it is what
production already runs, and it is a superset (runId + ladder + share). Then keep two
things that exist only on the `feat/clip-run-id` side:

1. `functions/tv_clip_runs.js` — the cleanup decision as a tested pure module.
   `feat/home-redesign` has that logic inline in `cleanupOldTvClipRuns`; keep the
   module, delete the inline copy, call `staleRunFiles`.
2. The `tv_clip_hls/` deletion lines in `onTvClipDeleted` / `deleteTvClipMedia` —
   verify they are present exactly once, not duplicated.

Simplest alternative: **do not merge `feat/clip-run-id` at all.** Once
`feat/home-redesign` reaches `main`, that branch's only unique content is item 1
above, which can be cherry-picked on its own.

**Verification after any such merge:** `npm run test:tv-clip-runs` and
`npm run test:tv-clip-output` must both pass (25 + 67 assertions). They cover exactly
the invariants a bad resolution breaks: old unversioned clips must survive cleanup,
the flag-off path must produce byte-identical Firebase paths and URLs, and deletion
must reach whichever backend the clip actually lives on.

---

## 11. Deploy

### 11.1 What is actually running in production

Verified by downloading the deployed source, not by inference:

```
gcloud functions describe onTvClipCreatedV2 --gen2 --region=us-central1 \
  --format="value(buildConfig.source.storageSource.bucket,...object,...generation)"
gsutil cp gs://<bucket>/onTvClipCreatedV2/function-source.zip#<generation> .
```

Deployed `updateTime`: **2026-09-26T15:41:43Z**. Diffed against
`feat/home-redesign:functions/index.js`: **6 insertions / 92 deletions**, and *none*
of it touches the TV pipeline (checked for `tv_clip`, `TV_CLIP`, `transcodeTvClip`,
`packageTvClipHls`, `fastTrack360`, `variantRun`, `variantLadder`, `onTvClip`,
`renderShareCopy` — zero hits).

**So production's TV pipeline is already identical to `feat/home-redesign` HEAD.**

What production is **missing** (committed after that deploy, or in the same commit
but written the next day):

| Undeployed | From |
|---|---|
| Realty cluster (`attachRealty`, `realty.js`) | `7e43f82` … `76f52ba` (2026-09-28/29) |
| Market ad re-post fix (`marketPendingExpiresAt`, `autoExpired` notification) | `19f7d1f` |
| `marketAdGeoStamp` — ad region from the product, not the seller | `19f7d1f` |

`19f7d1f` was committed 2026-09-27 15:20 — *after* the deploy. The deploy was made
from the working tree on 2026-09-26, which already had the ladder/runId work but not
yet that commit's market-ad half. This is why production has `variantLadder: 3` while
lacking `marketAdGeoStamp` from the same commit.

> Also noted: the branch's `functions/index.js` has a UTF-8 **BOM** that the deployed
> copy does not. Harmless for Node, but it means the file was rewritten by a tool
> that adds one. Avoid `Set-Content`/`Out-File` on this file.

### 11.2 Deploy narrowly — a broad deploy is not safe

`firebase deploy --only functions` would also ship the three undeployed items above.
The `marketAdGeoStamp` one is the В-8 trap: the code expects a `districtId` rule that
is **not deployed** in `firestore.rules`. So the deploy must name functions explicitly.

```
firebase deploy --only functions:onTvClipCreatedV2,functions:onTvClipVideoReplacedV2,functions:onTvClipBackfillRequested,functions:onTvClipDeleted,functions:expireTvContent
```

Why exactly these five, and nothing else — the changed code is reachable only from
them:

| Function | Why |
|---|---|
| `onTvClipCreatedV2` | calls `transcodeTvClipVideo` (new output, flag, cleanup); new `secrets` |
| `onTvClipVideoReplacedV2` | same code path and same options object |
| `onTvClipBackfillRequested` | same code path and same options object |
| `onTvClipDeleted` | now calls `purgeTvClipOutputs` (R2 delete + CDN purge); new `secrets` |
| `expireTvContent` | calls `deleteTvClipMedia` → `purgeTvClipOutputs`; new `secrets` |

`transcodeEntertainmentVideo`, `hlsSpikeTranscode`, `deleteHlsSpike` and `clipPage`
are untouched. The only edit near `transcodeEntertainmentVideo` was deleting a
now-unused `TV_CLIP_CACHE_CONTROL` constant it never referenced.

Verified before deploy: `index.js` loads (242 exports) and all five functions carry
exactly the three secrets — `CLOUDFLARE_ZONE_ID` is deliberately absent, since it was
never created in Secret Manager and would otherwise fail the deploy.

**No `firestore.rules` deploy is needed** for this change (see §5.1) — and per the
В-8 incident, rules always get their own command anyway.

### 11.3 Verification — done 2026-10-01/02, without a device

A clip can be put through the whole pipeline server-side: create a `tv_clips` doc
with `status: 'pending'` and a `videoUrl` pointing at an uploaded test video. The
transcode trigger fires, the clip stays out of the feed (feed queries
`status == 'active'`) and `onTvClipSocialPublish` does **not** fire — it requires the
status to *become* `active`, so nothing is posted to Instagram or Facebook. Deleting
the doc exercises the delete + purge path.

| Check | Result |
|---|---|
| Flag off | `variantBackend: firebase`, 5/5 outputs on Storage, all under `{runId}` |
| Firebase delete | both `tv_clip_variants/` and `tv_clip_hls/` prefixes emptied |
| Allowlist on (one phone) | `variantBackend: r2`, 5/5 on `video.ava-uz.com`, no tokens in URLs |
| Phone normalization | list held `+998 90 000-00-00`, clip had `998900000000` → matched |
| **Isolation** | two clips created at once, only the listed owner went to R2; the other stayed on Firebase (5/5 each way) |
| CDN cache | `.m3u8`, `.ts`, `.mp4`: MISS → **HIT**; correct Content-Type each; `immutable` |
| Delete + purge | 5 URLs went 200 → **404**; log: `R2 12 obyekt o'chdi, 12 URL edge keshdan chiqarildi` (12 = 12, so purge was complete) |
| Global flag | list empty, flag true, unlisted phone → `variantBackend: r2` |
| Transcode time | 10.0s / 540s budget |

Note on ordering: `processingStatus: 'ready'` is written by the fast-track 360p pass
(~4–9s) **before** `variantBackend`/`variantRun` land in the final update (~10s).
`resolveClipBackend` covers that window by falling back to the URL host, and the
fast-track URL is already the R2 one — verified.

### 11.7 Phase 3 — feed JSON builder (server half) — built 2026-10-02

Commit `52f6ae1`. **Not deployed** (see 11.8). The client does not read this yet, so
the builder only writes; nothing changes until the next app release.

Sized from real data rather than guessed: **228 active clips, 7 districts, 3 tabs,
~1787 B per clip** — so at most 21 pools and a 20-clip page is ~35 KB. That is small
enough that a plain full rebuild every 5 minutes is the right design; no dirty-pool
tracking needed yet.

- `functions/tv_feed.js` — the **pure** decisions (pool path, which fields, tab
  matching, pagination). No Firestore, no R2, so it is tested without either:
  `functions/test/tv_feed.test.js`, 25 assertions.
- `buildTvFeedJson` (every 5 min) reads active clips once, groups by district, and
  writes `feed/v1/{districtId}/{tab}/p{n}.json` to R2, deleting pages left over from
  a shrunken pool.
- `R2Output.putJson` — unlike clip files this is **not** `immutable`: the feed
  changes, so it gets a short `max-age` plus `stale-while-revalidate`.
- Tabs mirror the client's `_categoriesForTab`: `all` / `news` / `market`.
- Only feed-relevant fields are emitted — `playbackStats`, `socialPost`,
  `processedVideoUrl`, `variantRun` and friends are dropped. `createdAt` becomes
  `createdAtMs` because a Firestore Timestamp has no JSON form.
- An empty pool still gets one empty page, so the client sees `[]` rather than a 404.

**Needed in Cloudflare before the client switches over:** the current Cache Rule
matches `m3u8 ts m4s mp4 webp` only, so `.json` is not cached at the edge and the
latency win would not materialise. Add `json` to the extension list (its own short
TTL comes from the object's own `Cache-Control`).

**Known gap in v1:** region/national-scoped ads (`_fetchScopedAds`) are not included —
see 11.9.

**Scaling limit:** every run reads all active clips. Past roughly 2,000 active clips
those reads outgrow the savings, and only changed pools should be rebuilt.

### 11.7b Phase 3 — client half, built 2026-10-02 (commit `d567e1c`)

Takes effect only in the next app release; until then the feed behaves exactly as it
does today.

- **`TvClip.fromMap`** — `fromFirestore` now delegates to it, so both sources share
  one parser. They differ only in how a date arrives (Firestore `Timestamp` vs the
  JSON's `createdAtMs`), which `_asDate` absorbs. Adding a field later feeds both
  sources automatically instead of letting two parsers drift apart.
- **`TvFeedCdn`** is an *optional* source. It returns `null` — and the caller falls
  back to Firestore — when the JSON is missing (404), unparseable, on a different
  schema version, older than 6 hours (builder stopped), or the network fails. One
  malformed clip is skipped rather than breaking the whole feed. This is what makes
  the release safe before the builder is deployed.
- **The feed screen picks the source once per load cycle.** If page 1 came from the
  CDN, later pages do too; if the CDN fails, it drops to Firestore and does not retry
  within that cycle. `_loadMoreClips` already de-duplicates, so a mid-cycle switch
  cannot double up clips. Only the **district** feed uses the CDN — region and
  unfiltered modes are untouched, since the server builds no pools for them.
- **The author sees their own clip immediately.** The JSON can be up to 5 minutes
  stale, so someone could publish and not find their video — and conclude it was
  lost. When reading from the CDN the screen also pulls that user's latest clips
  (1 user, ≤5 docs) and puts them at the top.

Tests: `test/features/tv_market/tv_feed_cdn_test.dart` — 17 assertions, half of them
exercising the fallback path specifically. Full suite: 430 passing, analyzer clean.

### 11.8 Deploy blocked 2026-10-02 — Secret Manager returns a billing error

`firebase deploy --only functions:buildTvFeedJson` fails at secret validation:

```
Failed to validate secret versions:
403 This API method requires billing to be enabled ... projects/master-taxi-gurlan
```

What was checked:

| Check | Result |
|---|---|
| `gcloud billing projects describe` | `billingEnabled: True`, account `0185D6-…` |
| `gcloud secrets versions list` (R2 keys) | same 403 — so it is the API, not the CLI |
| `gcloud billing accounts describe` | the signed-in account lacks permission to view it |
| Firestore read | works |
| Deployed functions | still running (`expireTvContent` 3 min earlier), no errors in 30 min |

So **production is unaffected**; only APIs that strictly require a chargeable billing
account are refusing. Earlier deploys today succeeded, so this began within hours.
Most likely the billing account itself needs attention (closed, payment failed, or a
verification hold) — only the owner can see that.

Any function declaring `secrets:` is blocked until it clears. Pending:
`buildTvFeedJson`.

### 11.9 Defect found while measuring — `regionId` is empty on every clip

All 228 active clips have `districtId`, and **none has `regionId`**. Consequences:

- `_fetchScopedAds` (`tv_clips_repository.dart:124`) filters on
  `adScope in ['region','national']` and then matches `c.regionId == regionId`, so a
  region-wide paid ad can never appear in another district's feed. Whoever paid for
  regional reach is not getting it.
- `fetchByRegion` survives only because it works from the district list rather than
  the clip's own `regionId` — the repository comment already notes clips may lack it.

Not fixed here (outside this phase). A fix needs a backfill from `districtId` →
`geo_districts.regionId` plus writing `regionId` at publish time.

### 11.6 Pending deploy — `reconcileTvProfileViews`, `onTvClipDeleted`

```
firebase deploy --only functions:reconcileTvProfileViews,functions:onTvClipDeleted
```

Blocked on 2026-10-02: a parallel session is actively editing `functions/realty.js`.
`firebase deploy` packages the **working tree, not the commit**, so a deploy during
that would bundle half-written code into these two functions (one attempt already
failed on a vanishing `realty.js.tmp.*`). Wait until that file stops changing.

After deploying, prove the seeding worked — the first run must not lower anyone's
total:

1. Snapshot `tv_public_profiles` (`totalViewCount` per doc) before.
2. `gcloud scheduler jobs run firebase-schedule-reconcileTvProfileViews-us-central1
   --location=us-central1`
3. Re-read and compare: no profile's `totalViewCount` may drop, and every profile
   should gain a `deletedViewCount` field.

Baseline captured before the attempt: **105 profiles, `totalViewCount` sum = 125,
0 profiles carrying `deletedViewCount`.**

### 11.4 Original uploads on clip delete — fixed 2026-10-02

**Was:** `onTvClipDeleted` removed only the *processed* outputs. The user's original
upload at `tv_clips/{phone}/{file}.mp4` (~20–80 MB) and its poster were deleted only
by `deleteTvClipMedia`, which runs on news expiry — so a clip the user deleted
themselves left its original behind forever, growing the storage line in
`cost_model.py`.

**Now:** `onTvClipDeleted` calls `deleteTvClipMedia`, so both delete paths (owner
deleted / expired) go through one function and cannot drift apart. The owner confirmed
that "restore a deleted clip" is not a wanted feature.

Ad clips keep their files **on expiry** on purpose (possible reactivation) — that
decision stays in `expireTvContent`, which simply does not call the function for them.
Deleting the document removes an ad's files too.

Verified live on a test clip: before delete, 2 files under `tv_clips/{phone}/`; after,
0 — plus the log line `R2 12 obyekt o'chdi, 12 URL edge keshdan chiqarildi`.

### 11.5 Original verification plan (for reference)

1. **Flag off** — publish a clip. Expect `chiqish backend = firebase` in the logs,
   `tv_clip_variants/{clipId}/{runId}/…` URLs, `variantBackend: 'firebase'`, playback
   normal, old clips unaffected.
2. **Flag on for one phone** — set `server_config/tv_r2` → `owners: ["99894…"]`
   (Firebase Console; the doc is server-only by design). Publish from that phone.
   Expect `chiqish backend = r2`, `hlsUrl` on `https://video.ava-uz.com/processed/…`,
   `variantBackend: 'r2'`. A clip from any other phone must still go to Firebase.
3. **Cache** — `curl.exe -sSI` the master playlist twice: `cf-cache-status` `MISS`
   then `HIT`; `content-type` correct per extension; `cache-control` immutable.
   Repeat for the `.ts` segment (largest object, and the reason `.ts` is in the Cache
   Rule).
4. **Delete** — delete the test clip. Expect in the logs
   `R2 n obyekt o'chdi, n URL edge keshdan chiqarildi`, then `curl.exe -sSI` the same
   URLs → **404**. A 200 here means purge did not take effect; check the token's
   Zone.Cache Purge permission.
5. **Re-transcode** (optional) — set `backfillVariantsAt` on an R2 clip. The live run
   must keep playing throughout; the superseded run is deleted and purged afterwards.

---

**Status:** Cost model written and run; all figures above trace to
`docs/video-architecture/cost_model.py`. Recommended order: R2+Cloudflare (new
clips, flagged) → view/stats aggregation → feed JSON. iOS deferred to App Store
launch.
