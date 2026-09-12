package uz.ava.gurlan

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

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
    }
}
