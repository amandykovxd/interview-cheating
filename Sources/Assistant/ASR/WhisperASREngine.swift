import Foundation

/// Точка интеграции whisper.cpp. Пока не подключён — держим за тем же протоколом,
/// чтобы координатор не зависел от реализации.
///
/// План подключения (отдельная задача, тянет C++-мост):
///   1. Добавить whisper.cpp как SPM-зависимость или вендорнуть исходники
///      отдельным C-таргетом с module map.
///   2. Модели (ggml + опционально Core ML энкодер) тянуть при первом запуске
///      в Application Support, не класть в бандл.
///   3. Backend выбирать по устройству: Core ML энкодер на Apple Silicon,
///      CPU/Accelerate как fallback. Прогрев модели один раз при старте.
///   4. Потоковый режим окнами (~5с с перекрытием ~1с): partial сразу в UI,
///      final по закрытию сегмента из VAD.
///
/// До подключения фабрика отдаёт StubASREngine.
enum ASREngineFactory {
    static func make(modelName: String) -> ASREngine {
        // TODO: вернуть WhisperASREngine, когда мост будет готов и модель на месте.
        Log.asr.warning("whisper недоступен, работаем на заглушке (model=\(modelName))")
        return StubASREngine()
    }
}
