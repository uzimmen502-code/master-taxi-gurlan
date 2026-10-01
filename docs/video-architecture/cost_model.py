#!/usr/bin/env python3
"""
AVA Video — cost model (analysis tool, NOT product code).

Single source of truth for every number in TASK.md. Change a parameter here,
re-run, and copy the printed numbers into the document. Do not hand-write any
cost figure that this script does not produce.

Usage:
    python docs/video-architecture/cost_model.py

Units: GB = 1000 MB (decimal, how Cloud providers bill). Month = 30 days.
"""

# ─────────────────────────────────────────────────────────────────────────
# PARAMETERS (given)
# ─────────────────────────────────────────────────────────────────────────
VIEWS_PER_DAU_DAY = 20          # one view = one playback impression
MB_PER_VIEW = 5                 # bytes streamed per playback (artifact target)
FEED_LOADS_PER_DAU_DAY = 5      # how many times a user opens/refreshes the feed
DOCS_PER_PAGE = 20              # Firestore returns N docs per feed query -> N reads
EGRESS_USD_PER_GB = 0.12        # Firebase Storage egress (R2 via Cloudflare = 0)
WRITE_USD_PER_1M = 1.80         # Firestore document write
READ_USD_PER_1M = 0.60          # Firestore document read
R2_STORAGE_USD_PER_GB = 0.015   # R2 at-rest storage per month

DAYS = 30
MB_PER_GB = 1000                # decimal GB (matches "3 PB" framing)

# ─────────────────────────────────────────────────────────────────────────
# WRITE MULTIPLIERS (read from the code, documented so they live in the script)
# ─────────────────────────────────────────────────────────────────────────
# recordView() transaction writes: views/{viewer} + clip.viewCount +
#   profile.totalViewCount  (tv_clips_repository.dart:561-567). Deduped 1/24h,
#   but each distinct view still costs this many document writes.
VIEW_WRITES_PER_VIEW = 3
# recordPlaybackStats() -> one update with increment fields
#   (tv_clips_repository.dart:588-604). Not deduped: one per playback.
STATS_WRITES_PER_VIEW = 1

# After merging view+stats into ONE client event:
#   1) client appends one lightweight event per playback (ingest log)
#   2) server sums per clip and flushes counters every AGG_INTERVAL_MIN
# So optimized writes = ingest(1 x views) + counter_flush(active_clips x intervals).
# active_clips is content-bound (the hot catalog), NOT 1:1 with DAU. Modeled as
# DAU * ACTIVE_CLIP_RATIO, capped at CATALOG_HOT_CAP.
MERGED_WRITES_PER_VIEW = 1      # one ingest event per playback (was 4: 3 view + 1 stats)
ACTIVE_CLIP_RATIO = 0.02        # distinct clips touched per interval ~= DAU * this
CATALOG_HOT_CAP = 50_000        # upper bound on distinct clips in the hot set
AGG_INTERVAL_MIN = 5            # server flushes aggregated counters every N min

# ─────────────────────────────────────────────────────────────────────────
# STORAGE ASSUMPTIONS (needed for the R2 storage line; documented defaults)
# ─────────────────────────────────────────────────────────────────────────
UPLOAD_FRACTION = 0.01          # 1% of DAU upload one clip per day
PROCESSED_MB_PER_CLIP = 25      # 3 MP4 variants + HLS single-file segments
STORAGE_MONTHS = 12             # accumulation window (run-rate at month 12)


