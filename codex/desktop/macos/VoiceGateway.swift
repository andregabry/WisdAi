import AVFoundation
import Foundation
import Security
import Speech

// MARK: - Multilingual & Regional Variant Definitions (Section 9)

public enum VoiceLanguageVariant: String, CaseIterable, Identifiable, Codable, Sendable {
    case portugueseBR = "pt-BR"
    case portuguesePT = "pt-PT"
    case englishUS = "en-US"
    case spanishES = "es-ES"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .portugueseBR: return "Português (Brasil)"
        case .portuguesePT: return "Português (Portugal)"
        case .englishUS: return "English (US)"
        case .spanishES: return "Español"
        }
    }

    public var shortCode: String {
        switch self {
        case .portugueseBR: return "PT-BR"
        case .portuguesePT: return "PT-PT"
        case .englishUS: return "EN"
        case .spanishES: return "ES"
        }
    }

    public var appleLocaleIdentifier: String { rawValue }

    public var bcp47LanguagePrefix: String {
        switch self {
        case .portugueseBR, .portuguesePT: return "pt"
        case .englishUS: return "en"
        case .spanishES: return "es"
        }
    }
}

// MARK: - Voice External Provider Keys (macOS Keychain Only)

public enum VoiceExternalService: String, CaseIterable, Identifiable, Codable, Sendable {
    case deepgram
    case elevenLabs

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .deepgram: return "Deepgram (Nova-3 / Flux STT)"
        case .elevenLabs: return "ElevenLabs (Flash v2.5 TTS)"
        }
    }
}

public enum VoiceKeychainStore {
    private static let service = "local.wisdai.voice-api-keys"

    public static func saveKey(_ key: String, for serviceKind: VoiceExternalService) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteKey(for: serviceKind)
            return
        }
        let account = "voice-key-\(serviceKind.rawValue)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(trimmed.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Erro ao salvar chave de voz no Chaves do macOS (OSStatus \(status))."
            ])
        }
    }

    public static func readKey(for serviceKind: VoiceExternalService) -> String? {
        let account = "voice-key-\(serviceKind.rawValue)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    public static func deleteKey(for serviceKind: VoiceExternalService) throws {
        let account = "voice-key-\(serviceKind.rawValue)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

// MARK: - Privacy, Consent & Paid-API Authorization Policies (Sections 12 & 18)

public struct VoicePolicyPreferences: Equatable, Codable, Sendable {
    public var allowPaidVoiceAPIs: Bool
    public var externalAudioConsentGranted: Bool
    public var preferOnDeviceSpeechOnly: Bool
    public var allowPersistentVoiceMemory: Bool
    public var storeRawAudioRecordings: Bool // Must stay false by default

    public static let strictDefault = VoicePolicyPreferences(
        allowPaidVoiceAPIs: false,
        externalAudioConsentGranted: false,
        preferOnDeviceSpeechOnly: true,
        allowPersistentVoiceMemory: false,
        storeRawAudioRecordings: false
    )

    private static let defaultsPrefix = "wisdai.voice.policy."

    public static func load(from defaults: UserDefaults = .standard) -> VoicePolicyPreferences {
        let paid = defaults.object(forKey: defaultsPrefix + "allowPaidVoiceAPIs") as? Bool ?? false
        let external = defaults.object(forKey: defaultsPrefix + "externalAudioConsentGranted") as? Bool ?? false
        let onDevice = defaults.object(forKey: defaultsPrefix + "preferOnDeviceSpeechOnly") as? Bool ?? true
        let persistMem = defaults.object(forKey: defaultsPrefix + "allowPersistentVoiceMemory") as? Bool ?? false
        // Raw audio recording persistence defaults strictly to false.
        let rawAudio = false
        return VoicePolicyPreferences(
            allowPaidVoiceAPIs: paid,
            externalAudioConsentGranted: external,
            preferOnDeviceSpeechOnly: onDevice,
            allowPersistentVoiceMemory: persistMem,
            storeRawAudioRecordings: rawAudio
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(allowPaidVoiceAPIs, forKey: Self.defaultsPrefix + "allowPaidVoiceAPIs")
        defaults.set(externalAudioConsentGranted, forKey: Self.defaultsPrefix + "externalAudioConsentGranted")
        defaults.set(preferOnDeviceSpeechOnly, forKey: Self.defaultsPrefix + "preferOnDeviceSpeechOnly")
        defaults.set(allowPersistentVoiceMemory, forKey: Self.defaultsPrefix + "allowPersistentVoiceMemory")
        defaults.set(false, forKey: Self.defaultsPrefix + "storeRawAudioRecordings")
    }
}

public enum VoiceGatewayProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case autoBestCompliant = "auto"
    case appleLocalHybrid = "apple_local_hybrid"
    case codexAppServerRealtime = "codex_app_server_realtime"
    case openAIRealtimeAPI = "openai_realtime_api"
    case geminiLiveAPI = "gemini_live_api"
    case hybridDeepgramElevenLabs = "hybrid_deepgram_elevenlabs"
    case hybridOpenAITTS = "hybrid_openai_tts"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .autoBestCompliant: return "Motor Autônomo WisdAI (Local-First · Recomendado)"
        case .appleLocalHybrid: return "Local / On-Device WisdAI ($0 · Sem API Externa)"
        case .codexAppServerRealtime: return "Codex App-Server Realtime (IPC Opcional)"
        case .openAIRealtimeAPI: return "OpenAI Realtime API (Chave Própria)"
        case .geminiLiveAPI: return "Google Gemini Live API (Chave Própria)"
        case .hybridDeepgramElevenLabs: return "Híbrido Premium (Deepgram + ElevenLabs)"
        case .hybridOpenAITTS: return "Híbrido Neural (Agente Ativo + OpenAI TTS)"
        }
    }

    public var isSpeechToSpeech: Bool {
        switch self {
        case .codexAppServerRealtime, .openAIRealtimeAPI, .geminiLiveAPI: return true
        default: return false
        }
    }

    public var requiresPaidAPIOptIn: Bool {
        switch self {
        case .openAIRealtimeAPI, .geminiLiveAPI, .hybridDeepgramElevenLabs, .hybridOpenAITTS:
            return true
        case .autoBestCompliant, .appleLocalHybrid, .codexAppServerRealtime:
            return false
        }
    }

    public var transmitsAudioExternally: Bool {
        switch self {
        case .autoBestCompliant, .appleLocalHybrid:
            return false // Local-first: Apple SpeechAnalyzer + FoundationModels ANE + Voz WisdAI local
        default:
            return true
        }
    }

    public var pricingSummary: String {
        switch self {
        case .autoBestCompliant:
            return "Motor Autônomo WisdAI ($0): escuta local (SpeechAnalyzer) + cérebro local (ANE) + Voz WisdAI, independente do agente de código."
        case .appleLocalHybrid:
            return "Gratuito ($0): processamento integralmente local/on-device sem envio de áudio para APIs externas."
        case .codexAppServerRealtime:
            return "Usa apenas os limites oficiais do processo Codex app-server autenticado."
        case .openAIRealtimeAPI:
            return "Pago via API OpenAI (~US$ 10–64/1M tokens áudio). ChatGPT Plus NÃO inclui API."
        case .geminiLiveAPI:
            return "Via Google AI Studio (~US$ 3/1M in, US$ 12/1M out; contexto acumula). Gemini Pro consumidor NÃO cobre API direta."
        case .hybridDeepgramElevenLabs:
            return "Pago por uso: Deepgram (~US$ 0.0058/min) + ElevenLabs Flash v2.5 (~US$ 0.04–0.05/1k chars)."
        case .hybridOpenAITTS:
            return "Pago via API OpenAI: gpt-4o-mini-tts / tts-1 (PCM streaming) + seu agente conectado."
        }
    }
}

