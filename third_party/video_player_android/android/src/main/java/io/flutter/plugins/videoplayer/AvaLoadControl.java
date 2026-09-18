// AVA patch (vendored video_player_android 2.9.5).
//
// ExoPlayer'ning standart DefaultLoadControl'i har bir player uchun 50 soniya
// oldinga buferlaydi. Qisqa-format lentada (o'rtacha ko'rish 8s, 50% skip)
// bu har svaypda 50s × bitrate yuklash degani — TECNO LH7n / Beeline LTE'da
// 11 ta klip × 8s ko'rish = 111 MB (o'lchandi). Zaif 4G'da joriy klip shu
// fon yuklash bilan tarmoqni bo'lib olib qotib qoladi (production
// playbackStats: o'rtacha 6.4% rebuffer, ba'zi kliplarda 60–100%).
//
// Bu yerda buferni ~4s HLS segmentlariga mos qilib chegaralaymiz:
// boshlash uchun 1.5s, rebuffer'dan keyin 3s, oldinga eng ko'pi 20s.
package io.flutter.plugins.videoplayer;

import androidx.annotation.NonNull;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.LoadControl;

@UnstableApi
public final class AvaLoadControl {
  private AvaLoadControl() {}

  public static final int MIN_BUFFER_MS = 10_000;
  public static final int MAX_BUFFER_MS = 20_000;
  public static final int BUFFER_FOR_PLAYBACK_MS = 1_500;
  public static final int BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS = 3_000;

  @NonNull
  public static LoadControl create() {
    return new DefaultLoadControl.Builder()
        .setBufferDurationsMs(
            MIN_BUFFER_MS,
            MAX_BUFFER_MS,
            BUFFER_FOR_PLAYBACK_MS,
            BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS)
        .setPrioritizeTimeOverSizeThresholds(true)
        .build();
  }
}
