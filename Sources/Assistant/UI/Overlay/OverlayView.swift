import SwiftUI

/// Содержимое overlay. Прозрачный фон, читаемый текст ответа.
struct OverlayView: View {
    @ObservedObject var model: OverlayViewModel

    // фокус полей: при получении фокуса активируем приложение,
    // иначе клавиатура не доходит до nonactivating-панели accessory-приложения
    @FocusState private var chatFocused: Bool
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow
            controlRow
            if model.showSettings {
                settingsPanel
            }
            Divider().opacity(0.3)
            answerArea
            Divider().opacity(0.3)
            chatInputRow
        }
        .padding(12)
        .frame(minWidth: 380, minHeight: 240)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: chatFocused) { _, focused in
            if focused { model.onRequestActivation?() }
        }
        .onChange(of: keyFocused) { _, focused in
            if focused { model.onRequestActivation?() }
        }
    }

    // MARK: - Верхняя часть

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Circle().fill(model.llmReady ? .green : .orange).frame(width: 7, height: 7)
            Text(model.llmStatusText).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var controlRow: some View {
        HStack(spacing: 8) {
            Button {
                model.onToggleListening?()
            } label: {
                Label(model.isListening ? "Стоп" : "Слушать",
                      systemImage: model.isListening ? "mic.slash" : "mic")
            }
            Button {
                model.onCaptureAndAsk?()
            } label: {
                Label("Экран", systemImage: "viewfinder")
            }
            Spacer()
            Button {
                model.onToggleSettings?()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Подключение LLM")
            Button {
                model.onHideOverlay?()
            } label: {
                Image(systemName: "xmark")
            }
            .help("Скрыть overlay")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Ответы LLM (основная область)

    private var answerArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(displayText)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("answerBottom")
            }
            .frame(maxHeight: .infinity)
            // при стриминге прокручиваем к свежему тексту
            .onChange(of: model.answer) { _, _ in
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo("answerBottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Ввод чата (снизу)

    private var chatInputRow: some View {
        HStack(spacing: 6) {
            TextField("спросить LLM…", text: $model.chatInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .focused($chatFocused)
                .onSubmit(send)

            if model.isGenerating {
                // во время генерации кнопка прерывает ответ
                Button {
                    model.onStopGeneration?()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
                .help("Прервать генерацию")
            } else {
                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func send() {
        let text = model.chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.onSendMessage?(text)
        model.chatInput = ""
    }

    // MARK: - Панель провайдера

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Провайдер: \(model.providerTitle)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Text("Порт llama").font(.system(size: 11))
                TextField("11434", text: $model.portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Button("Подключить") {
                    model.onUseLocalLlama?(Int(model.portText) ?? 11434)
                }
            }

            Divider().opacity(0.3)

            Text("ChatGPT (OpenAI API)").font(.system(size: 11, weight: .semibold))
            Button {
                model.onOpenOpenAIKeysPage?()
            } label: {
                Label("Открыть страницу ключей OpenAI", systemImage: "safari")
            }
            HStack(spacing: 6) {
                SecureField("вставьте API-ключ", text: $model.apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .focused($keyFocused)
                Button("Сохранить") {
                    model.onConnectOpenAI?(model.apiKeyInput)
                    model.apiKeyInput = ""
                }
                .disabled(model.apiKeyInput.isEmpty)
            }
            Text("Нужен API-ключ платформы OpenAI, не вход в подписку ChatGPT.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Вспомогательное

    private var displayText: String {
        switch model.status {
        case .error(let msg): return msg
        case .idle where model.answer.isEmpty: return model.lastTranscript
        default: return model.answer.isEmpty ? model.lastTranscript : model.answer
        }
    }

    private var statusText: String {
        switch model.status {
        case .idle: return "готов"
        case .listening: return "слушаю"
        case .thinking: return "думаю"
        case .answering: return "отвечаю"
        case .error: return "ошибка"
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .idle: return .green
        case .listening: return .blue
        case .thinking, .answering: return .orange
        case .error: return .red
        }
    }
}