public enum VoiceGatewayError: LocalizedError, Equatable {
    case paidAPIDisabled(provider: String)
    case externalAudioConsentRequired(provider: String)
    case missingOfficialAPIKey(provider: String)
    case onDeviceRecognitionUnavailable(locale: String)
    case networkConnectionFailed(String)
    case protocolError(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .paidAPIDisabled(let provider):
            return "\(provider) exige habilitação explícita de APIs de voz pagas nas Configurações → Voz (desativado por padrão)."
        case .externalAudioConsentRequired(let provider):
            return "Consentimento explícito necessário antes de enviar áudio de microfone para \(provider)."
        case .missingOfficialAPIKey(let provider):
            return "Nenhuma chave de API oficial configurada no Chaves do macOS para \(provider)."
        case .onDeviceRecognitionUnavailable(let locale):
            return "Reconhecimento offline Apple Speech ainda não disponível para \(locale); habilite pacote offline nos Ajustes do macOS ou autorize nuvem."
        case .networkConnectionFailed(let detail):
            return "Falha de conexão no gateway de voz: \(detail)"
        case .protocolError(let detail):
            return "Erro de protocolo no provedor de voz: \(detail)"
        case .cancelled:
            return "Sessão de voz cancelada."
        }
    }
}

// MARK: - Provider-Agnostic Protocol Contracts

public struct VoiceSessionConfig: Equatable, Sendable {
    public var language: VoiceLanguageVariant
    public var systemInstructions: String
    public var voiceName: String
    public var semanticVADPreferred: Bool
    public var initialContextItems: [CodexContinuityItem]
    public var speechRate: Float // 0.75...1.35

    public init(
        language: VoiceLanguageVariant = .portugueseBR,
        systemInstructions: String = "",
        voiceName: String = "cedar",
        semanticVADPreferred: Bool = true,
        initialContextItems: [CodexContinuityItem] = [],
        speechRate: Float = 1.0
    ) {
        self.language = language
        self.systemInstructions = systemInstructions
        self.voiceName = voiceName
        self.semanticVADPreferred = semanticVADPreferred
        self.initialContextItems = initialContextItems
        self.speechRate = speechRate
    }
}

public enum RealtimeGatewayEvent: Sendable {
    case sessionReady(sessionId: String)
    case resumptionHandleUpdated(String)
    case userSpeechStarted
    case userSpeechStopped
    case inputTranscriptDelta(itemId: String, text: String)
    case inputTranscriptCompleted(itemId: String, text: String)
    case assistantItemStarted(itemId: String)
    case assistantAudioDelta(itemId: String, pcm16: Data, sampleRate: Double)
    case assistantTranscriptDelta(itemId: String, text: String)
    case assistantTurnCompleted(itemId: String, finalText: String)
    case assistantInterrupted
    case error(String)
    case disconnected(reason: String)
}

public protocol RealtimeSpeechToSpeechTransport: AnyObject, Sendable {
    var providerID: String { get }
    var inputSampleRateHz: Double { get }
    var outputSampleRateHz: Double { get }
    func connect(config: VoiceSessionConfig, resumptionHandle: String?, onEvent: @escaping @Sendable (RealtimeGatewayEvent) -> Void) async throws
    func sendAudioPCM16(_ pcm16Data: Data) async
    func commitInputAudio() async
    func triggerResponse(promptText: String?) async
    func injectContextUpdate(_ text: String, triggerReply: Bool) async
    func cancelActiveResponse() async
    func truncateAssistantItem(itemId: String, audioEndMs: Int) async
    func disconnect() async
}

public protocol StreamingSpeechToTextProvider: AnyObject, Sendable {
    var providerID: String { get }
    var requiresNetworkConsent: Bool { get }
    func start(
        language: VoiceLanguageVariant,
        policy: VoicePolicyPreferences,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws
    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer, monoFloats: [Float], sampleRate: Double)
    func stop()
}

public protocol StreamingTextToSpeechProvider: AnyObject, Sendable {
    var providerID: String { get }
    var requiresPaidOptIn: Bool { get }
    func synthesizeChunk(
        _ text: String,
        language: VoiceLanguageVariant,
        voicePreference: String,
        rate: Float,
        onAudioFloats24k: @escaping @Sendable ([Float], String) -> Void
    ) async throws
    func cancelAll()
}

// MARK: - Policy Enforcement Gate (Mandatory Compliance Guard)

public enum VoiceComplianceGate {
    public static func validateExternalAudioAccess(
        providerName: String,
        isPaidAPI: Bool,
        requiresAPIKey: Bool,
        apiKey: String?,
        policy: VoicePolicyPreferences
    ) throws {
        if isPaidAPI && !policy.allowPaidVoiceAPIs {
            throw VoiceGatewayError.paidAPIDisabled(provider: providerName)
        }
        if !policy.externalAudioConsentGranted {
            throw VoiceGatewayError.externalAudioConsentRequired(provider: providerName)
        }
        if requiresAPIKey {
            let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                throw VoiceGatewayError.missingOfficialAPIKey(provider: providerName)
            }
        }
    }

    public static func validatePaidCloudTTSAccess(
        providerName: String,
        apiKey: String?,
        policy: VoicePolicyPreferences
    ) throws {
        guard policy.allowPaidVoiceAPIs else {
            throw VoiceGatewayError.paidAPIDisabled(provider: providerName)
        }
        let trimmed = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            throw VoiceGatewayError.missingOfficialAPIKey(provider: providerName)
        }
    }
}

// MARK: - Official OpenAI Realtime WebSocket Transport (API Key Opt-In Only)

public final class OpenAIRealtimeWebSocketTransport: RealtimeSpeechToSpeechTransport, @unchecked Sendable {
    public let providerID = "openai_realtime_api"
    public let inputSampleRateHz: Double = 24_000
    public let outputSampleRateHz: Double = 24_000

    private let apiKeyProvider: @Sendable () -> String?
    private let policyProvider: @Sendable () -> VoicePolicyPreferences
    private let modelName: String

    private var session: URLSession?
    private var wsTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var eventCallback: (@Sendable (RealtimeGatewayEvent) -> Void)?
    private var isConnected = false
    private var connectionEpoch: UInt64 = 0
    private let stateLock = NSLock()

    public init(
        modelName: String = "gpt-realtime-2.1",
        apiKeyProvider: (@Sendable () -> String?)? = nil,
        policyProvider: @escaping @Sendable () -> VoicePolicyPreferences = { VoicePolicyPreferences.load() }
    ) {
        self.modelName = modelName
        self.apiKeyProvider = apiKeyProvider ?? { AccountKeychain.readProviderKey(provider: .openai) }
        self.policyProvider = policyProvider
    }

    public func connect(
        config: VoiceSessionConfig,
        resumptionHandle: String?,
        onEvent: @escaping @Sendable (RealtimeGatewayEvent) -> Void
    ) async throws {
        let key = apiKeyProvider()
        let policy = policyProvider()
        try VoiceComplianceGate.validateExternalAudioAccess(
            providerName: "OpenAI Realtime API",
            isPaidAPI: true,
            requiresAPIKey: true,
            apiKey: key,
            policy: policy
        )
        guard let trimmedKey = key?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(modelName)") else {
            throw VoiceGatewayError.missingOfficialAPIKey(provider: "OpenAI Realtime API")
        }

