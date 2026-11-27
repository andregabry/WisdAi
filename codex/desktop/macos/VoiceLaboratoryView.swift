import AppKit
import SwiftUI

// MARK: - Configurações → Voz → Laboratório de Voz (Phases 10 & 11)

struct VoiceLaboratoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var orchestrator: WisdVoiceOrchestrator

    @ObservedObject private var assetManager: VoiceModelAssetManager
    @ObservedObject private var llamaRuntime: LocalLlamaServerBrainRuntime
    @ObservedObject private var mlxRuntime: LocalMLXClientRuntime
    @ObservedObject private var localBrain: LocalConversationalBrain
    @ObservedObject private var telemetry: VoiceTelemetryRecorder
    @ObservedObject private var previewPlayer: VoiceAudioPreviewPlayer
    @ObservedObject private var vocalizationCache: VocalizationCacheEngine
    @ObservedObject private var mlxTTS: LocalExpressiveTTSLoopbackClient

    @State private var activeSection: LabSection = .enginesAndAudio
    @State private var sampleText: String = "Olá! Eu sou a voz neural local do WisdAI. Agora consigo conversar com naturalidade, baixa latência e interrupção imediata."
    @State private var brainPromptInput: String = "Explique em duas frases objetivas por que a baixa latência melhora a conversa por voz."
    @State private var brainTestOutput: String = ""
    @State private var brainTestMetrics: String?
    @State private var isTestingBrain: Bool = false
    @State private var sampleResultMessage: String?
    @State private var lastGeneratedWAV: Data?
    @State private var comparisonSummary: String?
    @State private var isSynthesizingSample: Bool = false
    @State private var cacheAuditMessage: String?

    @State private var hygieneCandidates: [VoiceMemoryContaminationCandidate] = []
    @State private var selectedHygieneIDs: Set<String> = []
    @State private var hygieneStatusMessage: String?
    @State private var hasScannedHygiene: Bool = false

    private enum LabSection: String, CaseIterable, Identifiable {
        case enginesAndAudio = "Motores & Voz"
        case behaviorAndCache = "Comportamento V3"
        case modelCatalog = "Modelos & Hardware"
        case telemetryAndTrace = "Telemetria & Pipeline"
        case memoryHygiene = "Higiene de Memória"

        var id: String { rawValue }
    }

    init(orchestrator: WisdVoiceOrchestrator) {
        self.orchestrator = orchestrator
        self.assetManager = orchestrator.modelAssetManager
        self.llamaRuntime = orchestrator.llamaBrainRuntime
        self.mlxRuntime = orchestrator.mlxBrainRuntime
        self.localBrain = orchestrator.localBrain
        self.telemetry = orchestrator.telemetry
        self.previewPlayer = orchestrator.previewPlayer
        self.vocalizationCache = orchestrator.vocalizationCache
        self.mlxTTS = orchestrator.mlxExpressiveTTS
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBar

            Picker("Seção do Laboratório", selection: $activeSection) {
                ForEach(LabSection.allCases) { sec in
                    Text(sec.rawValue).tag(sec)
                }
            }
            .pickerStyle(.segmented)

            if let consentReason = assetManager.pendingConsentReason {
                consentBanner(reason: consentReason)
            }

            if let transfer = assetManager.activeTransfer {
                transferProgressBanner(transfer)
            }

            switch activeSection {
            case .enginesAndAudio:
                enginesAndAudioSection
            case .behaviorAndCache:
                behaviorAndCacheSection
            case .modelCatalog:
                hardwareAndCatalogSection
            case .telemetryAndTrace:
                telemetryAndTraceSection
            case .memoryHygiene:
                memoryHygieneSection
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesktopStyle.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DesktopStyle.line))
        .onAppear {
            assetManager.refreshStorageInfo()
            localBrain.refreshBackendAvailability()
            orchestrator.refreshResolvedPipeline()
            telemetry.refreshResources(llamaServerPID: llamaRuntime.currentProcessID)
        }
        .onChange(of: localBrain.preferredEngineKind) { _, _ in
            localBrain.refreshBackendAvailability()
            orchestrator.refreshResolvedPipeline()
        }
        .onChange(of: llamaRuntime.selectedModelID) { _, newID in
            if llamaRuntime.isRunning && llamaRuntime.loadedModelID != newID {
                llamaRuntime.unloadModel()
            }
            localBrain.refreshBackendAvailability()
            orchestrator.refreshResolvedPipeline()
        }
        .onChange(of: orchestrator.selectedTTSEngine) { _, _ in
            orchestrator.refreshResolvedPipeline()
        }
    }

    private var headerBar: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WisdTheme.iconAccent)
                    Text("Laboratório de Voz · WisdAI Engine V3")
                        .font(.system(size: 14.5, weight: .semibold))
                }
                Text("Cérebro ativo: \(localBrain.backendStatus.rawValue) · Voz: \(orchestrator.telemetry.activeProviderLabel) · Perfil: \(orchestrator.behavior.profilePreset.displayName) · Hardware: \(assetManager.selectedHardwareTier.displayName)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DesktopStyle.muted)
                Text(WisdVoiceBuildInfo.summary)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(DesktopStyle.muted.opacity(0.85))
            }
            Spacer()
            Button("Atualizar Status") {
                assetManager.refreshStorageInfo()
                localBrain.refreshBackendAvailability()
                orchestrator.refreshResolvedPipeline()
                telemetry.refreshResources(llamaServerPID: llamaRuntime.currentProcessID)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func consentBanner(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(WisdTheme.iconAccent)
                Text("Autorização Explícita de Download Neural (SHA-256 Verificado)")
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(reason)
                .font(.system(size: 11.5))
            if let warn = assetManager.pendingConsentModels.compactMap(\.licenseWarning).first {
                Text(warn)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                Button("Autorizar e Baixar") {
                    assetManager.confirmAndStartAuthorizedDownload()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Cancelar") {
                    assetManager.declineConsent()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
        }
        .padding(12)
        .background(WisdTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WisdTheme.accent.opacity(0.35)))
    }

    private func transferProgressBanner(_ transfer: ModelAssetTransferState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(transfer.statusMessage)
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text(String(format: "%.0f%% · %.1f MB/s", transfer.progress * 100.0, transfer.bytesPerSecond / (1024.0 * 1024.0)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DesktopStyle.muted)
                Button("Cancelar") {
                    assetManager.cancelTransfer()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            ProgressView(value: transfer.progress)
                .progressViewStyle(.linear)
        }
        .padding(10)
        .background(DesktopStyle.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Tab 1: Motores, Áudio & Comparação

    private var enginesAndAudioSection: some View {
        let s2sProbe = NativeS2SRuntimeProbe.evaluate(hardwareTier: assetManager.selectedHardwareTier)
        let matchingPresets = KokoroVoicePreset.allCases.filter {
            $0.supportedLanguage == orchestrator.behavior.languageVariant
        }

        return VStack(alignment: .leading, spacing: 14) {
            // Brain selector & test
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Cérebro Conversacional Local (Intercambiável)")
                    .font(.system(size: 12.5, weight: .semibold))

                Picker("Motor do Cérebro", selection: $localBrain.preferredEngineKind) {
                    ForEach(VoiceBrainEngineKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                if localBrain.preferredEngineKind == .localLlamaCppMetal || localBrain.preferredEngineKind == .adaptiveAuto {
                    HStack(spacing: 8) {
                        Picker("Modelo GGUF Metal", selection: $llamaRuntime.selectedModelID) {
                            ForEach(VoiceModelCatalog.availableLocalModels.filter { $0.category == .llm && $0.isDownloadable }) { model in
                                let st = assetManager.installStates[model.id] ?? .notInstalled
                                Text("\(model.displayName) [\(st.rawValue)]").tag(model.id)
                            }
                        }

                        if llamaRuntime.isRunning {
                            Button("Descarregar") {
                                llamaRuntime.unloadModel()
                                localBrain.refreshBackendAvailability()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else if llamaRuntime.isSelectedModelReadyOnDisk {
                            Button(llamaRuntime.isLoadingModel ? "Carregando…" : "Carregar") {
                                Task {
                                    _ = try? await llamaRuntime.ensureServerReady()
                                    localBrain.refreshBackendAvailability()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(llamaRuntime.isLoadingModel)
                        } else {
                            Button("Baixar GGUF…") {
                                assetManager.requestDownloadConsent(for: llamaRuntime.selectedModelID)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                if localBrain.preferredEngineKind == .localMLXServer {
                    HStack(spacing: 8) {
                        Text("Porta Loopback MLX (127.0.0.1):")
                            .font(.system(size: 11.5))
                        TextField("Porta", value: $mlxRuntime.port, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Button("Verificar MLX") {
                            Task {
                                _ = await mlxRuntime.probeAvailability()
                                localBrain.refreshBackendAvailability()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Text(mlxRuntime.isServerReachable ? "Conectado (\(mlxRuntime.activeModelName))" : (mlxRuntime.lastError ?? "Off-line"))
                            .font(.system(size: 11))
                            .foregroundStyle(mlxRuntime.isServerReachable ? .green : .orange)
                    }
                }

                HStack(spacing: 8) {
                    TextField("Prompt rápido para validar cérebro local…", text: $brainPromptInput)
                        .textFieldStyle(.roundedBorder)
                    Button(isTestingBrain ? "Testando…" : "Testar Cérebro") {
                        runBrainTest()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isTestingBrain || brainPromptInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if !brainTestOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if let brainTestMetrics {
                            Text(brainTestMetrics)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(WisdTheme.softAccentText)
                        }
                        Text(brainTestOutput)
                            .font(.system(size: 11.5))
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesktopStyle.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Divider()

            // Architecture mode & Speech-to-Speech readiness
            VStack(alignment: .leading, spacing: 6) {
                Text("2. Arquitetura de Voz (Híbrido Neural vs Speech-to-Speech Nativo)")
                    .font(.system(size: 12.5, weight: .semibold))
                Picker("Modo de Execução", selection: $orchestrator.executionArchitecture) {
                    ForEach(VoiceExecutionArchitectureMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                if orchestrator.executionArchitecture == .nativeSpeechToSpeech, let blocker = s2sProbe.blockerReason {
                    Label(blocker, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            // Neural TTS selector + honest capability gating + audio testing
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("3. Síntese Vocal Neural & Teste Comparativo")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    let kokoroState = assetManager.installStates[VoiceModelCatalog.kokoroInt8ModelID] ?? .notInstalled
                    Text("Kokoro-82M: \(kokoroState.rawValue)")
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }

                Picker("Motor TTS", selection: $orchestrator.selectedTTSEngine) {
                    ForEach(VoiceTTSEngineKind.allCases) { eng in
                        Text(eng.displayName).tag(eng)
                    }
                }

                if let warn = orchestrator.selectedTTSEngine.licenseWarning {
                    Label(warn, systemImage: "exclamationmark.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                if orchestrator.selectedTTSEngine == .chatterbox || orchestrator.selectedTTSEngine == .cosyVoice2 || orchestrator.selectedTTSEngine == .sesameCSM || orchestrator.selectedTTSEngine == .diaTTS {
                    HStack(spacing: 8) {
                        Text("Porta Loopback mlx-audio (127.0.0.1):")
                            .font(.system(size: 11.5))
                        TextField("Porta", value: $mlxTTS.port, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Button("Verificar mlx-audio") {
                            Task { _ = await mlxTTS.probeServer() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Text(mlxTTS.isServerReachable ? "Conectado (\(mlxTTS.activeModelName))" : (mlxTTS.lastError ?? "Off-line"))
                            .font(.system(size: 11))
                            .foregroundStyle(mlxTTS.isServerReachable ? .green : .orange)
                    }
                }

                HStack(spacing: 10) {
                    Picker("Idioma do Teste", selection: $orchestrator.behavior.languageVariant) {
                        ForEach(VoiceLanguageVariant.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }

                    if !matchingPresets.isEmpty {
                        Picker("Voz Kokoro", selection: $orchestrator.selectedKokoroPreset) {
                            ForEach(matchingPresets) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                    }
                }

                if orchestrator.behavior.languageVariant == .portuguesePT &&
                    (orchestrator.selectedTTSEngine == .kokoro82M || orchestrator.selectedTTSEngine == .autoLocal) {
                    Label(
                        "Honestidade linguística: Kokoro-82M não possui fonetização pt-PT nativa (seu código 'p' gera pt-BR). Use Apple Voz Natural para pt-PT.",
                        systemImage: "info.circle.fill"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                }

                if orchestrator.selectedTTSEngine.supportsSpeedControl {
                    HStack {
                        Text("Velocidade Real (\(String(format: "%.2f×", orchestrator.behavior.speechRate)))")
                            .font(.system(size: 11.5))
                        Slider(value: $orchestrator.behavior.speechRate, in: 0.75...1.30, step: 0.05)
                            .tint(WisdTheme.accent)
                    }
                } else {
                    Text("Controles avançados de cadência/emoção estão ocultos porque este adaptador não os suporta nativamente neste dispositivo.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesktopStyle.muted)
                }

                TextField("Texto para prévia e comparação de áudio…", text: $sampleText)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Button(isSynthesizingSample ? "Sintetizando…" : "Ouvir Motor Selecionado") {
                        synthesizeSample(using: orchestrator.selectedTTSEngine)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isSynthesizingSample || sampleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if orchestrator.behavior.languageVariant == .portugueseBR && orchestrator.kokoroTTS.isReadyOnDisk {
                        Button("Ouvir pf_dora") {
                            synthesizePresetSample(.pfDora)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isSynthesizingSample)

                        Button("Ouvir pm_alex") {
                            synthesizePresetSample(.pmAlex)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isSynthesizingSample)
                    }

                    Button("Comparar Kokoro vs Apple") {
                        runComparativeABTest()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSynthesizingSample)

                    Button("Comparar V2 vs V3") {
                        runV2vsV3BehaviorComparison()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSynthesizingSample)

                    if previewPlayer.isPlaying {
                        Button("Parar Áudio") {
                            previewPlayer.stop()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let wav = lastGeneratedWAV {
                        Button("Salvar WAV…") {
                            saveWAVPanel(wav)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Spacer()

                    if !orchestrator.kokoroTTS.isReadyOnDisk {
                        Button("Instalar Kokoro-82M INT8 (~135 MB)") {
                            assetManager.requestDownloadConsent(for: VoiceModelCatalog.kokoroInt8ModelID)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if orchestrator.behavior.languageVariant == .portugueseBR {
                    Text("Avaliação PT-BR ativa: pf_dora e pm_alex disponíveis para comparação A/B e uso imediato em sessão; seleção final permanece aberta até aprovação.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesktopStyle.muted)
                }

                if let sampleResultMessage {
                    Text(sampleResultMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(DesktopStyle.muted)
                }
                if let comparisonSummary {
                    Text(comparisonSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(WisdTheme.softAccentText)
                }
            }
        }
    }

    // MARK: - Tab V3: Conversational Behavior Engine & Vocalization Cache

    private var behaviorAndCacheSection: some View {
        let personality = VoicePersonalityProfile.profile(for: orchestrator.voiceIdentity.persona)
        let engineCaps = EngineProsodyCapabilities.forEngine(
            orchestrator.selectedTTSEngine,
            isKokoroActive: orchestrator.selectedTTSEngine == .kokoro82M || (orchestrator.selectedTTSEngine == .autoLocal && orchestrator.kokoroTTS.isReadyOnDisk && orchestrator.behavior.languageVariant != .portuguesePT)
        )

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Perfil Conversacional (WisdAI Conversational Behavior Engine)")
                    .font(.system(size: 12.5, weight: .semibold))

                Picker("Perfil Ativo", selection: Binding(
                    get: { orchestrator.behavior.profilePreset },
                    set: { orchestrator.applyConversationProfilePreset($0) }
                )) {
                    ForEach(VoiceConversationProfilePreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                Text(orchestrator.behavior.profilePreset.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(DesktopStyle.muted)

                if orchestrator.behavior.profilePreset == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Escuta Ativa com Backchanneling durante fala do usuário", isOn: $orchestrator.behavior.enableActiveListening)
                        Toggle("Prosódia Contextual por Intenção", isOn: $orchestrator.behavior.enableContextualProsody)

                        HStack {
                            Text("Frequência de Feedback Vocal (\(Int(orchestrator.behavior.backchannelFrequency * 100))%)")
                                .font(.system(size: 11))
                            Slider(value: $orchestrator.behavior.backchannelFrequency, in: 0.0...1.0, step: 0.05)
                        }
                        HStack {
                            Text("Intensidade das Vocalizações (\(Int(orchestrator.behavior.vocalizationIntensity * 100))%)")
                                .font(.system(size: 11))
                            Slider(value: $orchestrator.behavior.vocalizationIntensity, in: 0.15...0.75, step: 0.05)
                        }
                        if engineCaps.supportsDynamicSilenceScale || engineCaps.supportsRateControl {
                            HStack {
                                Text("Ritmo de Fala (\(String(format: "%.2fx", orchestrator.behavior.speechRate)))")
                                    .font(.system(size: 11))
                                Slider(value: $orchestrator.behavior.speechRate, in: 0.80...1.25, step: 0.05)
                            }
                            HStack {
                                Text("Pausas Conversacionais (\(String(format: "%.2fx", orchestrator.behavior.pauseScale)))")
                                    .font(.system(size: 11))
                                Slider(value: $orchestrator.behavior.pauseScale, in: 0.70...1.50, step: 0.05)
                            }
                        }
                        HStack(spacing: 10) {
                            Picker("Expressividade", selection: $orchestrator.behavior.expressivity) {
                                ForEach(VoiceExpressivityLevel.allCases) { exp in
                                    Text(exp.displayName).tag(exp)
                                }
                            }
                            Picker("Formalidade", selection: $orchestrator.behavior.formality) {
                                ForEach(VoiceFormalityLevel.allCases) { form in
                                    Text(form.displayName).tag(form)
                                }
                            }
                            Picker("Comprimento", selection: $orchestrator.behavior.detailLevel) {
                                ForEach(VoiceDetailLevel.allCases) { det in
                                    Text(det.displayName).tag(det)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(DesktopStyle.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("2. Identidade Vocal Persistente (Voice Personality Engine)")
                    .font(.system(size: 12.5, weight: .semibold))
                Picker("Personalidade Base", selection: $orchestrator.voiceIdentity.persona) {
                    ForEach(WisdVoicePersona.allCases) { persona in
                        Text(persona.displayName).tag(persona)
                    }
                }
                Text("\(personality.interactionStyle) Calor \(Int(personality.conversationalWarmth * 100))% · Energia \(Int(personality.energy * 100))% · Objetividade \(Int(personality.directness * 100))%.")
                    .font(.system(size: 11))
                    .foregroundStyle(DesktopStyle.muted)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("3. Vocalization Cache Engine (Amostras <100 ms na Identidade Ativa)")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text("\(vocalizationCache.cachedClipsCount) clipes · \(String(format: "%.2f MB", vocalizationCache.cacheMemoryMB))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(DesktopStyle.muted)
                }

                Text(vocalizationCache.lastGenerationSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(DesktopStyle.muted)

                HStack(spacing: 8) {
                    Button(vocalizationCache.isPrewarming ? "Gerando Cache…" : "Pré-aquecer Cache Ativa") {
                        orchestrator.prewarmVocalizationCache()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(vocalizationCache.isPrewarming)

                    Button("Invalidar Cache") {
                        vocalizationCache.invalidateAll(reason: "Solicitação manual")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    ForEach([VocalizationKind.uhum, .aham, .hmm, .entendi, .interessante], id: \.rawValue) { kind in
                        Button(kind.spokenText(for: orchestrator.behavior.languageVariant)) {
                            Task {
                                let res = await orchestrator.previewCachedVocalization(kind)
                                cacheAuditMessage = res.detail
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }

                Text("Hits: \(vocalizationCache.hitCount) · Misses: \(vocalizationCache.missCount) · Última entrega: \(String(format: "%.1f ms", vocalizationCache.lastPlaybackLatencyMs)) · Escopo estrito por voz/idioma/motor.")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(DesktopStyle.muted)

                if let cacheAuditMessage {
                    Text(cacheAuditMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(WisdTheme.softAccentText)
                }
            }
        }
    }

    // MARK: - Tab 2: Hardware Profiles & Verified Model Catalog

    private var hardwareAndCatalogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Perfil Adaptativo de Hardware")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text(String(format: "%.1f GB RAM Físicos · %.1f GB Livres", telemetry.resourceSnapshot.physicalRAMGB, assetManager.availableDiskGB))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DesktopStyle.muted)
                }
                Picker("Perfil de Memória", selection: $assetManager.selectedHardwareTier) {
                    ForEach(VoiceHardwareTier.allCases) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
                Text(assetManager.selectedHardwareTier.recommendationSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(DesktopStyle.muted)
            }

            Divider()

            Text("Catálogo Unificado de Runtimes e Modelos Locais (Consentimento + SHA-256)")
                .font(.system(size: 12.5, weight: .semibold))

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(VoiceModelCatalog.availableLocalModels) { model in
                        let status = assetManager.installStates[model.id] ?? .notInstalled
                        let fit = assetManager.canFitOnDevice(model)
                        let errMsg = assetManager.modelErrorMessages[model.id]
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(model.displayName)
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text("· \(model.kind) · \(model.sizeMBText) · \(model.licenseName)")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(DesktopStyle.muted)
                                }
                                Text(model.description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(DesktopStyle.muted)
                                if let warn = model.licenseWarning {
                                    Text(warn)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.orange)
                                }
                                if let errMsg {
                                    Text(errMsg)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.red)
                                } else if !fit.ok, let reason = fit.reason, status == .incompatible {
                                    Text(reason)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Text(status.rawValue)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(statusBadgeColor(status))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(statusBadgeColor(status).opacity(0.12), in: Capsule())

                                if model.isDownloadable {
                                    if assetManager.isModelInstalledOnDisk(model) {
                                        HStack(spacing: 6) {
                                            if model.category == .llm {
                                                Button("Selecionar") {
                                                    if llamaRuntime.isRunning && llamaRuntime.loadedModelID != model.id {
                                                        llamaRuntime.unloadModel()
                                                    }
                                                    llamaRuntime.selectedModelID = model.id
                                                    localBrain.preferredEngineKind = .localLlamaCppMetal
                                                    localBrain.refreshBackendAvailability()
                                                    orchestrator.refreshResolvedPipeline()
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.mini)
                                            }
                                            Button("Remover") {
                                                if llamaRuntime.loadedModelID == model.id {
                                                    llamaRuntime.unloadModel()
                                                }
                                                if model.category == .tts || model.id == VoiceModelCatalog.sherpaRuntimeID {
                                                    orchestrator.kokoroTTS.unload()
                                                }
                                                assetManager.uninstallModel(id: model.id)
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.mini)
                                        }
                                    } else if fit.ok {
                                        Button("Baixar…") {
                                            assetManager.requestDownloadConsent(for: model.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                    }
                                }
                            }
                        }
                        .padding(9)
                        .background(DesktopStyle.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxHeight: 330)
        }
    }

    // MARK: - Tab 3: Telemetry & Opt-In 11-Stage Pipeline Trace

    private var telemetryAndTraceSection: some View {
        let res = telemetry.resourceSnapshot

        return VStack(alignment: .leading, spacing: 10) {
            Text("Métricas Reais de Desempenho & Recursos do Sistema")
                .font(.system(size: 12.5, weight: .semibold))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                metricTile(title: "Fim Fala → STT Final", value: formatStats(telemetry.sttStats))
                metricTile(title: "LLM TTFT (Commit)", value: formatStats(telemetry.llmFirstChunkStats))
                metricTile(title: "1ª Cláusula Pronta", value: formatStats(telemetry.firstClauseStats))
                metricTile(title: "TTS 1º Chunk PCM", value: formatStats(telemetry.ttsFirstAudioStats))
                metricTile(title: "TTS Síntese Total", value: formatStats(telemetry.ttsTotalSynthesisStats))
                metricTile(title: "1º Áudio Reproduzido", value: formatStats(telemetry.firstAudiblePlaybackStats))
                metricTile(title: "Fim Fala → Voz Audível", value: formatStats(telemetry.e2eFromSpeechEndAudibleStats))
                metricTile(title: "Barge-In Flush", value: formatStats(telemetry.bargeInStopStats))
                metricTile(title: "Barge-In Audível Real", value: formatStats(telemetry.bargeInAudibleStopStats))
                metricTile(title: "Cache Vocal (<100ms)", value: telemetry.vocalizationCacheLatencyStats.count > 0 ? formatStats(telemetry.vocalizationCacheLatencyStats) : "sem hits ainda")
                metricTile(title: "Escuta Ativa", value: "\(telemetry.backchannelsEmittedCount) emitidos · \(telemetry.backchannelsSuppressedCount) suprimidos")
                metricTile(title: "Estilo Acústico Usuário", value: telemetry.lastAcousticContextSummary)
            }

            HStack(spacing: 12) {
                Text(String(format: "App+Kokoro: %.1f MB · llama-server: %.1f MB · Total Voz: %.1f MB · CPU: %.1f%% (%d núcleos) · GPU Metal: %@ (máx %llu MB) · Disco: %.1f GB",
                            res.residentMemoryMB, telemetry.llamaServerMemoryMB, telemetry.totalVoiceStackMemoryMB, res.cpuPercent, res.cpuCoreCount, res.gpuName, res.gpuMaxRecommendedMB, assetManager.availableDiskGB))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DesktopStyle.muted)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesktopStyle.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

            Divider()

            HStack {
                Toggle("Diagnóstico Avançado do Pipeline (11 estágios · em memória · desligado por padrão)", isOn: $telemetry.enablePipelineDiagnosticsTrace)
                    .toggleStyle(.switch)
                Spacer()
                if !telemetry.pipelineTraceEvents.isEmpty {
                    Button("Limpar Trace") {
                        telemetry.enablePipelineDiagnosticsTrace = false
                        telemetry.enablePipelineDiagnosticsTrace = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            if telemetry.enablePipelineDiagnosticsTrace {
                if telemetry.pipelineTraceEvents.isEmpty {
                    Text("Aguardando captura de turno de voz com diagnóstico ativado…")
                        .font(.system(size: 11))
                        .foregroundStyle(DesktopStyle.muted)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(telemetry.pipelineTraceEvents.suffix(30)) { ev in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("T\(ev.turnEpoch)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(WisdTheme.softAccentText)
                                    Text(ev.stage.rawValue)
                                        .font(.system(size: 10.5, weight: .semibold))
                                    Text(ev.payload)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(DesktopStyle.muted)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                    .padding(8)
                    .background(DesktopStyle.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Tab 4: Structural Memory Hygiene Inspector

    private var memoryHygieneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inspetor Estrutural de Memória & Deriva ASR")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Localiza loops de repetição e fragmentos vazios sem apagar histórico legítimo. Nenhuma exclusão ocorre sem sua confirmação.")
                        .font(.system(size: 11))
                        .foregroundStyle(DesktopStyle.muted)
                }
                Spacer()
                Button("Verificar Memória") {
                    scanMemoryHygiene()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if let hygieneStatusMessage {
                Text(hygieneStatusMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.green)
            }

            if hasScannedHygiene {
                if hygieneCandidates.isEmpty {
                    Text("Nenhuma memória contaminada ou loop de repetição estrutural encontrado.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DesktopStyle.muted)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesktopStyle.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    HStack(spacing: 8) {
                        Button("Selecionar Tudo") {
                            selectedHygieneIDs = Set(hygieneCandidates.map(\.id))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Button("Desmarcar Tudo") {
                            selectedHygieneIDs.removeAll()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        Spacer()

                        Button("Remover Selecionados (\(selectedHygieneIDs.count))") {
                            removeSelectedHygieneItems()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(selectedHygieneIDs.isEmpty)
                    }

                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(hygieneCandidates) { item in
                                let isSelected = selectedHygieneIDs.contains(item.id)
                                Button {
                                    if isSelected {
                                        selectedHygieneIDs.remove(item.id)
                                    } else {
                                        selectedHygieneIDs.insert(item.id)
                                    }
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                            .foregroundStyle(isSelected ? WisdTheme.iconAccent : DesktopStyle.muted)
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(item.source.rawValue)
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.orange.opacity(0.15), in: Capsule())
                                                Text("\(item.roleOrTier) · \(item.threadOrScope.prefix(12))")
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundStyle(DesktopStyle.muted)
                                            }
                                            Text(item.text)
                                                .font(.system(size: 11.5))
                                                .foregroundStyle(WisdTheme.ink(colorScheme))
                                                .multilineTextAlignment(.leading)
                                            Text("Motivo: \(item.reason)")
                                                .font(.system(size: 10.5))
                                                .foregroundStyle(.orange)
                                        }
                                        Spacer()
                                    }
                                    .padding(8)
                                    .background(DesktopStyle.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            }
        }
    }

    // MARK: - Actions & Helpers

    private func runBrainTest() {
        let prompt = brainPromptInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        isTestingBrain = true
        brainTestOutput = ""
        brainTestMetrics = nil
        let lang = orchestrator.behavior.languageVariant
        let sys = "Responda em \(lang.displayName) de forma clara, objetiva e natural em 2 frases."
        Task {
            let t0 = DispatchTime.now().uptimeNanoseconds
            var ttftMs: Double?
            let reply = await localBrain.streamReply(
                userText: prompt,
                systemInstructions: sys,
                portableContextSummary: "",
                recentTurns: [],
                language: lang
            ) { delta in
                if ttftMs == nil && !delta.isEmpty {
                    ttftMs = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
                }
                self.brainTestOutput += delta
            }
            let totalMs = Double(DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000.0
            self.brainTestOutput = reply
            self.brainTestMetrics = String(
                format: "Motor: %@ | TTFT: %@ | Total: %.0f ms",
                localBrain.backendStatus.rawValue,
                ttftMs.map { String(format: "%.0f ms", $0) } ?? "-",
                totalMs
            )
            self.isTestingBrain = false
        }
    }

    private func synthesizeSample(using engine: VoiceTTSEngineKind) {
        isSynthesizingSample = true
        comparisonSummary = nil
        Task {
            let res = await orchestrator.synthesizeAndPreviewVoiceSample(
                text: sampleText,
                ttsEngine: engine,
                kokoroPreset: orchestrator.selectedKokoroPreset,
                language: orchestrator.behavior.languageVariant,
                playAudio: true
            )
            sampleResultMessage = "\(res.engineUsed): \(res.detail)"
            lastGeneratedWAV = res.wavData
            isSynthesizingSample = false
        }
    }

    private func synthesizePresetSample(_ preset: KokoroVoicePreset) {
        isSynthesizingSample = true
        comparisonSummary = nil
        Task {
            let res = await orchestrator.synthesizeAndPreviewVoiceSample(
                text: sampleText,
                ttsEngine: .kokoro82M,
                kokoroPreset: preset,
                language: .portugueseBR,
                playAudio: true
            )
            sampleResultMessage = "Avaliação \(preset.rawValue): \(res.detail)"
            lastGeneratedWAV = res.wavData
            isSynthesizingSample = false
        }
    }

    private func runComparativeABTest() {
        isSynthesizingSample = true
        Task {
            let kokoro = await orchestrator.synthesizeAndPreviewVoiceSample(
                text: sampleText,
                ttsEngine: .kokoro82M,
                kokoroPreset: orchestrator.selectedKokoroPreset,
                language: orchestrator.behavior.languageVariant,
                playAudio: true
            )
            let apple = await orchestrator.synthesizeAndPreviewVoiceSample(
                text: sampleText,
                ttsEngine: .appleNaturalPCM,
                kokoroPreset: orchestrator.selectedKokoroPreset,
                language: orchestrator.behavior.languageVariant,
                playAudio: !kokoro.ok
            )
            lastGeneratedWAV = kokoro.wavData ?? apple.wavData
            comparisonSummary = "Kokoro: \(kokoro.ok ? String(format: "%.0f ms", kokoro.synthMs) : kokoro.detail) | Apple Natural: \(apple.ok ? String(format: "%.0f ms", apple.synthMs) : apple.detail)"
            sampleResultMessage = kokoro.ok ? "Reproduzindo Kokoro (\(kokoro.detail))." : "Comparação concluída usando Apple Natural."
            isSynthesizingSample = false
        }
    }

    private func runV2vsV3BehaviorComparison() {
        isSynthesizingSample = true
        let rawFormalText = "Certamente! Aqui está a explicação solicitada: 1. Baixa latência melhora a conversa. 2. Backchanneling em cache mantém a escuta natural. Se precisar de mais alguma coisa, estou à disposição!"
        Task {
            let v2 = await orchestrator.synthesizeAndPreviewVoiceSample(
                text: rawFormalText,
                ttsEngine: orchestrator.selectedTTSEngine,
                kokoroPreset: orchestrator.selectedKokoroPreset,
                language: orchestrator.behavior.languageVariant,
                playAudio: false,
                applyBehaviorComposition: false
            )
            let v3 = await orchestrator.synthesizeAndPreviewVoiceSample(
                text: rawFormalText,
                ttsEngine: orchestrator.selectedTTSEngine,
                kokoroPreset: orchestrator.selectedKokoroPreset,
                language: orchestrator.behavior.languageVariant,
                playAudio: true,
                applyBehaviorComposition: true
            )
            lastGeneratedWAV = v3.wavData ?? v2.wavData
            let composedPreview = NaturalSpeechComposer.compose(
                rawFormalText,
                plan: orchestrator.lastBehaviorPlan,
                profile: orchestrator.behavior,
                capabilities: EngineProsodyCapabilities.forEngine(orchestrator.selectedTTSEngine, isKokoroActive: orchestrator.kokoroTTS.isReadyOnDisk),
                customDictionary: orchestrator.customPronunciation
            ).spokenText
            comparisonSummary = "Comparação V2 vs V3: V2=\(String(format: "%.0fms", v2.synthMs)) | V3(Natural Composer)=\(String(format: "%.0fms", v3.synthMs)) · Texto oral: \"\(composedPreview)\""
            sampleResultMessage = "Reproduzindo versão V3 natural (\(v3.engineUsed))."
            isSynthesizingSample = false
        }
    }

    private func saveWAVPanel(_ data: Data) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "wisdai-voice-sample.wav"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url, options: [.atomic])
            sampleResultMessage = "Amostra salva em \(url.lastPathComponent)."
        }
    }

    private func scanMemoryHygiene() {
        let extraThreads = orchestrator.onScanAdditionalChatThreads?() ?? []
        let found = VoiceMemoryHygieneAnalyzer.scan(
            knowledgeStore: orchestrator.knowledgeStore,
            continuityStore: CodexRealtimeContinuityStore.shared,
            additionalChatThreads: extraThreads
        )
        hygieneCandidates = found
        selectedHygieneIDs = Set(found.map(\.id))
        hasScannedHygiene = true
        hygieneStatusMessage = found.isEmpty ? nil : "\(found.count) registro(s) com indício de deriva ASR ou fragmento vazio encontrado(s) para revisão."
    }

    private func removeSelectedHygieneItems() {
        let toRemove = hygieneCandidates.filter { selectedHygieneIDs.contains($0.id) }
        guard !toRemove.isEmpty else { return }
        let removed = VoiceMemoryHygieneAnalyzer.removeReviewedCandidates(
            toRemove,
            knowledgeStore: orchestrator.knowledgeStore,
            continuityStore: CodexRealtimeContinuityStore.shared,
            chatHistoryRemover: orchestrator.onRemoveAdditionalChatItems
        )
        hygieneStatusMessage = "\(removed) registro(s) contaminado(s) removido(s) com segurança. Histórico legítimo preservado."
        let extraThreads = orchestrator.onScanAdditionalChatThreads?() ?? []
        let updated = VoiceMemoryHygieneAnalyzer.scan(
            knowledgeStore: orchestrator.knowledgeStore,
            continuityStore: CodexRealtimeContinuityStore.shared,
            additionalChatThreads: extraThreads
        )
        hygieneCandidates = updated
        selectedHygieneIDs = Set(updated.map(\.id))
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(DesktopStyle.muted)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesktopStyle.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatStats(_ stats: LatencySummaryStats) -> String {
        guard stats.count > 0 else { return "sem amostras" }
        return String(format: "P50 %.0fms · P95 %.0fms (%d)", stats.p50Ms, stats.p95Ms, stats.count)
    }

    private func statusBadgeColor(_ state: VoiceModelInstallState) -> Color {
        switch state {
        case .operational, .available: return .green
        case .loading, .installing, .awaitingConsent: return .blue
        case .incompatible: return .orange
        case .error: return .red
        case .notInstalled: return .gray
        }
    }
}
