package be.perso.coffre

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.CalendarContract
import java.util.TimeZone
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

/**
 * Pont natif « coffre/system » : réglages batterie/notifications Samsung,
 * sélecteur de fichiers système (export/import) et actions du widget.
 */
// FragmentActivity : requis par local_auth (verrouillage par empreinte).
class MainActivity : FlutterFragmentActivity() {

    private var channel: MethodChannel? = null

    /** Action du widget reçue au démarrage, lue une fois par Flutter. */
    private var pendingLaunchUri: String? = null

    /** Résultat en attente du sélecteur de fichiers. */
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    /** Réponse en attente de la demande de permission Agenda. */
    private var pendingPermission: MethodChannel.Result? = null

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
            "openUrl" -> result.success(
                startSafely(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url") ?: ""))),
            )
            "calendarPermission" -> result.success(hasCalendarPermission())
            "requestCalendarPermission" -> requestCalendarPermission(result)
            "listCalendars" -> guardedCalendar(result) { listCalendars() }
            "calendarEvents" -> guardedCalendar(result) {
                calendarEvents(call.argument<Number>("begin")!!.toLong(), call.argument<Number>("end")!!.toLong())
            }
            "insertEvent" -> guardedCalendar(result) { insertEvent(call) }
            "openEvent" -> result.success(
                startSafely(
                    Intent(
                        Intent.ACTION_VIEW,
                        ContentUris.withAppendedId(
                            CalendarContract.Events.CONTENT_URI,
                            call.argument<Number>("id")!!.toLong(),
                        ),
                    ),
                ),
            )
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

    // --- Agenda du téléphone (Google Agenda synchronisé par le compte Google) ---
    // Lecture/écriture locales : aucune connexion Google dans l'app.

    private fun hasCalendarPermission(): Boolean =
        checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED

    private fun requestCalendarPermission(result: MethodChannel.Result) {
        if (hasCalendarPermission()) {
            result.success(true)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        requestPermissions(
            arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
            REQUEST_CALENDAR,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CALENDAR) {
            pendingPermission?.success(hasCalendarPermission())
            pendingPermission = null
        }
    }

    private fun guardedCalendar(result: MethodChannel.Result, block: () -> Any?) {
        if (!hasCalendarPermission()) {
            result.error("no_permission", "Accès à l'agenda refusé", null)
            return
        }
        try {
            result.success(block())
        } catch (e: Exception) {
            result.error("calendar", e.message, null)
        }
    }

    private fun listCalendars(): List<Map<String, Any?>> {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.ACCOUNT_TYPE,
            CalendarContract.Calendars.CALENDAR_COLOR,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
            CalendarContract.Calendars.IS_PRIMARY,
        )
        val list = mutableListOf<Map<String, Any?>>()
        contentResolver.query(CalendarContract.Calendars.CONTENT_URI, projection, null, null, null)?.use { c ->
            while (c.moveToNext()) {
                list += mapOf(
                    "id" to c.getLong(0),
                    "name" to c.getString(1),
                    "account" to c.getString(2),
                    "accountType" to c.getString(3),
                    "color" to c.getInt(4),
                    "writable" to (c.getInt(5) >= CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR),
                    "primary" to (c.getInt(6) == 1),
                )
            }
        }
        return list
    }

    /** Occurrences (y compris récurrentes) entre deux instants, en millisecondes. */
    private fun calendarEvents(begin: Long, end: Long): List<Map<String, Any?>> {
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, begin)
            ContentUris.appendId(it, end)
        }.build()
        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.DISPLAY_COLOR,
        )
        val list = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            uri,
            projection,
            "${CalendarContract.Instances.VISIBLE} = 1",
            null,
            "${CalendarContract.Instances.BEGIN} ASC",
        )?.use { c ->
            while (c.moveToNext() && list.size < 60) {
                list += mapOf(
                    "id" to c.getLong(0),
                    "title" to (c.getString(1) ?: ""),
                    "begin" to c.getLong(2),
                    "end" to c.getLong(3),
                    "allDay" to (c.getInt(4) == 1),
                    "location" to c.getString(5),
                    "color" to c.getInt(6),
                )
            }
        }
        return list
    }

    private fun insertEvent(call: MethodCall): Long {
        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, call.argument<Number>("calendarId")!!.toLong())
            put(CalendarContract.Events.TITLE, call.argument<String>("title"))
            put(CalendarContract.Events.DESCRIPTION, call.argument<String>("description"))
            put(CalendarContract.Events.DTSTART, call.argument<Number>("begin")!!.toLong())
            put(CalendarContract.Events.DTEND, call.argument<Number>("end")!!.toLong())
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
        }
        val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            ?: throw IllegalStateException("Création refusée par l'agenda")
        return ContentUris.parseId(uri)
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
        if (intent == null) return null
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return null
        // Texte partagé depuis une autre app → écran Capture prérempli.
        if (intent.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            val text = listOfNotNull(
                intent.getStringExtra(Intent.EXTRA_SUBJECT),
                intent.getStringExtra(Intent.EXTRA_TEXT),
            ).map { it.trim() }.filter { it.isNotEmpty() }.distinct().joinToString("\n")
            if (text.isEmpty()) return null
            return Uri.Builder().scheme("coffre").authority("capture")
                .appendQueryParameter("text", text.take(20000)).build().toString()
        }
        val data = intent.data ?: return null
        if (data.scheme != "coffre") return null
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
        private const val REQUEST_CALENDAR = 4301
    }
}