        await disconnect()
        stateLock.withLock {
            self.eventCallback = onEvent
        }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        let urlSession = URLSession(configuration: cfg)
        var req = URLRequest(url: url)
        req.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        req.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")
        req.timeoutInterval = 20

        let task = urlSession.webSocketTask(with: req)
        let epoch = stateLock.withLock { () -> UInt64 in
            self.session = urlSession
            self.wsTask = task
            self.isConnected = true
            self.connectionEpoch &+= 1
            return self.connectionEpoch
        }
        task.resume()
        startReceiveLoop(task: task, epoch: epoch)

        let turnDetection: [String: Any] = config.semanticVADPreferred
            ? ["type": "semantic_vad", "eagerness": "medium", "interrupt_response": true, "create_response": true]
            : ["type": "server_vad", "threshold": 0.5, "prefix_padding_ms": 300, "silence_duration_ms": 620, "interrupt_response": true, "create_response": true]

        let sessionUpdate: [String: Any] = [
            "type": "session.update",
            "session": [
                "modalities": ["audio", "text"],
                "instructions": config.systemInstructions,
                "voice": config.voiceName.isEmpty ? "cedar" : config.voiceName,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": "gpt-4o-mini-transcribe",
                    "language": config.language.bcp47LanguagePrefix
                ],
                "turn_detection": turnDetection
            ]
        ]
        try await sendJSON(sessionUpdate)

        for item in config.initialContextItems.suffix(12) {
            let role = item.role == "assistant" ? "assistant" : "user"
            let partType = role == "assistant" ? "text" : "input_text"
            let createEvent: [String: Any] = [
                "type": "conversation.item.create",
                "item": [
                    "type": "message",
                    "role": role,
                    "content": [["type": partType, "text": item.text]]
                ]
            ]
            try? await sendJSON(createEvent)
        }
        onEvent(.sessionReady(sessionId: UUID().uuidString))
    }

    public func sendAudioPCM16(_ pcm16Data: Data) async {
        guard !pcm16Data.isEmpty else { return }
        let b64 = pcm16Data.base64EncodedString()
        try? await sendJSON(["type": "input_audio_buffer.append", "audio": b64])
    }

    public func commitInputAudio() async {
        try? await sendJSON(["type": "input_audio_buffer.commit"])
    }

    public func triggerResponse(promptText: String?) async {
        if let promptText, !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await injectContextUpdate(promptText, triggerReply: true)
            return
        }
        try? await sendJSON(["type": "response.create", "response": ["modalities": ["audio", "text"]]])
    }

    public func injectContextUpdate(_ text: String, triggerReply: Bool) async {
        let msg: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": text]]
            ]
        ]
        try? await sendJSON(msg)
        if triggerReply {
            try? await sendJSON(["type": "response.create", "response": ["modalities": ["audio", "text"]]])
        }
    }

    public func cancelActiveResponse() async {
        try? await sendJSON(["type": "response.cancel"])
    }

    public func truncateAssistantItem(itemId: String, audioEndMs: Int) async {
        guard !itemId.isEmpty else { return }
        try? await sendJSON([
            "type": "conversation.item.truncate",
            "item_id": itemId,
            "content_index": 0,
            "audio_end_ms": max(0, audioEndMs)
        ])
    }

    public func disconnect() async {
        let (task, sess, rx) = stateLock.withLock { () -> (URLSessionWebSocketTask?, URLSession?, Task<Void, Never>?) in
            self.isConnected = false
            self.connectionEpoch &+= 1
            self.eventCallback = nil
            let t = self.wsTask
            let s = self.session
            let r = self.receiveTask
            self.wsTask = nil
            self.session = nil
            self.receiveTask = nil
            return (t, s, r)
        }
        rx?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        sess?.invalidateAndCancel()
    }

    private func sendJSON(_ obj: [String: Any]) async throws {
        guard let task = stateLock.withLock({ isConnected ? wsTask : nil }) else { return }
        let data = try JSONSerialization.data(withJSONObject: obj)
        guard let str = String(data: data, encoding: .utf8) else { return }
        try await task.send(.string(str))
    }

    private func startReceiveLoop(task: URLSessionWebSocketTask, epoch: UInt64) {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    guard let self, self.stateLock.withLock({ self.connectionEpoch == epoch && self.isConnected }) else { break }
                    let rawData: Data?
                    switch message {
                    case .string(let s): rawData = s.data(using: .utf8)
                    case .data(let d): rawData = d
                    @unknown default: rawData = nil
                    }
                    if let rawData,
                       let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
                        self.handleServerEvent(json, epoch: epoch)
                    }
                } catch {
                    if let self, self.stateLock.withLock({ self.connectionEpoch == epoch }) {
                        self.emit(.disconnected(reason: error.localizedDescription), epoch: epoch)
                    }
                    break
                }
            }
        }
    }

    private func handleServerEvent(_ json: [String: Any], epoch: UInt64) {
        guard let type = json["type"] as? String else { return }
        switch type {
        case "input_audio_buffer.speech_started":
            emit(.userSpeechStarted, epoch: epoch)
        case "input_audio_buffer.speech_stopped":
            emit(.userSpeechStopped, epoch: epoch)
        case "conversation.item.input_audio_transcription.completed":
            let itemId = json["item_id"] as? String ?? UUID().uuidString
            let text = json["transcript"] as? String ?? ""
            emit(.inputTranscriptCompleted(itemId: itemId, text: text), epoch: epoch)
        case "response.output_item.added":
            if let item = json["item"] as? [String: Any], let itemId = item["id"] as? String {
                emit(.assistantItemStarted(itemId: itemId), epoch: epoch)
            }
        case "response.audio.delta":
            let itemId = json["item_id"] as? String ?? ""
            if let b64 = json["delta"] as? String, let pcm = Data(base64Encoded: b64) {
                emit(.assistantAudioDelta(itemId: itemId, pcm16: pcm, sampleRate: outputSampleRateHz), epoch: epoch)
            }
        case "response.audio_transcript.delta", "response.text.delta":
            let itemId = json["item_id"] as? String ?? ""
            let delta = json["delta"] as? String ?? ""
            if !delta.isEmpty { emit(.assistantTranscriptDelta(itemId: itemId, text: delta), epoch: epoch) }
        case "response.audio_transcript.done", "response.done":
            let itemId = json["item_id"] as? String ?? ""
            let text = json["transcript"] as? String ?? ""
            if !text.isEmpty || type == "response.done" {
                emit(.assistantTurnCompleted(itemId: itemId, finalText: text), epoch: epoch)
            }
        case "error":
            let msg = (json["error"] as? [String: Any])?["message"] as? String ?? "Erro na API OpenAI Realtime"
            emit(.error(msg), epoch: epoch)
        default:
            break
        }
    }

    private func emit(_ event: RealtimeGatewayEvent, epoch: UInt64) {
        let cb = stateLock.withLock { (connectionEpoch == epoch) ? eventCallback : nil }
        cb?(event)
    }
}

// MARK: - Official Google Gemini Live WebSocket Transport (API Key Opt-In Only)

public final class GeminiLiveWebSocketTransport: RealtimeSpeechToSpeechTransport, @unchecked Sendable {
    public let providerID = "gemini_live_api"
    public let inputSampleRateHz: Double = 16_000
    public let outputSampleRateHz: Double = 24_000

