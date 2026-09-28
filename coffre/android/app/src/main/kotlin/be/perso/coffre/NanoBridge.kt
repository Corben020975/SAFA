package be.perso.coffre

import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Candidate
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.SystemInstruction
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.prompt.generationConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Pont « coffre/nano » : Gemini Nano via ML Kit GenAI (service système AICore).
 * Le modèle tourne sur le téléphone : aucun texte ne quitte l'appareil.
 */
class NanoBridge(messenger: BinaryMessenger) {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var model: GenerativeModel? = null
    private var download: Job? = null

    init {
        channel.setMethodCallHandler(::onMethodCall)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        scope.cancel()
        model?.close()
        model = null
    }

    private fun client(): GenerativeModel =
        model ?: Generation.getClient(generationConfig {}).also { model = it }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> scope.launch { result.success(status()) }
            "download" -> startDownload(result)
            "generate" -> scope.launch {
                try {
                    result.success(
                        generate(
                            call.argument<String>("system") ?: "",
                            call.argument<String>("prompt") ?: "",
                            call.argument<Int>("maxTokens") ?: DEFAULT_TOKENS,
                        ),
                    )
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    result.error("generate", e.message ?: e.toString(), null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private suspend fun status(): Map<String, Any?> = try {
        val code = when (client().checkStatus()) {
            FeatureStatus.AVAILABLE -> "available"
            FeatureStatus.DOWNLOADABLE -> "downloadable"
            FeatureStatus.DOWNLOADING -> "downloading"
            else -> "unavailable"
        }
        mapOf("status" to code)
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        // AICore absent, trop ancien ou appareil non pris en charge.
        mapOf("status" to "unavailable", "error" to (e.message ?: e.toString()))
    }

    /** Téléchargement unique du modèle ; progression envoyée à Flutter. */
    private fun startDownload(result: MethodChannel.Result) {
        if (download?.isActive == true) {
            result.error("busy", "Téléchargement déjà en cours.", null)
            return
        }
        download = scope.launch {
            var total = 0L
            try {
                client().download().collect { s ->
                    when (s) {
                        is DownloadStatus.DownloadStarted -> {
                            total = s.bytesToDownload
                            progress(0L, total)
                        }
                        is DownloadStatus.DownloadProgress -> progress(s.totalBytesDownloaded, total)
                        is DownloadStatus.DownloadFailed -> throw s.e
                        else -> Unit
                    }
                }
                result.success(true)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                result.error("download", e.message ?: e.toString(), null)
            }
        }
    }

    private fun progress(done: Long, total: Long) {
        channel.invokeMethod("progress", mapOf("done" to done, "total" to total))
    }

    private suspend fun generate(system: String, prompt: String, maxTokens: Int): String {
        val first = runCatching { ask(system, prompt, maxTokens) }
        // Selon la version du modèle, la longueur de réponse peut être plafonnée :
        // second essai avec la valeur par défaut documentée.
        if (first.isSuccess || maxTokens <= DEFAULT_TOKENS) return first.getOrThrow()
        return ask(system, prompt, DEFAULT_TOKENS)
    }

    private suspend fun ask(system: String, prompt: String, maxTokens: Int): String {
        val response = client().generateContent(
            generateContentRequest(SystemInstruction(system), TextPart(prompt)) {
                temperature = 0.3f
                topK = 16
                candidateCount = 1
                maxOutputTokens = maxTokens
            },
        )
        val candidate = response.candidates.firstOrNull()
            ?: throw IllegalStateException("Réponse vide.")
        val text = candidate.text.trim()
        return if (candidate.finishReason == Candidate.FinishReason.MAX_TOKENS) "$text…" else text
    }

    private companion object {
        const val CHANNEL = "coffre/nano"
        const val DEFAULT_TOKENS = 256
    }
}
