// AVA patch #3 (vendored video_player_android 2.9.5).
//
// ExoPlayer birinchi HLS variant'ni `DefaultBandwidthMeter`ning boshlang'ich
// (mamlakat/tarmoq turi bo'yicha jadval) baholashiga qarab tanlaydi — Wi-Fi'da
// 480p/720p. `AvaMediaCache.prefetch()` esa eng past (360p) variant'ni
// yozadi — o'lchov (TECNO LH7n): player prefetch'ni chetlab, o'z variant'ini
// tarmoqdan tortdi (init 1.5–2.5 s kesh bo'lsa ham).
//
// Boshlang'ich baho pastroq → birinchi segment doim eng past variant (kesh
// hit, tez birinchi frame), keyin real o'lchovga qarab yuqoriga o'tadi
// (qisqa-format lentalarning "start low, ramp up" andozasi).
package io.flutter.plugins.videoplayer;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.upstream.BandwidthMeter;
import androidx.media3.exoplayer.upstream.DefaultBandwidthMeter;

@UnstableApi
public final class AvaBandwidthMeter {
  private AvaBandwidthMeter() {}

  /// Ataylab har qanday variant'dan past: AdaptiveTrackSelection "hech biri
  /// sig'masa — eng past bitrate" qoidasi bilan birinchi tanlov DOIM master'dagi
  /// eng past variant (prefetcher ham `lowestVariant` bilan aynan shuni yozadi).
  /// Birinchi segmentdan keyin real o'lchov bilan yuqoriga o'tadi.
  public static final long INITIAL_BITRATE_ESTIMATE = 100_000L;

  @NonNull
  public static BandwidthMeter create(@NonNull Context context) {
    return new DefaultBandwidthMeter.Builder(context)
        .setInitialBitrateEstimate(INITIAL_BITRATE_ESTIMATE)
        .build();
  }
}