    private let apiKeyProvider: @Sendable () -> String?
    private let policyProvider: @Sendable () -> VoicePolicyPreferences
    private let modelID: String

    private var session: URLSession?
    private var wsTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var eventCallback: (@Sendable (RealtimeGatewayEvent) -> Void)?
    private var activeItemId = UUID().uuidString
    private var accumulatedTurnText = ""
    private var connectionEpoch: UInt64 = 0
    private let stateLock = NSLock()

    public init(
        modelID: String = "models/gemini-2.5-flash-native-audio-preview-12-2025",
        apiKeyProvider: (@Sendable () -> String?)? = nil,
        policyProvider: @escaping @Sendable () -> VoicePolicyPreferences = { VoicePolicyPreferences.load() }
    ) {
        self.modelID = modelID
        self.apiKeyProvider = apiKeyProvider ?? { AccountKeychain.readProviderKey(provider: .gemini) }
        self.policyProvider = policyProvider
    }

    public func connect(
        config: VoiceSessionConfig,
        resumptionHandle: String?,
        onEvent: @escaping @Sendable (RealtimeGatewayEvent) -> Void
    ) async throws {
        let key = apiKeyProvider()
        let policy = policyProvider()
        try VoiceComplianceGate.validateExternalAudioAccess(
            providerName: "Google Gemini Live API",
            isPaidAPI: true,
            requiresAPIKey: true,
            apiKey: key,
            policy: policy
        )
        guard let trimmedKey = key?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent") else {
            throw VoiceGatewayError.missingOfficialAPIKey(provider: "Google Gemini Live API")
        }

        await disconnect()
        stateLock.withLock {
            self.eventCallback = onEvent
            self.activeItemId = UUID().uuidString
            self.accumulatedTurnText = ""
        }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        let urlSession = URLSession(configuration: cfg)
        var req = URLRequest(url: url)
        req.setValue(trimmedKey, forHTTPHeaderField: "x-goog-api-key")
        req.timeoutInterval = 20

        let task = urlSession.webSocketTask(with: req)
        let epoch = stateLock.withLock { () -> UInt64 in
            self.session = urlSession
            self.wsTask = task
            self.connectionEpoch &+= 1
            return self.connectionEpoch
        }
        task.resume()
        startReceiveLoop(task: task, epoch: epoch)

        var setup: [String: Any] = [
            "model": modelID,
            "generationConfig": [
                "responseModalities": ["AUDIO"]
            ],
            "realtimeInputConfig": [
                "automaticActivityDetection": [
                    "disabled": false
                ]
            ]
        ]
        if !config.systemInstructions.isEmpty {
            setup["systemInstruction"] = [
                "parts": [["text": config.systemInstructions]]
            ]
        }
        if let resumptionHandle, !resumptionHandle.isEmpty {
            setup["sessionResumption"] = ["handle": resumptionHandle]
        } else {
            setup["sessionResumption"] = [:]
        }

        try await sendJSON(["setup": setup])
        onEvent(.sessionReady(sessionId: UUID().uuidString))
    }

    public func sendAudioPCM16(_ pcm16Data: Data) async {
        guard !pcm16Data.isEmpty else { return }
        let payload: [String: Any] = [
            "realtimeInput": [
                "mediaChunks": [[
                    "mimeType": "audio/pcm;rate=16000",
                    "data": pcm16Data.base64EncodedString()
                ]]
            ]
        ]
        try? await sendJSON(payload)
    }

    public func commitInputAudio() async {
        try? await sendJSON(["realtimeInput": ["audioStreamEnd": true]])
    }

    public func triggerResponse(promptText: String?) async {
        guard let promptText, !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await injectContextUpdate(promptText, triggerReply: true)
    }

    public func injectContextUpdate(_ text: String, triggerReply: Bool) async {
        let payload: [String: Any] = [
            "clientContent": [
                "turns": [[
                    "role": "user",
                    "parts": [["text": text]]
                ]],
                "turnComplete": triggerReply
            ]
        ]
        try? await sendJSON(payload)
    }

    public func cancelActiveResponse() async {
        // Sending empty client interrupt marker or relying on live audio activity barge-in.
        stateLock.withLock {
            self.activeItemId = UUID().uuidString
            self.accumulatedTurnText = ""
        }
    }

    public func truncateAssistantItem(itemId: String, audioEndMs: Int) async {
        let note = "[O usuário interrompeu após \(audioEndMs)ms; desconsidere o restante não ouvido desta resposta.]"
        await injectContextUpdate(note, triggerReply: false)
    }

    public func disconnect() async {
        let (task, sess, rx) = stateLock.withLock { () -> (URLSessionWebSocketTask?, URLSession?, Task<Void, Never>?) in
            self.connectionEpoch &+= 1
            self.eventCallback = nil
            let t = self.wsTask
            let s = self.session
            let r = self.receiveTask
            self.wsTask = nil
            self.session = nil
            self.receiveTask = nil
            return (t, s, r)
        }
        rx?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        sess?.invalidateAndCancel()
    }

    private func sendJSON(_ obj: [String: Any]) async throws {
        guard let task = stateLock.withLock({ wsTask }) else { return }
        let data = try JSONSerialization.data(withJSONObject: obj)
        guard let str = String(data: data, encoding: .utf8) else { return }
        try await task.send(.string(str))
    }

    private func startReceiveLoop(task: URLSessionWebSocketTask, epoch: UInt64) {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    guard let self, self.stateLock.withLock({ self.connectionEpoch == epoch }) else { break }
                    let rawData: Data?
                    switch message {
                    case .string(let s): rawData = s.data(using: .utf8)
                    case .data(let d): rawData = d
                    @unknown default: rawData = nil
                    }
                    if let rawData,
                       let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any] {
                        self.handleServerJSON(json, epoch: epoch)
                    }
                } catch {
                    if let self, self.stateLock.withLock({ self.connectionEpoch == epoch }) {
                        self.emit(.disconnected(reason: error.localizedDescription), epoch: epoch)
                    }
                    break
                }
            }
        }
    }

    private func handleServerJSON(_ json: [String: Any], epoch: UInt64) {
        if let resumption = json["sessionResumptionUpdate"] as? [String: Any],
           let handle = resumption["newHandle"] as? String, !handle.isEmpty {
            emit(.resumptionHandleUpdated(handle), epoch: epoch)
        }
        guard let serverContent = json["serverContent"] as? [String: Any] else { return }
        if (serverContent["interrupted"] as? Bool) == true {
            emit(.assistantInterrupted, epoch: epoch)
        }
        if let inputTrans = (serverContent["inputTranscription"] as? [String: Any])?["text"] as? String, !inputTrans.isEmpty {
            emit(.inputTranscriptDelta(itemId: "user-live", text: inputTrans), epoch: epoch)
        }
        if let modelTurn = serverContent["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            let itemId = stateLock.withLock { activeItemId }
            for part in parts {
                if let inline = part["inlineData"] as? [String: Any],
                   let mime = (inline["mimeType"] as? String)?.lowercased(),
                   mime.contains("audio/pcm"),
                   let b64 = inline["data"] as? String,
                   let pcm = Data(base64Encoded: b64) {
                    emit(.assistantAudioDelta(itemId: itemId, pcm16: pcm, sampleRate: outputSampleRateHz), epoch: epoch)
                }
                if let txt = part["text"] as? String, !txt.isEmpty {
                    stateLock.withLock { accumulatedTurnText += txt }
                    emit(.assistantTranscriptDelta(itemId: itemId, text: txt), epoch: epoch)
                }
            }
        }
        if (serverContent["turnComplete"] as? Bool) == true {
            let (finishedId, finishedText) = stateLock.withLock { () -> (String, String) in
                let id = self.activeItemId
                let t = self.accumulatedTurnText
                self.activeItemId = UUID().uuidString
                self.accumulatedTurnText = ""
                return (id, t)
            }
            emit(.assistantTurnCompleted(itemId: finishedId, finalText: finishedText), epoch: epoch)
        }
    }

    private func emit(_ event: RealtimeGatewayEvent, epoch: UInt64) {
        let cb = stateLock.withLock { (connectionEpoch == epoch) ? eventCallback : nil }
        cb?(event)
    }
}

