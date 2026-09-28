/// Moteur de génération en ligne : Gemini (Google) ou Claude (Anthropic).
abstract interface class AiEngine {
  Future<String> complete({
    required String system,
    required String prompt,
    String effort,
  });
}
