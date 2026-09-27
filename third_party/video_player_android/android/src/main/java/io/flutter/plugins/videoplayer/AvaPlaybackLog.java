// AVA patch #5 (vendored video_player_android 2.9.5).
//
// ABR диагностикаси. `dumpsys media.metrics` фақат ДЕКОДЕР нимани
// очганини кўрсатади — плеер НЕГА ўша поғонани танлаганини эмас. Бу
// listener иккита ҳал қилувчи сигнални logcat'га чиқаради:
//
//   • `onBandwidthSample` — метр ҲАҚИҚАТДА қанча тармоқ кўрганини ва
//     жорий баҳосини. Агар бу ўсмаса, ABR ҳеч қачон кўтарилмайди
//     (айнан шу ҳолат 2026-09-26 да топилди: кеш туфайли плеер тармоққа
//     деярли чиқмайди, шунинг учун метр ҳеч нарса ўрганмайди).
//   • `onVideoInputFormatChanged` — танланган вариантнинг ЎЛЧАМИ ва
//     bitrate'и, ҳар алмашувда.
//
// Logcat: `adb logcat -s AvaPlayback`.
package io.flutter.plugins.videoplayer;

import android.util.Log;
import androidx.annotation.NonNull;
import androidx.media3.common.Format;
import androidx.annotation.Nullable;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.DecoderReuseEvaluation;
import androidx.media3.exoplayer.analytics.AnalyticsListener;

@UnstableApi
public final class AvaPlaybackLog implements AnalyticsListener {
  private static final String TAG = "AvaPlayback";

  /// `onBandwidthSample` жуда тез-тез келади — логни босмаслик учун.
  private static final long SAMPLE_LOG_INTERVAL_MS = 2_000;

  private long lastSampleLogAt;

  @Override
  public void onBandwidthEstimate(
      @NonNull EventTime eventTime, int elapsedMs, long bytes, long bitrateEstimate) {
    long now = System.currentTimeMillis();
    if (now - lastSampleLogAt < SAMPLE_LOG_INTERVAL_MS) return;
    lastSampleLogAt = now;
    Log.d(
        TAG,
        "bw sample elapsed=" + elapsedMs + "ms bytes=" + bytes
            + " estimate=" + (bitrateEstimate / 1000) + "kbps");
  }

  @Override
  public void onVideoInputFormatChanged(
      @NonNull EventTime eventTime,
      @NonNull Format format,
      @Nullable DecoderReuseEvaluation decoderReuseEvaluation) {
    Log.d(
        TAG,
        "video format " + format.width + "x" + format.height
            + " bitrate=" + (format.bitrate == Format.NO_VALUE
                ? "?" : (format.bitrate / 1000) + "kbps")
            + " id=" + format.id);
  }
}