// MARK: - Apple Continuous Streaming STT (Overcomes 60s Limit, On-Device First)

public final class AppleSpeechStreamingSTTProvider: StreamingSpeechToTextProvider, @unchecked Sendable {
    public let providerID = "apple_speech_streaming"
    public private(set) var requiresNetworkConsent: Bool = false

    private let lock = NSLock()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var rotationTimer: DispatchSourceTimer?
    private var activeLanguage: VoiceLanguageVariant = .portugueseBR
    private var activePolicy: VoicePolicyPreferences = .strictDefault
    private var accumulatedPrefix: String = ""
    private var currentSegmentText: String = ""
    private var segmentEpoch: UInt64 = 0
    private var isStopped: Bool = true

    private var onPartialCB: (@Sendable (String) -> Void)?
    private var onFinalCB: (@Sendable (String) -> Void)?
    private var onErrorCB: (@Sendable (String) -> Void)?

    public init() {}

    public static func authorizationAuthorized() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    public static func requestAuthorizationIfNeeded() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        if status == .denied || status == .restricted { return false }
        return await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { newStatus in
                cont.resume(returning: newStatus == .authorized)
            }
        }
    }

    public func start(
        language: VoiceLanguageVariant,
        policy: VoicePolicyPreferences,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws {
        guard await Self.requestAuthorizationIfNeeded() else {
            throw VoiceGatewayError.protocolError("Permissão de Reconhecimento de Fala negada nos Ajustes do macOS.")
        }
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: language.appleLocaleIdentifier)), rec.isAvailable else {
            throw VoiceGatewayError.protocolError("Reconhecimento de fala Apple indisponível no momento para \(language.displayName).")
        }

        let supportsLocal = rec.supportsOnDeviceRecognition
        if policy.preferOnDeviceSpeechOnly && !supportsLocal && !policy.externalAudioConsentGranted {
            throw VoiceGatewayError.onDeviceRecognitionUnavailable(locale: language.displayName)
        }
        requiresNetworkConsent = !(policy.preferOnDeviceSpeechOnly && supportsLocal)

        stop()

        lock.withLock {
            self.recognizer = rec
            self.activeLanguage = language
            self.activePolicy = policy
            self.accumulatedPrefix = ""
            self.currentSegmentText = ""
            self.onPartialCB = onPartial
            self.onFinalCB = onFinal
            self.onErrorCB = onError
            self.isStopped = false
        }

        startRecognitionSegment()
        startRotationWatchdog()
    }

    public func feedAudioBuffer(_ buffer: AVAudioPCMBuffer, monoFloats: [Float], sampleRate: Double) {
        let req = lock.withLock { request }
        req?.append(buffer)
    }

    public func commitCurrentUtterance() -> String {
        let (combined, shouldRotate) = lock.withLock { () -> (String, Bool) in
            let joined = [accumulatedPrefix, currentSegmentText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            accumulatedPrefix = ""
            currentSegmentText = ""
            segmentEpoch &+= 1
            return (joined, !isStopped)
        }
        if shouldRotate {
            DispatchQueue.main.async { [weak self] in
                self?.startRecognitionSegment()
            }
        }
        return combined
    }

    public func resetUtteranceBuffer() {
        let shouldRotate = lock.withLock { () -> Bool in
            accumulatedPrefix = ""
            currentSegmentText = ""
            segmentEpoch &+= 1
            return !isStopped
        }
        if shouldRotate {
            DispatchQueue.main.async { [weak self] in
                self?.startRecognitionSegment()
            }
        }
    }

    public func stop() {
        let (t, r, timer) = lock.withLock { () -> (SFSpeechRecognitionTask?, SFSpeechAudioBufferRecognitionRequest?, DispatchSourceTimer?) in
            isStopped = true
            segmentEpoch &+= 1
            onPartialCB = nil
            onFinalCB = nil
            onErrorCB = nil
            let task = self.task
            let req = self.request
            let tmr = self.rotationTimer
            self.task = nil
            self.request = nil
            self.rotationTimer = nil
            self.accumulatedPrefix = ""
            self.currentSegmentText = ""
            return (task, req, tmr)
        }
        timer?.cancel()
        r?.endAudio()
        t?.cancel()
    }

    private func startRecognitionSegment() {
        let snapshot = lock.withLock { () -> (SFSpeechRecognizer?, VoicePolicyPreferences, Bool, UInt64) in
            segmentEpoch &+= 1
            return (recognizer, activePolicy, isStopped, segmentEpoch)
        }
        guard !snapshot.2, let rec = snapshot.0 else { return }
        let taskEpoch = snapshot.3

        let newReq = SFSpeechAudioBufferRecognitionRequest()
        newReq.shouldReportPartialResults = true
        newReq.addsPunctuation = true
        if snapshot.1.preferOnDeviceSpeechOnly && rec.supportsOnDeviceRecognition {
            newReq.requiresOnDeviceRecognition = true
        }

        lock.withLock {
            self.task?.cancel()
            self.request?.endAudio()
            self.request = newReq
        }

        let newTask = rec.recognitionTask(with: newReq) { [weak self] result, err in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasSemanticChars = text.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) })
                let (fullText, isFinal, partialCB) = self.lock.withLock { () -> (String, Bool, (@Sendable (String) -> Void)?) in
                    guard !self.isStopped, self.segmentEpoch == taskEpoch else { return ("", false, nil) }
                    if hasSemanticChars {
                        self.currentSegmentText = text
                    }
                    let full = [self.accumulatedPrefix, self.currentSegmentText]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    return (full, result.isFinal, self.onPartialCB)
                }
                if !fullText.isEmpty {
                    partialCB?(fullText)
                }
                if isFinal {
                    self.rotateAfterNaturalEnd(expectedEpoch: taskEpoch)
                }
            }
            if let err {
                let ns = err as NSError
                let (validEpoch, errCB) = self.lock.withLock { () -> (Bool, (@Sendable (String) -> Void)?) in
                    guard !self.isStopped, self.segmentEpoch == taskEpoch else { return (false, nil) }
                    return (true, self.onErrorCB)
                }
                guard validEpoch else { return }
                // Recover seamlessly from Apple's 1110 "No speech detected" / timeout without dropping voice session.
                if ns.code == 1110 || ns.code == 216 || ns.code == 203 {
                    self.rotateAfterNaturalEnd(expectedEpoch: taskEpoch)
                } else {
                    errCB?(err.localizedDescription)
                }
            }
        }
        lock.withLock {
            if self.segmentEpoch == taskEpoch && !self.isStopped {
                self.task = newTask
            } else {
                newTask.cancel()
            }
        }
    }

    private func rotateAfterNaturalEnd(expectedEpoch: UInt64? = nil) {
        let shouldRestart = lock.withLock { () -> Bool in
            guard !self.isStopped else { return false }
            if let expectedEpoch, self.segmentEpoch != expectedEpoch { return false }
            let seg = self.currentSegmentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !seg.isEmpty {
                self.accumulatedPrefix = [self.accumulatedPrefix, seg]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                self.currentSegmentText = ""
            }
            return true
        }
        if shouldRestart {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                if let expectedEpoch, self.lock.withLock({ self.segmentEpoch != expectedEpoch || self.isStopped }) {
                    return
                }
                self.startRecognitionSegment()
            }
        }
    }

    private func startRotationWatchdog() {
        // Rotate cleanly every 48 seconds so continuous long sessions never hit Apple's hard 60-second termination ceiling.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + 48.0, repeating: 48.0)
        timer.setEventHandler { [weak self] in
            self?.rotateAfterNaturalEnd()
        }
        lock.withLock {
            self.rotationTimer?.cancel()
            self.rotationTimer = timer
        }
        timer.resume()
    }
}

