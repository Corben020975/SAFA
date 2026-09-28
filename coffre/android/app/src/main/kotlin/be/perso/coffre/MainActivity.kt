package be.perso.coffre

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

/**
 * Pont natif « coffre/system » : réglages batterie/notifications Samsung,
 * sélecteur de fichiers système (export/import) et actions du widget.
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

    /** Action du widget reçue au démarrage, lue une fois par Flutter. */
    private var pendingLaunchUri: String? = null

    /** Résultat en attente du sélecteur de fichiers. */
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Pas de relecture de l'action si l'activité est recréée ou relancée
        // depuis les apps récentes (sinon l'écran Capture se rouvrirait).
        if (savedInstanceState == null) pendingLaunchUri = extractLaunchUri(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractLaunchUri(intent)?.let { channel?.invokeMethod("onLaunchAction", it) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(::onMethodCall)
        }
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takeLaunchAction" -> {
                result.success(pendingLaunchUri)
                pendingLaunchUri = null
            }
            "isIgnoringBatteryOptimizations" -> {
                val power = getSystemService(POWER_SERVICE) as PowerManager
                result.success(power.isIgnoringBatteryOptimizations(packageName))
            }
            "requestIgnoreBatteryOptimizations" -> {
                // Boîte de dialogue directe ; sinon la liste système complète.
                val shown = startSafely(
                    Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:$packageName"),
                    ),
                ) || startSafely(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                result.success(shown)
            }
            "openAppSettings" -> result.success(
                startSafely(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", packageName, null),
                    ),
                ),
            )
            "openNotificationSettings" -> result.success(
                startSafely(
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                ),
            )
            "openExactAlarmSettings" -> result.success(
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && startSafely(
                    Intent(
                        Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                        Uri.parse("package:$packageName"),
                    ),
                ),
            )
            "appVersion" -> result.success(appVersion())
            "saveDocument" -> saveDocument(call, result)
            "openDocument" -> openDocument(call, result)
            else -> result.notImplemented()
        }
    }

    // --- Export / import via le sélecteur système (Storage Access Framework) ---
    // Aucune permission de stockage nécessaire : l'utilisateur choisit le fichier.

    private fun saveDocument(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null) {
            result.error("args", "Contenu manquant", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = call.argument<String>("mimeType") ?: "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "coffre-export")
        }
        launchPicker(intent, REQUEST_CREATE, result, bytes)
    }

    private fun openDocument(call: MethodCall, result: MethodChannel.Result) {
        val types = call.argument<List<String>>("mimeTypes") ?: listOf("*/*")
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
        }
        launchPicker(intent, REQUEST_OPEN, result, null)
    }

    private fun launchPicker(
        intent: Intent,
        requestCode: Int,
        result: MethodChannel.Result,
        bytes: ByteArray?,
    ) {
        if (pendingResult != null) {
            result.error("busy", "Un sélecteur de fichier est déjà ouvert", null)
            return
        }
        pendingResult = result
        pendingBytes = bytes
        try {
            startActivityForResult(intent, requestCode)
        } catch (e: ActivityNotFoundException) {
            pendingResult = null
            pendingBytes = null
            result.error("no_picker", "Aucun gestionnaire de fichiers disponible", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CREATE && requestCode != REQUEST_OPEN) return
        val result = pendingResult ?: return
        val bytes = pendingBytes
        pendingResult = null
        pendingBytes = null

        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            // Annulé par l'utilisateur.
            result.success(if (requestCode == REQUEST_CREATE) false else null)
            return
        }
        try {
            if (requestCode == REQUEST_CREATE) {
                val stream = contentResolver.openOutputStream(uri, "wt")
                    ?: throw IOException("Écriture impossible")
                stream.use { it.write(bytes ?: ByteArray(0)) }
                result.success(true)
            } else {
                val stream = contentResolver.openInputStream(uri)
                    ?: throw IOException("Lecture impossible")
                result.success(stream.use { it.readBytes() })
            }
        } catch (e: Exception) {
            result.error("io", e.message, null)
        }
    }

    // --- Utilitaires ---

    private fun startSafely(intent: Intent): Boolean = try {
        startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: SecurityException) {
        false
    }

    private fun extractLaunchUri(intent: Intent?): String? {
        val data = intent?.data ?: return null
        if (data.scheme != "coffre") return null
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return null
        return data.toString()
    }

    @Suppress("DEPRECATION")
    private fun appVersion(): String {
        val info = packageManager.getPackageInfo(packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            info.versionCode.toLong()
        }
        return "${info.versionName} ($code)"
    }

    companion object {
        private const val CHANNEL = "coffre/system"
        private const val REQUEST_CREATE = 4201
        private const val REQUEST_OPEN = 4202
    }
}
