// AVA patch #2 (vendored video_player_android 2.9.5).
//
// Media3 SimpleCache: ExoPlayer o'qigan har bir HLS segment/playlist diskka
// yoziladi va keyingi o'qishda (orqaga svayp, qayta kirish, `releaseAll()`dan
// keyin resume) tarmoqsiz keladi. Qo'shimcha: `prefetch()` — ExoPlayer
// instance YARATMASDAN (RAM ≈ 0) keyingi klipning master playlist + eng past
// variant media playlist + birinchi N soniya segmentlarini `CacheWriter`
// bilan shu kesh'ga oldindan yozadi. Svaypda player ochilganda birinchi
// frame keshdan keladi.
//
// O'lchov (TECNO LH7n, 4G): svayp → play() o'rtacha 2.9 s, NEXT player hech
// qachon tayyor bo'lmagan (current "sog'lom" bo'lguncha prefetch
// boshlanmaydi). Ikkinchi ExoPlayer instance yo'li yopiq — PSS 516 MB.
package io.flutter.plugins.videoplayer;

import android.content.Context;
import android.net.Uri;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.media3.common.C;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.common.util.UriUtil;
import androidx.media3.database.StandaloneDatabaseProvider;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DataSourceInputStream;
import androidx.media3.datasource.DataSpec;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.datasource.cache.CacheDataSource;
import androidx.media3.datasource.cache.CacheWriter;
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor;
import androidx.media3.datasource.cache.SimpleCache;
import androidx.media3.exoplayer.hls.playlist.HlsMediaPlaylist;
import androidx.media3.exoplayer.hls.playlist.HlsMultivariantPlaylist;
import androidx.media3.exoplayer.hls.playlist.HlsPlaylist;
import androidx.media3.exoplayer.hls.playlist.HlsPlaylistParser;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@UnstableApi
public final class AvaMediaCache {
  private AvaMediaCache() {}

  private static final String TAG = "AvaMediaCache";
  private static final String DIR = "tv_media3";
  /// Disk chegarasi — LRU. `getCacheDir()` ichida, OS zarurat bo'lsa tozalaydi.
  private static final long MAX_BYTES = 150L * 1024 * 1024;
  private static final int BUFFER = 64 * 1024;

  @Nullable private static SimpleCache cache;
  private static final ExecutorService prefetchExecutor = Executors.newSingleThreadExecutor();
  /// Hozir kerak bo'lgan URL'lar (`TvPlayerPool._wanted` andozasi): `markWanted()`
  /// ro'yxatda yo'q ishlarni bekor qiladi — forward svaypda oldingi NEXT/NEXT+1
  /// (= yangi CURRENT/NEXT) davom etaveradi, faqat chetga chiqqanlar to'xtaydi.
  private static final Set<String> wanted = ConcurrentHashMap.newKeySet();
  @Nullable private static volatile CacheWriter activeWriter;
  @Nullable private static volatile String activeUrl;

  @NonNull
  public static synchronized SimpleCache get(@NonNull Context context) {
    if (cache == null) {
      File dir = new File(context.getApplicationContext().getCacheDir(), DIR);
      cache =
          new SimpleCache(
              dir,
              new LeastRecentlyUsedCacheEvictor(MAX_BYTES),
              new StandaloneDatabaseProvider(context.getApplicationContext()));
    }
    return cache;
  }