// MARK: - Deepgram Streaming STT Provider (Opt-In Paid API Only)

public final class DeepgramStreamingSTTProvider: StreamingSpeechToTextProvider, @unchecked Sendable {
    public let providerID = "deepgram_streaming_stt"
    public let requiresNetworkConsent = true

    private let apiKeyProvider: @Sendable () -> String?
    private let model: String
    private var session: URLSession?
    private var wsTask: URLSessionWebSocketTask?
    private var rxTask: Task<Void, Never>?
    private let lock = NSLock()
    private var onPartialCB: (@Sendable (String) -> Void)?
    private var onFinalCB: (@Sendable (String) -> Void)?
    private var onErrorCB: (@Sendable (String) -> Void)?
    private var lastSourceRate: Double = 48_000
    private var sessionEpoch: UInt64 = 0

    public init(
        model: String = "nova-3",
        apiKeyProvider: @escaping @Sendable () -> String? = { VoiceKeychainStore.readKey(for: .deepgram) }
    ) {
        self.model = model
        self.apiKeyProvider = apiKeyProvider
    }

    public func start(
        language: VoiceLanguageVariant,
        policy: VoicePolicyPreferences,
        onPartial: @escaping @Sendable (String) -> Void,
        onFinal: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) async throws {
        let key = apiKeyProvider()
        try VoiceComplianceGate.validateExternalAudioAccess(
            providerName: "Deepgram STT",
            isPaidAPI: true,
            requiresAPIKey: true,
            apiKey: key,
            policy: policy
        )
        guard let trimmedKey = key?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw VoiceGatewayError.missingOfficialAPIKey(provider: "Deepgram STT")
        }
        stop()

        let urlStr = "wss://api.deepgram.com/v1/listen?model=\(model)&language=\(language.appleLocaleIdentifier)&encoding=linear16&sample_rate=16000&channels=1&interim_results=true&smart_format=true&endpointing=300"
        guard let url = URL(string: urlStr) else { throw VoiceGatewayError.protocolError("URL Deepgram inválida") }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        let urlSession = URLSession(configuration: cfg)
        var req = URLRequest(url: url)
        req.setValue("Token \(trimmedKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let task = urlSession.webSocketTask(with: req)
        let epoch = lock.withLock { () -> UInt64 in
            self.session = urlSession
            self.wsTask = task
            self.onPartialCB = onPartial
            self.onFinalCB = onFinal
            self.onErrorCB = onError
            self.sessionEpoch &+= 1
            return self.sessionEpoch
        }
        task.resume()

        rxTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let msg = try await task.receive()
                    guard let self, self.lock.withLock({ self.sessionEpoch == epoch }) else { break }
                    let raw: Data? = {
                        switch msg {
                        case .string(let s): return s.data(using: .utf8)
                        case .data(let d): return d
                        @unknown default: return nil
                        }
                    }()
                    guard let raw,
                          let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                          let channel = json["channel"] as? [String: Any],
                          let alts = channel["alternatives"] as? [[String: Any]],
                          let transcript = (alts.first?["transcript"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !transcript.isEmpty else { continue }
                    let isFinal = (json["is_final"] as? Bool) ?? false
                    if isFinal {
                        self.lock.withLock { self.sessionEpoch == epoch ? self.onFinalCB : nil }?(transcript)
                    } else {
                        self.lock.withLock { self.sessionEpoch == epoch ? self.onPartialCB : nil }?(transcript)
                    }
                } catch {
                    if let self {
                        self.lock.withLock { self.sessionEpoch == epoch ? self.onErrorCB : nil }?(error.localizedDescription)
                    }
                    break
                }
            }
        }
    }

    public func feedAudioBuffer(_ buffer: AVAudioPCMBuffer, monoFloats: [Float], sampleRate: Double) {
        guard !monoFloats.isEmpty else { return }
        lastSourceRate = sampleRate
        let downsampled = AudioPCMConverter.resampleLinear(samples: monoFloats, fromSampleRate: sampleRate, toSampleRate: 16_000)
        let pcm = AudioPCMConverter.floatsToPCM16Data(downsampled)
        let task = lock.withLock { wsTask }
        task?.send(.data(pcm)) { _ in }
    }

    public func stop() {
        let (t, s, r) = lock.withLock { () -> (URLSessionWebSocketTask?, URLSession?, Task<Void, Never>?) in
            sessionEpoch &+= 1
            onPartialCB = nil
            onFinalCB = nil
            onErrorCB = nil
            let a = wsTask; let b = session; let c = rxTask
            wsTask = nil; session = nil; rxTask = nil
            return (a, b, c)
        }
        r?.cancel()
        t?.cancel(with: .normalClosure, reason: nil)
        s?.invalidateAndCancel()
    }
}

// MARK: - Compliant Streaming TTS Providers (Local Clean PCM / Opt-In Cloud Neural)

