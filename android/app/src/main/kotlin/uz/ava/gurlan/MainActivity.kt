package uz.ava.gurlan

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.videoplayer.AvaMediaCache

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "openApp") {
                    val pkg = call.argument<String>("package")
                    result.success(pkg != null && launchPackage(pkg))
                } else {
                    result.notImplemented()
                }
            }

        // AVAGram HLS segment prefetch — vendored video_player_android'dagi
        // AvaMediaCache (Media3 SimpleCache) bilan bir xil kesh.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CACHE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prefetch" -> {
                        val url = call.argument<String>("url")
                        val seconds = call.argument<Int>("seconds") ?: 0
                        if (url.isNullOrEmpty()) {
                            result.success(false)
                        } else {
                            // Javob — prefetch tugaganda (Dart `await` NEXT
                            // instance'ni shundan keyin ochadi).
                            AvaMediaCache.prefetch(applicationContext, url, seconds) {
                                result.success(true)
                            }
                        }
                    }
                    "markWanted" -> {
                        val urls = call.argument<List<String>>("urls") ?: emptyList()
                        AvaMediaCache.markWanted(urls)
                        result.success(true)
                    }
                    "cancelAll" -> {
                        AvaMediaCache.cancelAll()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Paketning launcher activity'si. `null` — ilova o'rnatilmagan
    /// (yoki manifest `<queries>` da ko'rsatilmagan).
    private fun launchPackage(pkg: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private companion object {
        const val CHANNEL = "uz.ava.gurlan/external_app"
        const val MEDIA_CACHE_CHANNEL = "uz.ava.gurlan/tv_media_cache"
    }
}