  /**
   * Upstream'ni kesh bilan o'raydi. Kesh ochilmasa (disk/DB xatosi) — upstream
   * o'zgarishsiz qaytadi, playback hech qachon shu sabab to'xtamaydi.
   * `FLAG_BLOCK_ON_CACHE`: prefetch writer segmentni yozayotgan paytda player
   * uni qayta tarmoqdan tortmaydi — writer tugashini kutadi (o'lchandi: flag'siz
   * ikkalasi parallel yuklab, init 1–4 s edi).
   */
  @NonNull
  public static DataSource.Factory wrap(
      @NonNull Context context, @NonNull DataSource.Factory upstream) {
    try {
      return new CacheDataSource.Factory()
          .setCache(get(context))
          .setUpstreamDataSourceFactory(upstream)
          .setFlags(
              CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR
                  | CacheDataSource.FLAG_BLOCK_ON_CACHE)
          .setEventListener(
              new CacheDataSource.EventListener() {
                @Override
                public void onCachedBytesRead(long cacheSizeBytes, long cachedBytesRead) {
                  // Har open'da bir marta — kesh hit o'lchovi (logcat: AvaMediaCache).
                  Log.d(TAG, "hit cachedRead=" + cachedBytesRead + " cacheSize=" + cacheSizeBytes);
                }

                @Override
                public void onCacheIgnored(int reason) {
                  Log.d(TAG, "cache ignored reason=" + reason);
                }
              });
    } catch (RuntimeException e) {
      Log.w(TAG, "cache unavailable, upstream only: " + e);
      return upstream;
    }
  }

  /**
   * Endi faqat [urls] kerak: ro'yxatda yo'q kutayotgan/ishlayotgan prefetch'lar
   * bekor qilinadi (ishlayotgani — `CacheWriter.cancel()` bilan darhol).
   */
  public static void markWanted(@NonNull List<String> urls) {
    wanted.clear();
    wanted.addAll(urls);
    CacheWriter w = activeWriter;
    String u = activeUrl;
    if (w != null && u != null && !wanted.contains(u)) w.cancel();
  }

  /** Barcha kutayotgan/ishlayotgan prefetch'larni bekor qiladi. */
  public static void cancelAll() {
    markWanted(java.util.Collections.emptyList());
  }

  /**
   * [url] (HLS master yoki media playlist) uchun playlist(lar) + birinchi
   * [seconds] soniya segmentlarini fon'da kesh'ga yozadi. `seconds <= 0` —
   * faqat playlist'lar. Best-effort: xatolar yutiladi.
   */
  public static void prefetch(@NonNull Context context, @NonNull String url, int seconds) {
    prefetch(context, url, seconds, null);
  }

  /**
   * [onDone] — ish tugaganda (muvaffaqiyat, bekor yoki xato) main thread'da
   * bir marta chaqiriladi. Feed shu signalga qarab NEXT ExoPlayer instance'ini
   * ochadi — aks holda writer va player bir xil segmentni parallel tarmoqdan
   * tortadi (o'lchandi: init 1–4 s).
   */
  public static void prefetch(
      @NonNull Context context, @NonNull String url, int seconds, @Nullable Runnable onDone) {
    wanted.add(url);
    final Context app = context.getApplicationContext();
    prefetchExecutor.execute(
        () -> {
          try {
            run(app, url, seconds);
          } finally {
            if (onDone != null) MAIN.post(onDone);
          }
        });
  }

  private static final android.os.Handler MAIN =
      new android.os.Handler(android.os.Looper.getMainLooper());

  private static boolean stale(String url) {
    return !wanted.contains(url);
  }