public final class AppleNaturalPCMStreamingTTSProvider: NSObject, StreamingTextToSpeechProvider, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    public let providerID = "apple_natural_pcm_tts"
    public let requiresPaidOptIn = false

    private let synth = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var cancelled = false
    private var activeCancelHook: (@Sendable () -> Void)?

    public override init() {
        super.init()
        synth.delegate = self
    }

    public static func selectBestNaturalVoice(
        for language: VoiceLanguageVariant,
        preferredIdentifier: String?
    ) -> AVSpeechSynthesisVoice? {
        let all = AVSpeechSynthesisVoice.speechVoices()
        if let preferredIdentifier,
           preferredIdentifier != "auto",
           !preferredIdentifier.hasPrefix("persona:"),
           let exact = AVSpeechSynthesisVoice(identifier: preferredIdentifier) {
            return exact
        }
        let wantsMale = preferredIdentifier == "persona:atlas"
        let wantsFemale = preferredIdentifier == "persona:aurora" || preferredIdentifier == "persona:aria"
        if language.bcp47LanguagePrefix == "pt", !wantsMale {
            for siriID in ["com.apple.siri.natural.Sandra", "com.apple.siri.natural.pt-BR.female"] {
                if let siriVoice = AVSpeechSynthesisVoice(identifier: siriID) {
                    return siriVoice
                }
            }
        }
        let exactLocale = all.filter { $0.language.caseInsensitiveCompare(language.appleLocaleIdentifier) == .orderedSame }
        let familyPrefix = language.bcp47LanguagePrefix
        let familyVoices = exactLocale.isEmpty
            ? all.filter { $0.language.lowercased().hasPrefix(familyPrefix) }
            : exactLocale

        // Prioritize Siri/Natural/Premium voices and exclude legacy robotic Eloquence voices unless nothing else exists.
        let ranked = familyVoices.sorted { a, b in
            func score(_ v: AVSpeechSynthesisVoice) -> Int {
                let idL = v.identifier.lowercased()
                var s = v.quality.rawValue * 100
                if idL.contains("siri") || idL.contains("natural") { s += 500 }
                if idL.contains("eloquence") { s -= 1000 }
                if wantsMale && v.gender == .male { s += 250 }
                if wantsFemale && v.gender == .female { s += 250 }
                return s
            }
            return score(a) > score(b)
        }
        return ranked.first ?? AVSpeechSynthesisVoice(language: language.appleLocaleIdentifier)
    }

    public func synthesizeChunk(
        _ text: String,
        language: VoiceLanguageVariant,
        voicePreference: String,
        rate: Float,
        onAudioFloats24k: @escaping @Sendable ([Float], String) -> Void
    ) async throws {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        lock.withLock { cancelled = false }

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = Self.selectBestNaturalVoice(for: language, preferredIdentifier: voicePreference)
        // Map friendly 0.75...1.35 scale around Apple's default rate smoothly.
        let clampedRate = min(max(rate, 0.75), 1.35)
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * clampedRate))
        utterance.pitchMultiplier = 1.0 // Zero synthetic pitch-shifting distortion!
        utterance.preUtteranceDelay = 0.0
        utterance.postUtteranceDelay = 0.03

        final class SynthProgressState: @unchecked Sendable {
            private let lock = NSLock()
            private var finished = false
            private var emittedChunk = false
            func markFinishedIfFirst() -> Bool {
                lock.withLock {
                    guard !finished else { return false }
                    finished = true
                    return true
                }
            }
            func claimFirstChunkLabel() -> Bool {
                lock.withLock {
                    guard !emittedChunk else { return false }
                    emittedChunk = true
                    return true
                }
            }
        }
        let progressState = SynthProgressState()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            @Sendable func finishOnce() {
                if progressState.markFinishedIfFirst() {
                    self.lock.withLock { self.activeCancelHook = nil }
                    continuation.resume()
                }
            }

            self.lock.withLock {
                self.activeCancelHook = {
                    finishOnce()
                }
            }
            if self.lock.withLock({ self.cancelled }) {
                finishOnce()
                return
            }

            // Safety timeout matching bounded utterance duration.
            let watchdog = DispatchWorkItem { finishOnce() }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 25.0, execute: watchdog)

            synth.write(utterance) { [weak self] buffer in
                guard let self else { finishOnce(); return }
                let isCancelled = self.lock.withLock { self.cancelled }
                if isCancelled {
                    watchdog.cancel()
                    finishOnce()
                    return
                }
                guard let pcm = buffer as? AVAudioPCMBuffer else {
                    watchdog.cancel()
                    finishOnce()
                    return
                }
                if pcm.frameLength == 0 {
                    watchdog.cancel()
                    finishOnce()
                    return
                }
                let mono = AudioPCMConverter.mixToMono(buffer: pcm)
                let resampled = AudioPCMConverter.resampleLinear(samples: mono, fromSampleRate: pcm.format.sampleRate, toSampleRate: 24_000)
                if !resampled.isEmpty {
                    let spanLabel = progressState.claimFirstChunkLabel() ? clean : ""
                    onAudioFloats24k(resampled, spanLabel)
                }
            }
        }
    }

    public func cancelAll() {
        let cancelHook = lock.withLock { () -> (@Sendable () -> Void)? in
            cancelled = true
            let h = activeCancelHook
            activeCancelHook = nil
            return h
        }
        synth.stopSpeaking(at: .immediate)
        cancelHook?()
    }
}

public final class ElevenLabsStreamingTTSProvider: StreamingTextToSpeechProvider, @unchecked Sendable {
    public let providerID = "elevenlabs_flash_v2_5"
    public let requiresPaidOptIn = true

    private let apiKeyProvider: @Sendable () -> String?
    private let policyProvider: @Sendable () -> VoicePolicyPreferences
    private let lock = NSLock()
    private var activeTask: Task<Void, Never>?

    public init(
        apiKeyProvider: @escaping @Sendable () -> String? = { VoiceKeychainStore.readKey(for: .elevenLabs) },
        policyProvider: @escaping @Sendable () -> VoicePolicyPreferences = { VoicePolicyPreferences.load() }
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.policyProvider = policyProvider
    }

    public func synthesizeChunk(
        _ text: String,
        language: VoiceLanguageVariant,
        voicePreference: String,
        rate: Float,
        onAudioFloats24k: @escaping @Sendable ([Float], String) -> Void
    ) async throws {
        let key = apiKeyProvider()
        let policy = policyProvider()
        try VoiceComplianceGate.validatePaidCloudTTSAccess(providerName: "ElevenLabs TTS", apiKey: key, policy: policy)
        guard let trimmedKey = key?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw VoiceGatewayError.missingOfficialAPIKey(provider: "ElevenLabs TTS")
        }

        let voiceId = voicePreference.count >= 12 ? voicePreference : "21m00Tcm4TlvDq8ikWAM"
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)/stream?output_format=pcm_24000") else {
            throw VoiceGatewayError.protocolError("URL ElevenLabs inválida")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue(trimmedKey, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": "eleven_flash_v2_5",
            "language_code": language.bcp47LanguagePrefix,
            "voice_settings": [
                "stability": 0.45,
                "similarity_boost": 0.78,
                "speed": min(max(Double(rate), 0.7), 1.2)
            ]
        ])

        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw VoiceGatewayError.protocolError("ElevenLabs HTTP \(status)")
        }

        var pendingPCM = Data()
        var labelled = false
        for try await byte in bytes {
            if Task.isCancelled { break }
            pendingPCM.append(byte)
            if pendingPCM.count >= 4_800 { // ~100 ms chunk @ 24kHz Int16
                let evenCount = pendingPCM.count - (pendingPCM.count % 2)
                let slice = pendingPCM.prefix(evenCount)
                pendingPCM.removeFirst(evenCount)
                let floats = AudioPCMConverter.pcm16DataToFloats(slice)
                if !floats.isEmpty {
                    onAudioFloats24k(floats, labelled ? "" : text)
                    labelled = true
                }
            }
        }
        let evenRest = pendingPCM.count - (pendingPCM.count % 2)
        if evenRest > 0 && !Task.isCancelled {
            let floats = AudioPCMConverter.pcm16DataToFloats(pendingPCM.prefix(evenRest))
            if !floats.isEmpty {
                onAudioFloats24k(floats, labelled ? "" : text)
            }
        }
    }

    public func cancelAll() {
        lock.withLock {
            activeTask?.cancel()
            activeTask = nil
        }
    }
}

public final class OpenAIStreamingTTSProvider: StreamingTextToSpeechProvider, @unchecked Sendable {
    public let providerID = "openai_streaming_tts"
    public let requiresPaidOptIn = true

    private let apiKeyProvider: @Sendable () -> String?
    private let policyProvider: @Sendable () -> VoicePolicyPreferences
    private let modelName: String

    public init(
        modelName: String = "gpt-4o-mini-tts",
        apiKeyProvider: (@Sendable () -> String?)? = nil,
        policyProvider: @escaping @Sendable () -> VoicePolicyPreferences = { VoicePolicyPreferences.load() }
    ) {
        self.modelName = modelName
        self.apiKeyProvider = apiKeyProvider ?? { AccountKeychain.readProviderKey(provider: .openai) }
        self.policyProvider = policyProvider
    }

