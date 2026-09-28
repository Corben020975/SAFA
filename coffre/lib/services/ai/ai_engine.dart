/// Moteur de génération : Claude (en ligne) ou Gemini Nano (sur le téléphone).
abstract interface class AiEngine {
  Future<String> complete({
    required String system,
    required String prompt,
    String effort,
  });
}