  private static void run(Context app, String url, int seconds) {
    if (stale(url)) return;
    long t0 = System.currentTimeMillis();
    activeUrl = url;
    try {
      CacheDataSource ds = newCacheDataSource(app);
      Uri masterUri = Uri.parse(url);

      HlsPlaylist playlist = fetchAndParse(ds, masterUri, url);
      if (playlist == null) return;

      Uri mediaUri = masterUri;
      HlsMediaPlaylist media;
      if (playlist instanceof HlsMultivariantPlaylist) {
        Uri lowest = lowestVariant((HlsMultivariantPlaylist) playlist);
        if (lowest == null) return;
        mediaUri = lowest;
        HlsPlaylist mp = fetchAndParse(ds, mediaUri, url);
        if (!(mp instanceof HlsMediaPlaylist)) return;
        media = (HlsMediaPlaylist) mp;
      } else if (playlist instanceof HlsMediaPlaylist) {
        media = (HlsMediaPlaylist) playlist;
      } else {
        return;
      }

      long wantUs = seconds <= 0 ? 0 : (long) seconds * C.MICROS_PER_SECOND;
      long gotUs = 0;
      int n = 0;
      if (wantUs > 0) {
        String base = mediaUri.toString();
        for (HlsMediaPlaylist.Segment s : media.segments) {
          if (stale(url)) break;
          if (s.initializationSegment != null) {
            write(ds, segmentSpec(base, s.initializationSegment), url);
          }
          write(ds, segmentSpec(base, s), url);
          gotUs += s.durationUs;
          n++;
          if (gotUs >= wantUs) break;
        }
      }
      Log.d(
          TAG,
          "prefetch done segs="
              + n
              + " sec="
              + (gotUs / C.MICROS_PER_SECOND)
              + " ms="
              + (System.currentTimeMillis() - t0)
              + (stale(url) ? " (stale)" : "")
              + " "
              + tail(url));
    } catch (java.io.InterruptedIOException e) {
      // markWanted() — endi kerak emas; kutilgan holat.
      Log.d(TAG, "prefetch cancelled " + tail(url));
    } catch (Exception e) {
      Log.d(TAG, "prefetch failed " + tail(url) + ": " + e);
    } finally {
      activeUrl = null;
    }
  }

  private static CacheDataSource newCacheDataSource(Context app) {
    DefaultHttpDataSource.Factory http =
        new DefaultHttpDataSource.Factory()
            .setUserAgent("ExoPlayer")
            .setAllowCrossProtocolRedirects(true);
    return new CacheDataSource.Factory()
        .setCache(get(app))
        .setUpstreamDataSourceFactory(http)
        .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
        .createDataSource();
  }

  /** Playlist'ni kesh orqali o'qiydi (kesh'da bo'lsa tarmoqsiz) va parse qiladi. */
  @Nullable
  private static HlsPlaylist fetchAndParse(CacheDataSource ds, Uri uri, String jobUrl)
      throws IOException {
    if (stale(jobUrl)) return null;
    DataSpec spec = new DataSpec(uri);
    write(ds, spec, jobUrl);
    if (stale(jobUrl)) return null;
    try (InputStream in = new DataSourceInputStream(ds, spec)) {
      return new HlsPlaylistParser().parse(uri, in);
    }
  }

  private static void write(CacheDataSource ds, DataSpec spec, String jobUrl)
      throws IOException {
    if (stale(jobUrl)) return;
    CacheWriter w = new CacheWriter(ds, spec, new byte[BUFFER], null);
    activeWriter = w;
    try {
      w.cache();
    } finally {
      if (activeWriter == w) activeWriter = null;
    }
  }

  @Nullable
  private static Uri lowestVariant(HlsMultivariantPlaylist master) {
    List<HlsMultivariantPlaylist.Variant> variants = master.variants;
    HlsMultivariantPlaylist.Variant best = null;
    for (HlsMultivariantPlaylist.Variant v : variants) {
      if (best == null || v.format.bitrate < best.format.bitrate) best = v;
    }
    return best == null ? null : best.url;
  }

  private static DataSpec segmentSpec(String baseUrl, HlsMediaPlaylist.SegmentBase s) {
    Uri uri = Uri.parse(UriUtil.resolve(baseUrl, s.url));
    DataSpec.Builder b = new DataSpec.Builder().setUri(uri);
    if (s.byteRangeLength != C.LENGTH_UNSET) {
      b.setPosition(s.byteRangeOffset).setLength(s.byteRangeLength);
    }
    return b.build();
  }

  /** Log uchun: query'siz (token'siz) yo'lning oxirgi 48 belgisi — variant/segment ko'rinsin. */
  private static String tail(String u) {
    int q = u.indexOf('?');
    String p = q > 0 ? u.substring(0, q) : u;
    p = Uri.decode(p);
    return p.length() > 48 ? "…" + p.substring(p.length() - 48) : p;
  }
}
