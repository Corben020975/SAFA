package be.perso.coffre

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * « Ajouter à Coffre » (sélection de texte) et « Partager › Coffre » :
 * panneau transparent posé sur l'app d'origine, qui se referme après
 * l'enregistrement pour rester dans le mail.
 */
class QuickCaptureActivity : FlutterActivity() {

    override fun getDartEntrypointFunctionName(): String = "quickCaptureMain"

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coffre/quick")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shared" -> result.success(mapOf("text" to sharedText(), "source" to sourceTag()))
                    "openFull" -> {
                        startActivity(
                            Intent(this, MainActivity::class.java)
                                .setAction(Intent.ACTION_VIEW)
                                .setData(Uri.parse(call.argument<String>("uri") ?: "coffre://capture"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(null)
                        finish()
                    }
                    "close" -> {
                        result.success(null)
                        finish()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun sharedText(): String {
        val parts = when (intent?.action) {
            Intent.ACTION_PROCESS_TEXT -> listOfNotNull(
                intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString(),
            )
            Intent.ACTION_SEND -> listOfNotNull(
                intent.getStringExtra(Intent.EXTRA_SUBJECT),
                intent.getStringExtra(Intent.EXTRA_TEXT),
            )
            else -> emptyList()
        }
        return parts.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
            .joinToString("\n").take(20000)
    }

    /** App d'origine → tag (#outlook, #whatsapp…), quand Android la donne. */
    private fun sourceTag(): String? {
        val pkg = callingPackage ?: referrer?.host ?: return null
        if (pkg == packageName) return null
        return KNOWN_SOURCES[pkg]
    }

    private companion object {
        val KNOWN_SOURCES = mapOf(
            "com.microsoft.office.outlook" to "outlook",
            "com.microsoft.teams" to "teams",
            "com.microsoft.office.word" to "word",
            "com.google.android.gm" to "gmail",
            "com.whatsapp" to "whatsapp",
            "org.thoughtcrime.securesms" to "signal",
            "com.google.android.apps.messaging" to "sms",
            "com.samsung.android.messaging" to "sms",
            "com.android.chrome" to "web",
            "com.sec.android.app.sbrowser" to "web",
            "com.samsung.android.app.notes" to "notes",
            "com.adobe.reader" to "pdf",
            "notion.id" to "notion",
        )
    }
}