    public func synthesizeChunk(
        _ text: String,
        language: VoiceLanguageVariant,
        voicePreference: String,
        rate: Float,
        onAudioFloats24k: @escaping @Sendable ([Float], String) -> Void
    ) async throws {
        let key = apiKeyProvider()
        let policy = policyProvider()
        try VoiceComplianceGate.validatePaidCloudTTSAccess(providerName: "OpenAI TTS", apiKey: key, policy: policy)
        guard let trimmedKey = key?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: "https://api.openai.com/v1/audio/speech") else {
            throw VoiceGatewayError.missingOfficialAPIKey(provider: "OpenAI TTS")
        }

        let allowedVoices = ["alloy", "ash", "ballad", "cedar", "coral", "echo", "marin", "sage", "shimmer", "verse"]
        let selectedVoice = allowedVoices.contains(voicePreference.lowercased()) ? voicePreference.lowercased() : "cedar"

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelName,
            "voice": selectedVoice,
            "input": text,
            "response_format": "pcm",
            "speed": min(max(Double(rate), 0.75), 1.35)
        ])

        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.urlCredentialStorage = nil
        let session = URLSession(configuration: cfg)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw VoiceGatewayError.protocolError("OpenAI TTS HTTP \(status)")
        }

        var pendingPCM = Data()
        var labelled = false
        for try await byte in bytes {
            if Task.isCancelled { break }
            pendingPCM.append(byte)
            if pendingPCM.count >= 4_800 {
                let evenCount = pendingPCM.count - (pendingPCM.count % 2)
                let slice = pendingPCM.prefix(evenCount)
                pendingPCM.removeFirst(evenCount)
                let floats = AudioPCMConverter.pcm16DataToFloats(slice)
                if !floats.isEmpty {
                    onAudioFloats24k(floats, labelled ? "" : text)
                    labelled = true
                }
            }
        }
        let evenRest = pendingPCM.count - (pendingPCM.count % 2)
        if evenRest > 0 && !Task.isCancelled {
            let floats = AudioPCMConverter.pcm16DataToFloats(pendingPCM.prefix(evenRest))
            if !floats.isEmpty {
                onAudioFloats24k(floats, labelled ? "" : text)
            }
        }
    }

    public func cancelAll() {
        // Cancellation happens cooperatively via structured Task cancellation on bytes stream.
    }
}

// MARK: - Provider Resolution Engine

public struct ResolvedVoicePipeline: Equatable, Sendable {
    public let effectiveProvider: VoiceGatewayProviderKind
    public let activeSTTName: String
    public let activeTTSName: String
    public let isUsingPaidCloud: Bool
    public let advisoryBanner: String?
}

public enum VoicePipelineResolver {
    public static func resolve(
        requested: VoiceGatewayProviderKind,
        policy: VoicePolicyPreferences,
        hasOpenAIKey: Bool,
        hasGeminiKey: Bool,
        hasDeepgramKey: Bool,
        hasElevenLabsKey: Bool,
        hasCodexAppServer: Bool
    ) -> ResolvedVoicePipeline {
        switch requested {
        case .openAIRealtimeAPI:
            if policy.allowPaidVoiceAPIs && policy.externalAudioConsentGranted && hasOpenAIKey {
                return ResolvedVoicePipeline(effectiveProvider: .openAIRealtimeAPI, activeSTTName: "OpenAI Realtime S2S", activeTTSName: "OpenAI Realtime S2S", isUsingPaidCloud: true, advisoryBanner: nil)
            }
        case .geminiLiveAPI:
            if policy.allowPaidVoiceAPIs && policy.externalAudioConsentGranted && hasGeminiKey {
                return ResolvedVoicePipeline(effectiveProvider: .geminiLiveAPI, activeSTTName: "Gemini Live S2S", activeTTSName: "Gemini Live S2S", isUsingPaidCloud: true, advisoryBanner: nil)
            }
        case .hybridDeepgramElevenLabs:
            if policy.allowPaidVoiceAPIs && policy.externalAudioConsentGranted && hasDeepgramKey && hasElevenLabsKey {
                return ResolvedVoicePipeline(effectiveProvider: .hybridDeepgramElevenLabs, activeSTTName: "Deepgram Nova-3", activeTTSName: "ElevenLabs Flash v2.5", isUsingPaidCloud: true, advisoryBanner: nil)
            }
        case .hybridOpenAITTS:
            if policy.allowPaidVoiceAPIs && hasOpenAIKey {
                return ResolvedVoicePipeline(effectiveProvider: .hybridOpenAITTS, activeSTTName: hasDeepgramKey && policy.externalAudioConsentGranted ? "Deepgram Nova-3" : "Apple Speech", activeTTSName: "OpenAI gpt-4o-mini-tts", isUsingPaidCloud: true, advisoryBanner: nil)
            }
        case .codexAppServerRealtime:
            if hasCodexAppServer && policy.externalAudioConsentGranted {
                return ResolvedVoicePipeline(effectiveProvider: .codexAppServerRealtime, activeSTTName: "Codex App-Server Realtime", activeTTSName: "Codex App-Server Realtime", isUsingPaidCloud: false, advisoryBanner: nil)
            }
        case .appleLocalHybrid:
            return ResolvedVoicePipeline(effectiveProvider: .appleLocalHybrid, activeSTTName: "SpeechAnalyzer On-Device", activeTTSName: "Voz WisdAI Local (PCM)", isUsingPaidCloud: false, advisoryBanner: nil)
        case .autoBestCompliant:
            if policy.allowPaidVoiceAPIs && policy.externalAudioConsentGranted {
                if hasOpenAIKey {
                    return ResolvedVoicePipeline(effectiveProvider: .openAIRealtimeAPI, activeSTTName: "OpenAI Realtime S2S", activeTTSName: "OpenAI Realtime S2S", isUsingPaidCloud: true, advisoryBanner: nil)
                }
                if hasGeminiKey {
                    return ResolvedVoicePipeline(effectiveProvider: .geminiLiveAPI, activeSTTName: "Gemini Live S2S", activeTTSName: "Gemini Live S2S", isUsingPaidCloud: true, advisoryBanner: nil)
                }
                if hasDeepgramKey && hasElevenLabsKey {
                    return ResolvedVoicePipeline(effectiveProvider: .hybridDeepgramElevenLabs, activeSTTName: "Deepgram Nova-3", activeTTSName: "ElevenLabs Flash v2.5", isUsingPaidCloud: true, advisoryBanner: nil)
                }
            }
            if policy.allowPaidVoiceAPIs && hasOpenAIKey {
                return ResolvedVoicePipeline(effectiveProvider: .hybridOpenAITTS, activeSTTName: "SpeechAnalyzer On-Device", activeTTSName: "OpenAI gpt-4o-mini-tts", isUsingPaidCloud: true, advisoryBanner: nil)
            }
        }

        let banner: String? = (requested != .appleLocalHybrid && requested != .autoBestCompliant)
            ? "Motor Autônomo WisdAI ativo ($0 · Local): configure uma chave oficial e habilite o opt-in nas Configurações apenas se desejar usar \(requested.displayName)."
            : nil

        return ResolvedVoicePipeline(
            effectiveProvider: .appleLocalHybrid,
            activeSTTName: "SpeechAnalyzer On-Device",
            activeTTSName: "Voz WisdAI Local (PCM)",
            isUsingPaidCloud: false,
            advisoryBanner: banner
        )
    }
}
