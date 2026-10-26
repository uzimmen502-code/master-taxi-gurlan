package uz.ava.gurlan

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.videoplayer.AvaMediaCache

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openApp" -> {
                        val pkg = call.argument<String>("package")
                        result.success(pkg != null && launchPackage(pkg))
                    }
                    // Ochmasdan faqat o'rnatilganini tekshirish (AVA yordamchisi:
                    // ChatGPT ilovasi bo'lsa — o'z obunasidan foydalanish taklifi).
                    "isAppInstalled" -> {
                        val pkg = call.argument<String>("package")
                        result.success(
                            pkg != null && packageManager.getLaunchIntentForPackage(pkg) != null
                        )
                    }
                    else -> result.notImplemented()
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

        // Deferred deep link (do'kon QR -> Play -> o'rnatish -> ilova o'sha do'konni ochadi):
        // Google Play Install Referrer. Dart tomoni (install_referrer_link.dart) faqat birinchi
        // ishga tushishda bir marta chaqiradi va o'z timeout'iga ega. Javob: referrer satri yoki null
        // (xizmat yo'q / xato — jim, logcat'da kod).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_REFERRER_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getInstallReferrer") {
                    readInstallReferrer(result)
                } else {
                    result.notImplemented()
                }
            }
    }

    /// Install Referrer'ni o'qiydi. Binder chaqiruvi (`installReferrer`) asosiy oqimda EMAS
    /// (Play sekin bo'lsa ANR bo'lmasin); javob bir marta va asosiy oqimda yuboriladi.
    private fun readInstallReferrer(result: MethodChannel.Result) {
        val main = Handler(Looper.getMainLooper())
        val done = java.util.concurrent.atomic.AtomicBoolean(false)
        val client = InstallReferrerClient.newBuilder(applicationContext).build()
        val finish: (String?) -> Unit = { value ->
            if (done.compareAndSet(false, true)) {
                try {
                    client.endConnection()
                } catch (e: Exception) {
                    Log.w(REFERRER_TAG, "endConnection: ${e.javaClass.simpleName}")
                }
                main.post { result.success(value) }
            }
        }
        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(responseCode: Int) {
                    if (responseCode != InstallReferrerClient.InstallReferrerResponse.OK) {
                        Log.w(REFERRER_TAG, "setup code=$responseCode")
                        finish(null)
                        return
                    }
                    Thread {
                        val referrer = try {
                            client.installReferrer.installReferrer
                        } catch (e: Exception) {
                            Log.w(REFERRER_TAG, "read: ${e.javaClass.simpleName}")
                            null
                        }
                        finish(referrer)
                    }.start()
                }

                override fun onInstallReferrerServiceDisconnected() {
                    Log.w(REFERRER_TAG, "service disconnected")
                    finish(null)
                }
            })
        } catch (e: Exception) {
            Log.w(REFERRER_TAG, "startConnection: ${e.javaClass.simpleName}")
            finish(null)
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
        const val INSTALL_REFERRER_CHANNEL = "uz.ava.gurlan/install_referrer"
        const val REFERRER_TAG = "AvaInstallReferrer"
    }
}