def model(dau):
    views = dau * VIEWS_PER_DAU_DAY * DAYS                 # views / month
    egress_gb = views * MB_PER_VIEW / MB_PER_GB            # GB / month

    # Egress
    egress_firebase = egress_gb * EGRESS_USD_PER_GB
    egress_r2 = 0.0

    # Writes (current)
    view_writes = views * VIEW_WRITES_PER_VIEW
    stats_writes = views * STATS_WRITES_PER_VIEW
    view_write_cost = view_writes / 1e6 * WRITE_USD_PER_1M
    stats_write_cost = stats_writes / 1e6 * WRITE_USD_PER_1M

    # Writes (merged + aggregated): one ingest event per playback + server
    # counter flush per active clip per interval.
    intervals_month = DAYS * 24 * 60 / AGG_INTERVAL_MIN
    active_clips = min(dau * ACTIVE_CLIP_RATIO, CATALOG_HOT_CAP)
    ingest_writes = views * MERGED_WRITES_PER_VIEW
    flush_writes = active_clips * intervals_month
    agg_writes = ingest_writes + flush_writes
    agg_write_cost = agg_writes / 1e6 * WRITE_USD_PER_1M

    # Feed reads (current): one read per returned document
    feed_loads = dau * FEED_LOADS_PER_DAU_DAY * DAYS
    feed_reads = feed_loads * DOCS_PER_PAGE
    feed_read_cost = feed_reads / 1e6 * READ_USD_PER_1M
    # Feed JSON (pre-built): 0 Firestore reads
    feed_json_cost = 0.0

    # R2 storage (at month STORAGE_MONTHS)
    clips_total = dau * UPLOAD_FRACTION * DAYS * STORAGE_MONTHS
    storage_gb = clips_total * PROCESSED_MB_PER_CLIP / MB_PER_GB
    r2_storage_cost = storage_gb * R2_STORAGE_USD_PER_GB

    # Totals
    baseline = (egress_firebase + view_write_cost + stats_write_cost
                + feed_read_cost + r2_storage_cost)
    optimized = (egress_r2 + agg_write_cost + feed_json_cost + r2_storage_cost)

    # Per 1,000 views
    v1k = 1000
    egress_fb_1k = v1k * MB_PER_VIEW / MB_PER_GB * EGRESS_USD_PER_GB
    egress_r2_1k = 0.0
    writes_cur_1k = (VIEW_WRITES_PER_VIEW + STATS_WRITES_PER_VIEW) * v1k / 1e6 * WRITE_USD_PER_1M
    writes_agg_1k = MERGED_WRITES_PER_VIEW * v1k / 1e6 * WRITE_USD_PER_1M  # ingest only (flush amortized)
    # feed reads attributable to 1000 views: (feed_loads/views) * docs * read_price
    reads_1k = (FEED_LOADS_PER_DAU_DAY / VIEWS_PER_DAU_DAY) * v1k * DOCS_PER_PAGE / 1e6 * READ_USD_PER_1M
    per1k_baseline = egress_fb_1k + writes_cur_1k + reads_1k
    per1k_optimized = egress_r2_1k + writes_agg_1k + 0.0

    return {
        "dau": dau, "views": views, "egress_gb": egress_gb,
        "egress_firebase": egress_firebase, "egress_r2": egress_r2,
        "view_write_cost": view_write_cost, "stats_write_cost": stats_write_cost,
        "agg_write_cost": agg_write_cost,
        "feed_read_cost": feed_read_cost, "feed_json_cost": feed_json_cost,
        "r2_storage_cost": r2_storage_cost, "storage_gb": storage_gb,
        "baseline": baseline, "optimized": optimized,
        "per1k_baseline": per1k_baseline, "per1k_optimized": per1k_optimized,
        "egress_fb_1k": egress_fb_1k, "reads_1k": reads_1k,
        "writes_cur_1k": writes_cur_1k, "writes_agg_1k": writes_agg_1k,
    }


def fmt(x):
    if x >= 1000:
        return f"${x:,.0f}"
    if x >= 1:
        return f"${x:,.2f}"
    return f"${x:.4f}"


def pb(gb):
    if gb >= 1e6:
        return f"{gb/1e6:.1f} PB"
    if gb >= 1e3:
        return f"{gb/1e3:.0f} TB"
    return f"{gb:.0f} GB"


if __name__ == "__main__":
    tiers = [10_000, 100_000, 1_000_000]
    rows = [model(d) for d in tiers]

    def line(label, key, formatter=fmt):
        cells = "  ".join(f"{formatter(r[key]):>14}" for r in rows)
        print(f"{label:<34}{cells}")

    print("=" * 80)
    print("AVA VIDEO — MONTHLY COST MODEL")
    print("=" * 80)
    hdr = "  ".join(f"{d:>14,}" for d in tiers)
    print(f"{'DAU':<34}{hdr}")
    print("-" * 80)
    line("Views / month", "views", lambda v: f"{v:,.0f}")
    line("Egress volume", "egress_gb", pb)
    print("-" * 80)
    print("CURRENT (Firebase Storage + unbatched Firestore)")
    line("  Egress (Firebase)", "egress_firebase")
    line("  View writes (x3)", "view_write_cost")
    line("  Stats writes (x1)", "stats_write_cost")
    line("  Feed reads (20 docs/load)", "feed_read_cost")
    line("  R2 storage (if used)", "r2_storage_cost")
    line("  = BASELINE TOTAL", "baseline")
    print("-" * 80)
    print("OPTIMIZED (R2+Cloudflare egress=0, merged+aggregated events, JSON feed)")
    line("  Egress (R2 via Cloudflare)", "egress_r2")
    line("  Aggregated writes", "agg_write_cost")
    line("  Feed JSON reads", "feed_json_cost")
    line("  R2 storage", "r2_storage_cost")
    line("  = OPTIMIZED TOTAL", "optimized")
    print("-" * 80)
    print("COST PER 1,000 VIEWS")
    line("  Firebase baseline", "per1k_baseline")
    line("    of which egress", "egress_fb_1k")
    line("    of which feed reads", "reads_1k")
    line("    of which writes", "writes_cur_1k")
    line("  R2+optimized", "per1k_optimized")
    print("=" * 80)
