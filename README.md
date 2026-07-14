# Assistant

Локальный ассистент для macOS (Apple Silicon). Menu bar + прозрачный overlay,
захват микрофона, локальный ASR (за протоколом), OCR по хоткею, стриминг ответа LLM.

## Требования

- macOS 14.2+ (Apple Silicon)
- Swift 6.x / Xcode 26
- Для локального LLM: запущенный Ollama или llama.cpp server на `http://127.0.0.1:11434/v1`

## Сборка и запуск

```sh
swift build
swift test
swift run Assistant
```

## MVP-проверка

1. Поднимите OpenAI-совместимый LLM endpoint. По умолчанию приложение ждёт Ollama
   на `http://127.0.0.1:11434/v1` и модель `llama3.1`.
2. Запустите приложение:

   ```sh
   swift run Assistant
   ```

3. В появившемся overlay используйте кнопки:
   - `Слушать` / `Стоп` — включить или выключить микрофон
   - `Экран` — снять область вокруг курсора, распознать текст и спросить LLM
   - `x` — скрыть overlay

4. Дайте системные разрешения:
   - Microphone — для кнопки `Слушать`
   - Screen Recording — для кнопки `Экран`
   - Accessibility — для глобальных hotkeys

После `swift run Assistant` приложение живёт в menu bar как значок `AI`, без Dock-иконки.
Закрыть его можно через `AI` -> `Выход`. Если запускали из терминала и menu bar
недоступен, остановите процесс через `Ctrl+C`.

При запуске из чистого бинаря macOS будет спрашивать разрешения по мере обращения
к устройствам. Для полноценной работы (стабильные TCC-разрешения, скрытие из Dock,
подпись) приложение нужно упаковать в `.app` бандл с `Info.plist` и entitlements:

- `NSMicrophoneUsageDescription` — доступ к микрофону
- Screen Recording — включается системой при первом захвате экрана (OCR)
- Accessibility — нужно для глобальных горячих клавиш через `CGEventTap`

Горячие клавиши: `⇧⌘A` — снять область и спросить LLM, `⇧⌘O` — показать/скрыть overlay.
Если они не срабатывают, проверьте `System Settings` -> `Privacy & Security` ->
`Accessibility` и разрешите процессу, из которого запущено приложение (`Terminal`,
Xcode или собранный `.app`).

## Что работает сейчас

- Menu bar приложение (accessory, без Dock), прозрачный overlay-`NSPanel`
- Микрофон → ресемпл 16 kHz mono → VAD → сегменты речи (тишина в ASR не идёт)
- OCR области экрана через Vision по хоткею, с debounce и кэшем по хешу кадра
- ContextManager (actor) с дедупликацией хвостов и обрезкой окна
- PromptBuilder: компактный промпт, схлопывание реплик, бюджет по длине
- LLM стриминг по SSE (OpenAI-совместимый), батчинг обновлений UI
- Keychain для ключа, логи без секретов

## Осознанные заглушки / TODO

- **ASR**: `ASREngineFactory` пока отдаёт `StubASREngine` (маркер вместо текста).
  Точка интеграции whisper.cpp описана в `WhisperASREngine.swift`. Это отдельная
  задача — C++-мост + модели в Application Support + выбор Core ML/CPU backend.
- **System audio**: сейчас только микрофон. Второй источник (ScreenCaptureKit или
  Core Audio process tap) добавляется за протоколом `AudioSource` в v2.
- **Захват экрана**: `CGWindowListCreateImage` (deprecated в 14.0). Работает, но
  переезд на ScreenCaptureKit — в v2.
- **Настройки/онбординг разрешений**: UI ещё не сделан, значения берутся из дефолтов.

## Про скрытие overlay от записи экрана

`OverlayWindow.setHiddenFromCapture` ставит `sharingType = .none`. Это убирает окно
из большинства ШТАТНЫХ путей захвата, но не гарантирует невидимость: поведение
менялось между версиями macOS, аппаратный захват (грабер/камера) окно видит всегда.
Флаг выключен по умолчанию и должен подаваться как экспериментальный.

## Структура

```
Sources/Assistant/
  App/       — main, AppDelegate, AppCoordinator, DIContainer
  UI/        — Overlay (NSPanel + SwiftUI), MenuBar
  Audio/     — источники, ресемпл, VAD, пайплайн
  ASR/       — протокол, стаб, seam под whisper
  Vision/    — захват области, OCR, пайплайн
  LLM/       — протокол, OpenAI-совместимый клиент, SSE-парсер
  Context/   — окно контекста, менеджер (actor), сборка промпта
  Core/      — логи, Keychain, настройки, хоткеи
Tests/       — ContextWindow, PromptBuilder, SSEParser
```
