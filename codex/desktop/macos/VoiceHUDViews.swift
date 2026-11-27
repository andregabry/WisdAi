import AppKit
import AVFoundation
import SwiftUI

// MARK: - WisdAI Signature Chromatic Orb (Section 16)
// Paleta oficial WisdAI: Azul Profundo, Azul Luminoso, Turquesa, Dourado e Prata.
// Renderizada em Canvas 60–120 Hz fluida, sem contornos sólidos indesejados, respeitando Reduce Motion.

public struct WisdBrandVoiceOrbView: View {
    public var size: CGFloat
    public var palette: WisdVoiceOrbPalette
    public var state: VoiceConversationState
    public var levels: CodexOrbAudioLevels

    @Environment(\.accessibilityReduceMotion) private var envReduceMotion

    public init(
        size: CGFloat = 148,
        palette: WisdVoiceOrbPalette = .wisdAIBrand,
        state: VoiceConversationState = .listening,
        levels: CodexOrbAudioLevels = .zero
    ) {
        self.size = size
        self.palette = palette
        self.state = state
        self.levels = levels
    }

    private var shouldReduceMotion: Bool {
        envReduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: shouldReduceMotion ? 0.35 : (1.0 / 60.0))) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                drawOrb(context: context, canvasSize: canvasSize, time: t)
            }
            .frame(width: size, height: size)
        }
        .accessibilityLabel("Assistente de voz WisdAI: \(state.displayTitle)")
    }

    private func drawOrb(context: GraphicsContext, canvasSize: CGSize, time: TimeInterval) {
        let center = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
        let baseRadius = min(canvasSize.width, canvasSize.height) * 0.36
        let motionScale: Double = shouldReduceMotion ? 0.15 : 1.0

        let audioEnergy = Double(max(levels.overall, levels.micLevel))
        let statePulseSpeed: Double = {
            switch state {
            case .assistantSpeaking: return 4.2
            case .processing, .consultingAgent: return 5.2
            case .userSpeaking: return 3.8
            case .listening, .connecting, .initializingLocalEngine, .loadingModel, .reconnecting: return 1.8
            case .interrupted: return 6.0
            default: return 0.9
            }
        }()

        let pulse = shouldReduceMotion ? 0.0 : sin(time * statePulseSpeed) * 0.045
        let reactiveRadius = baseRadius * (1.0 + pulse + (audioEnergy * 0.14 * motionScale))

        // Ambient chromatic glow (soft halo, ZERO hard outer stroke border)
        let haloRadius = reactiveRadius * 1.48
        let haloRect = CGRect(
            x: center.x - haloRadius,
            y: center.y - haloRadius,
            width: haloRadius * 2,
            height: haloRadius * 2
        )
        let haloGradient = Gradient(colors: [
            palette.luminousBlue.opacity(0.32 + audioEnergy * 0.25),
            palette.turquoise.opacity(0.20),
            palette.gold.opacity(0.10),
            .clear
        ])
        context.fill(
            Path(ellipseIn: haloRect),
            with: .radialGradient(haloGradient, center: center, startRadius: reactiveRadius * 0.25, endRadius: haloRadius)
        )

        // Fluid organic morphing core clipped inside dynamic wavy contour
        let corePath = organicCirclePath(
            center: center,
            radius: reactiveRadius,
            time: time * motionScale,
            energy: audioEnergy,
            state: state
        )

        context.drawLayer { layer in
            layer.clip(to: corePath)

            let orbBounds = CGRect(
                x: center.x - reactiveRadius * 1.25,
                y: center.y - reactiveRadius * 1.25,
                width: reactiveRadius * 2.5,
                height: reactiveRadius * 2.5
            )
            layer.fill(
                Path(orbBounds),
                with: .radialGradient(
                    Gradient(colors: [
                        palette.luminousBlue,
                        palette.deepBlue,
                        Color(red: 0.02, green: 0.08, blue: 0.24)
                    ]),
                    center: CGPoint(x: center.x - reactiveRadius * 0.18, y: center.y - reactiveRadius * 0.22),
                    startRadius: 4,
                    endRadius: reactiveRadius * 1.28
                )
            )

            // Rotating turquoise & gold fluid ribbons
            let shiftA = shouldReduceMotion ? 0.0 : time * 1.35
            let shiftB = shouldReduceMotion ? 0.0 : -time * 1.05
            let blobA = CGPoint(
                x: center.x + cos(shiftA) * reactiveRadius * 0.34,
                y: center.y + sin(shiftA * 1.3) * reactiveRadius * 0.28
            )
            let blobB = CGPoint(
                x: center.x + cos(shiftB) * reactiveRadius * 0.36,
                y: center.y + sin(shiftB * 0.9) * reactiveRadius * 0.32
            )
            let blobC = CGPoint(
                x: center.x + sin(shiftA * 0.7) * reactiveRadius * 0.22,
                y: center.y + cos(shiftB * 1.1) * reactiveRadius * 0.26
            )

            let rA = reactiveRadius * (0.86 + Double(levels.mid) * 0.22)
            layer.fill(
                Path(ellipseIn: CGRect(x: blobA.x - rA, y: blobA.y - rA, width: rA * 2, height: rA * 2)),
                with: .radialGradient(
                    Gradient(colors: [palette.turquoise.opacity(0.82), .clear]),
                    center: blobA,
                    startRadius: 2,
                    endRadius: rA
                )
            )

            let rB = reactiveRadius * (0.72 + Double(levels.low) * 0.25)
            layer.fill(
                Path(ellipseIn: CGRect(x: blobB.x - rB, y: blobB.y - rB, width: rB * 2, height: rB * 2)),
                with: .radialGradient(
                    Gradient(colors: [palette.gold.opacity(state == .processing ? 0.78 : 0.48), .clear]),
                    center: blobB,
                    startRadius: 2,
                    endRadius: rB
                )
            )

            let rC = reactiveRadius * (0.58 + Double(levels.high) * 0.25)
            layer.fill(
                Path(ellipseIn: CGRect(x: blobC.x - rC, y: blobC.y - rC, width: rC * 2, height: rC * 2)),
                with: .radialGradient(
                    Gradient(colors: [palette.silver.opacity(0.68), .clear]),
                    center: blobC,
                    startRadius: 1,
                    endRadius: rC
                )
            )

            // Crisp top specular highlight
            let specRadius = reactiveRadius * 0.56
            let specCenter = CGPoint(x: center.x - reactiveRadius * 0.22, y: center.y - reactiveRadius * 0.28)
            layer.fill(
                Path(ellipseIn: CGRect(x: specCenter.x - specRadius, y: specCenter.y - specRadius * 0.68, width: specRadius * 2, height: specRadius * 1.36)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.36), .clear]),
                    center: specCenter,
                    startRadius: 1,
                    endRadius: specRadius
                )
            )
        }
    }

    private func organicCirclePath(
        center: CGPoint,
        radius: CGFloat,
        time: TimeInterval,
        energy: Double,
        state: VoiceConversationState
    ) -> Path {
        let pointsCount = 64
        let amp: Double = {
            switch state {
            case .assistantSpeaking: return 0.045 + energy * 0.095
            case .userSpeaking: return 0.035 + energy * 0.085
            case .processing: return 0.055
            case .interrupted: return 0.08
            default: return 0.018
            }
        }()
        var pts: [CGPoint] = []
        pts.reserveCapacity(pointsCount)
        for i in 0..<pointsCount {
            let angle = (Double(i) / Double(pointsCount)) * .pi * 2.0
            let wave = sin(angle * 3.0 + time * 3.1) * 0.55
                + cos(angle * 5.0 - time * 2.4) * 0.45
            let r = radius * CGFloat(1.0 + wave * amp)
            pts.append(CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r))
        }
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for idx in 1..<pts.count {
            let prev = pts[idx - 1]
            let cur = pts[idx]
            let mid = CGPoint(x: (prev.x + cur.x) * 0.5, y: (prev.y + cur.y) * 0.5)
            path.addQuadCurve(to: mid, control: prev)
        }
        if let last = pts.last {
            path.addQuadCurve(to: first, control: last)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Dedicated Interactive Voice HUD Window (Compact / Expanded Modes — Section 16 & 20)

struct VoiceHUDModalView: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var orchestrator: WisdVoiceOrchestrator
    @State private var showTelemetryDrawer = false

    private var isExpanded: Bool {
        orchestrator.presentationMode == .expandedWindow
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture {
                    orchestrator.openHUDWindow(expanded: isExpanded)
                }

            VStack(spacing: 0) {
                headerBar
                Divider().background(Color.white.opacity(0.10))

                ScrollView {
                    VStack(spacing: 18) {
                        HStack(alignment: .center, spacing: 20) {
                            WisdBrandVoiceOrbView(
                                size: isExpanded ? 148 : 112,
                                palette: orchestrator.orbPalette,
                                state: orchestrator.state,
                                levels: orchestrator.audioEngine.liveLevels
                            )
                            .onTapGesture {
                                if orchestrator.state == .assistantSpeaking {
                                    orchestrator.performManualOrVADBarageIn(reason: "Toque na Orb")
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(orchestrator.state.displayTitle)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.white)

                                Text("Identidade: \(orchestrator.identityManager.configuredSnapshot.summary) · STT: \(orchestrator.resolvedPipeline.activeSTTName)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.76))

                                HStack(spacing: 8) {
                                    roleBadge(
                                        icon: "waveform",
                                        label: orchestrator.resolvedPipeline.isUsingPaidCloud ? "Cloud Autorizada" : "Motor Local ($0)"
                                    )
                                    roleBadge(
                                        icon: "brain.head.profile",
                                        label: orchestrator.brainStatus.rawValue
                                    )
                                    roleBadge(
                                        icon: "cpu",
                                        label: "Agente: \(workspace.selectedAccount?.name ?? "WisdAI")"
                                    )
                                    if !workspace.activeTasks.isEmpty {
                                        roleBadge(
                                            icon: "arrow.triangle.2.circlepath",
                                            label: "\(workspace.activeTasks.count) tarefa(s)"
                                        )
                                    }
                                }

                                audioMetersRow
                            }
                            Spacer(minLength: 0)
                        }

                        if let banner = orchestrator.activeBannerNotice, !banner.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(Color(red: 0.90, green: 0.72, blue: 0.29))
                                Text(banner)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.92))
                                Spacer()
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }

                        if isExpanded {
                            liveTranscriptSection
                            quickSelectorsGrid
                            telemetrySection
                        } else {
                            compactTranscriptBar
                        }
                    }
                    .padding(20)
                }

                Divider().background(Color.white.opacity(0.10))
                controlsFooter
            }
            .frame(width: isExpanded ? 740 : 480, height: isExpanded ? 640 : 380)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(red: 0.075, green: 0.085, blue: 0.115).opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 34, y: 12)
        }
        .sheet(isPresented: $orchestrator.showConsentDialog) {
            VoiceConsentAndOptInSheet(orchestrator: orchestrator)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            BrandLogoView(height: 18)
            Text("Modo de Voz WisdAI")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                orchestrator.presentationMode = .floatingOverlay
                orchestrator.showVoiceHUDWindow = false
            } label: {
                Label("Minimizar no Chat", systemImage: "rectangle.bottomhalf.inset.filled")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)

            Button {
                orchestrator.presentationMode = isExpanded ? .compactWindow : .expandedWindow
            } label: {
                Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered)
            .help(isExpanded ? "Modo Compacto" : "Modo Expandido")

            Button {
                workspace.toggleVoiceConversation()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Encerrar modo de voz")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func roleBadge(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(Color.white.opacity(0.88))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.09), in: Capsule())
    }

    private var audioMetersRow: some View {
        HStack(spacing: 12) {
            meterBar(title: "Microfone", value: Double(orchestrator.audioEngine.liveLevels.micLevel), color: orchestrator.orbPalette.turquoise)
            meterBar(title: "Saída", value: Double(orchestrator.audioEngine.liveLevels.overall), color: orchestrator.orbPalette.gold)
        }
    }

    private func meterBar(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.65))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, g.size.width * min(1, max(0, value))))
                }
            }
            .frame(width: 110, height: 5)
        }
    }

    private var compactTranscriptBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !orchestrator.liveUserTranscript.isEmpty {
                Text("Você: \(orchestrator.liveUserTranscript)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(2)
            }
            if !orchestrator.liveAssistantTranscript.isEmpty {
                Text("WisdAI: \(orchestrator.liveAssistantTranscript)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(orchestrator.orbPalette.silver)
                    .lineLimit(2)
            }
            if orchestrator.liveUserTranscript.isEmpty && orchestrator.liveAssistantTranscript.isEmpty {
                Text("Fale naturalmente. Pausas para pensar não interrompem sua frase; fale a qualquer hora para fazer barge-in.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.60))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private var liveTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transcrição ao Vivo & Turno Semântico")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(orchestrator.memoryStore.sessionTurns.suffix(4)) { turn in
                    HStack(alignment: .top, spacing: 6) {
                        Text(turn.role == "user" ? "Você:" : "WisdAI:")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(turn.role == "user" ? orchestrator.orbPalette.turquoise : orchestrator.orbPalette.gold)
                        Text(turn.text)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.88))
                            .lineLimit(3)
                    }
                }
                if !orchestrator.liveUserTranscript.isEmpty {
                    Text("Ouvindo: \(orchestrator.liveUserTranscript)")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                }
                if !orchestrator.liveAssistantTranscript.isEmpty {
                    Text("Falando: \(orchestrator.liveAssistantTranscript)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(orchestrator.orbPalette.silver)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var quickSelectorsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Controles Rápidos de Áudio, Provedor & Personalidade")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provedor de Voz")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Picker("", selection: $orchestrator.routing.requestedTransportProvider) {
                        ForEach(VoiceGatewayProviderKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Idioma")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Picker("", selection: $orchestrator.behavior.languageVariant) {
                        ForEach(VoiceLanguageVariant.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Identidade Vocal WisdAI")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Picker("", selection: $orchestrator.voiceIdentity.persona) {
                        ForEach(WisdVoicePersona.allCases) { persona in
                            Text(persona.displayName).tag(persona)
                        }
                    }
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Perfil Conversacional")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Picker("", selection: Binding(
                        get: { orchestrator.behavior.profilePreset },
                        set: { orchestrator.applyConversationProfilePreset($0) }
                    )) {
                        ForEach(VoiceConversationProfilePreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ritmo (\(String(format: "%.2fx", orchestrator.behavior.speechRate)))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Slider(value: $orchestrator.behavior.speechRate, in: 0.80...1.30, step: 0.05)
                }
            }

            HStack(spacing: 12) {
                if !orchestrator.audioEngine.inputDevices.isEmpty {
                    Picker("Entrada", selection: Binding(
                        get: { orchestrator.audioEngine.selectedInputDeviceUID ?? "" },
                        set: { orchestrator.audioEngine.selectInputDevice(uid: $0) }
                    )) {
                        ForEach(orchestrator.audioEngine.inputDevices, id: \.uid) { dev in
                            Text("\(dev.name) (\(dev.transport.displayLabel))").tag(dev.uid)
                        }
                    }
                }
                if !orchestrator.audioEngine.outputDevices.isEmpty {
                    Picker("Saída", selection: Binding(
                        get: { orchestrator.audioEngine.selectedOutputDeviceUID ?? "" },
                        set: { orchestrator.audioEngine.selectOutputDevice(uid: $0) }
                    )) {
                        ForEach(orchestrator.audioEngine.outputDevices, id: \.uid) { dev in
                            Text("\(dev.name) (\(dev.transport.displayLabel))").tag(dev.uid)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var telemetrySection: some View {
        let engStats = orchestrator.audioEngine.telemetrySnapshot()
        let tel = orchestrator.telemetry
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Telemetria & Estado dos Subsistemas · \(orchestrator.audioEngine.memoryProfile.displayName)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                Spacer()
                Button("Reiniciar Motor") {
                    Task { await orchestrator.restartVoiceEngine() }
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                Button("Copiar Logs") {
                    let report = orchestrator.exportSanitizedDiagnosticsReport()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
                Button("Permissões") {
                    orchestrator.showConsentDialog = true
                }
                .font(.system(size: 11))
                .buttonStyle(.bordered)
            }

            if let err = orchestrator.lastErrorSummary, !err.isEmpty {
                Text("Último erro: \(err)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.92))
            }

            Text("Build: \(WisdVoiceBuildInfo.summary) · Estado Engine: \(engStats.lifecycleState.rawValue) · AU: \(engStats.audioUnitState)")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.76))

            Text("Áudio: VPIO=\(engStats.vpioActive ? "ON" : "OFF") · Tap=\(engStats.tapInstalled ? "ON" : "OFF") · In: \(engStats.inputDeviceName) (\(Int(engStats.inputSampleRateHz))Hz/\(engStats.inputChannels)ch) · Out: \(engStats.outputDeviceName) (\(Int(engStats.outputSampleRateHz))Hz/\(engStats.outputChannels)ch)")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.68))

            Text("Grafo: \(engStats.nodeGraphSummary) · Op=\(engStats.lastOperation.rawValue) · Restarts=\(engStats.restartCount) · Recoveries=\(engStats.recoveryCount) · Jitter \(Int(engStats.outputTargetPrebufferMs))ms · Underruns=\(engStats.outputUnderruns)")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.62))

            Text(String(format: "Startup %.0fms · Barge-in %.0f/%.0fms · E2E %.0f/%.0fms · RAM %.0f MB · CPU %.1f%% (%d cores) · GPU %@",
                        orchestrator.lastStartupDurationMs,
                        tel.bargeInStopStats.p50Ms, tel.bargeInStopStats.p95Ms,
                        tel.e2eResponseStats.p50Ms, tel.e2eResponseStats.p95Ms,
                        tel.resourceSnapshot.residentMemoryMB, tel.resourceSnapshot.cpuPercent,
                        tel.resourceSnapshot.cpuCoreCount, tel.resourceSnapshot.gpuName))
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.68))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(VoiceComponentKind.allCases) { kind in
                    let snap = orchestrator.componentStatuses[kind] ?? VoiceComponentStatusSnapshot(kind: kind)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(componentDotColor(snap.state))
                            .frame(width: 6, height: 6)
                        Text("\(kind.displayName): \(snap.state.rawValue)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.84))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func componentDotColor(_ state: VoiceComponentHealthState) -> Color {
        switch state {
        case .ready: return .green
        case .initializing: return .yellow
        case .degraded: return .orange
        case .unavailable, .error: return .red
        case .idle: return .gray
        }
    }

    private var controlsFooter: some View {
        HStack(spacing: 12) {
            Button {
                orchestrator.toggleMute()
            } label: {
                Label(orchestrator.isMuted ? "Reativar Mic" : "Silenciar Mic", systemImage: orchestrator.isMuted ? "mic.slash.fill" : "mic.fill")
            }
            .buttonStyle(.bordered)

            Button {
                orchestrator.toggleOutputMute()
            } label: {
                Label(orchestrator.isOutputMuted ? "Ativar Áudio" : "Mudo Saída", systemImage: orchestrator.isOutputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)

            if orchestrator.state == .assistantSpeaking {
                Button {
                    orchestrator.performManualOrVADBarageIn(reason: "Botão interromper")
                } label: {
                    Label("Interromper", systemImage: "hand.raised.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()

            Button(role: .destructive) {
                workspace.toggleVoiceConversation()
            } label: {
                Label("Encerrar Voz", systemImage: "xmark.circle.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

// MARK: - Explicit Privacy Consent & Cost Transparency Sheet (Sections 12 & 18)

struct VoiceConsentAndOptInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var orchestrator: WisdVoiceOrchestrator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Privacidade, Consentimento e APIs Pagas de Voz")
                .font(.system(size: 17, weight: .semibold))

            Text("O WisdAI protege suas credenciais e evita cobranças inesperadas:")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Label("Assinaturas ChatGPT Plus / Google AI Pro / Claude Pro NÃO cobrem acesso comercial direto às APIs Realtime, Gemini Live API, ElevenLabs ou Deepgram.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5))
                Label("APIs pagas de voz permanecem DESATIVADAS por padrão até habilitação explícita abaixo e inserção da sua chave oficial no Chaves do macOS.", systemImage: "lock.shield.fill")
                    .font(.system(size: 12.5))
                Label("Áudio bruto do microfone nunca é gravado em disco por padrão.", systemImage: "waveform.slash")
                    .font(.system(size: 12.5))
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            Toggle("Autorizar envio de áudio de voz para servidores externos quando necessário (Apple Nuvem ou provedor selecionado)", isOn: $orchestrator.policy.externalAudioConsentGranted)
                .toggleStyle(.switch)

            Toggle("Autorizar uso de APIs comerciais pagas de voz (OpenAI Realtime / Gemini Live / Deepgram / ElevenLabs / OpenAI TTS)", isOn: $orchestrator.policy.allowPaidVoiceAPIs)
                .toggleStyle(.switch)

            Toggle("Preferir memória persistente de preferências conversacionais (Opt-In)", isOn: $orchestrator.policy.allowPersistentVoiceMemory)
                .toggleStyle(.switch)

            HStack {
                Button("Manter Somente Modo Local ($0)") {
                    orchestrator.revokeExternalAudioConsent()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Concluir") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(22)
        .frame(width: 560)
    }
}


// MARK: - Enterprise Settings Card for Configurações → Voz (Sections 3, 8, 9, 12, 16, 17, 18)

struct WisdEnterpriseVoiceSettingsCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var workspace: Workspace
    @ObservedObject var orchestrator: WisdVoiceOrchestrator

    @State private var deepgramKeyInput: String = VoiceKeychainStore.readKey(for: .deepgram) ?? ""
    @State private var elevenLabsKeyInput: String = VoiceKeychainStore.readKey(for: .elevenLabs) ?? ""
    @State private var keyFeedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Motor Conversacional em Tempo Real (WisdAI Voice)")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Ativo agora: \(orchestrator.telemetry.activeProviderLabel) · Perfil \(orchestrator.audioEngine.memoryProfile.displayName)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DesktopStyle.muted)
                }
                Spacer()
                Button("Abrir Janela de Voz") {
                    orchestrator.openHUDWindow(expanded: true)
                    if !orchestrator.isVoiceSessionActive {
                        workspace.toggleVoiceConversation()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Arquitetura e Provedor de Voz")
                    .font(.system(size: 12.5, weight: .semibold))
                Picker("Provedor", selection: $orchestrator.routing.requestedTransportProvider) {
                    ForEach(VoiceGatewayProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                Text(orchestrator.routing.requestedTransportProvider.pricingSummary)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DesktopStyle.muted)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Privacidade, Consentimento e APIs Pagas (Desativado por Padrão)")
                    .font(.system(size: 12.5, weight: .semibold))

                Toggle("Autorizar envio de áudio externo quando não estiver no modo 100% local", isOn: $orchestrator.policy.externalAudioConsentGranted)
                    .toggleStyle(.switch)
                Toggle("Autorizar uso de APIs pagas de voz (OpenAI Realtime / Gemini Live / Deepgram / ElevenLabs / OpenAI TTS)", isOn: $orchestrator.policy.allowPaidVoiceAPIs)
                    .toggleStyle(.switch)
                Toggle("Exigir Apple Speech On-Device quando disponível (sem enviar áudio de voz à rede)", isOn: $orchestrator.policy.preferOnDeviceSpeechOnly)
                    .toggleStyle(.switch)
                Toggle("Memória persistente de preferências de voz (Opt-In)", isOn: $orchestrator.policy.allowPersistentVoiceMemory)
                    .toggleStyle(.switch)

                HStack {
                    Button("Limpar Memória Persistente de Voz (FTS5)") {
                        orchestrator.memoryStore.clearPersistentMemory()
                        orchestrator.knowledgeStore.clearAllFacts()
                        keyFeedback = "Memória persistente e banco local FTS5 removidos com segurança."
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Motores & Modelos Locais (On-Device · \(orchestrator.modelAssetManager.hardwareProfile.displayName))")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text(String(format: "%.1f GB livres em disco", orchestrator.modelAssetManager.availableDiskGB))
                        .font(.system(size: 11))
                        .foregroundStyle(DesktopStyle.muted)
                }

                ForEach(VoiceModelCatalog.availableLocalModels.prefix(8)) { model in
                    let st = orchestrator.modelAssetManager.installStates[model.id] ?? .notInstalled
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(model.displayName) · \(model.kind) · \(model.licenseName)")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(model.description)
                                .font(.system(size: 11))
                                .foregroundStyle(DesktopStyle.muted)
                        }
                        Spacer()
                        Text(model.sizeBytes == 0 ? "Integrado" : "\(model.sizeMBText) · \(st.rawValue)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle((st == .operational || st == .available) ? .green : (st == .incompatible ? .orange : WisdTheme.iconAccent))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.10), in: Capsule())
                    }
                    .padding(8)
                    .background(DesktopStyle.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Identidade Vocal, Comportamento & Visual WisdAI")
                    .font(.system(size: 12.5, weight: .semibold))

                HStack(spacing: 12) {
                    Picker("Identidade Vocal", selection: $orchestrator.voiceIdentity.persona) {
                        ForEach(WisdVoicePersona.allCases) { persona in
                            Text(persona.displayName).tag(persona)
                        }
                    }
                    Picker("Idioma / Variante", selection: $orchestrator.behavior.languageVariant) {
                        ForEach(VoiceLanguageVariant.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    Picker("Personalidade", selection: $orchestrator.behavior.personality) {
                        ForEach(VoicePersonalityStyle.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Picker("Formalidade", selection: $orchestrator.behavior.formality) {
                        ForEach(VoiceFormalityLevel.allCases) { f in
                            Text(f.displayName).tag(f)
                        }
                    }
                    Picker("Expressividade", selection: $orchestrator.behavior.expressivity) {
                        ForEach(VoiceExpressivityLevel.allCases) { e in
                            Text(e.displayName).tag(e)
                        }
                    }
                    Picker("Detalhe", selection: $orchestrator.behavior.detailLevel) {
                        ForEach(VoiceDetailLevel.allCases) { d in
                            Text(d.displayName).tag(d)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Picker("Orb Cromática", selection: $orchestrator.orbPalette) {
                        ForEach(WisdVoiceOrbPalette.allCases) { pal in
                            Text(pal.displayName).tag(pal)
                        }
                    }
                    Picker("Apresentação", selection: $orchestrator.presentationMode) {
                        ForEach(VoicePresentationMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }

                Toggle("Resumir blocos longos de código/tabelas na fala mantendo detalhes completos no chat", isOn: $orchestrator.behavior.autoSummarizeTechnicalReplies)
                    .toggleStyle(.switch)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Chaves Opcionais de Voz Neural (macOS Keychain)")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("Chaves OpenAI e Gemini cadastradas na aba de APIs são reutilizadas quando autorizadas acima. Abaixo você pode salvar chaves opcionais de Deepgram (STT) e ElevenLabs (TTS).")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DesktopStyle.muted)

                HStack(spacing: 8) {
                    SecureField("Deepgram API Key (opcional)", text: $deepgramKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Salvar") {
                        try? VoiceKeychainStore.saveKey(deepgramKeyInput, for: .deepgram)
                        orchestrator.refreshResolvedPipeline()
                        keyFeedback = "Chave Deepgram atualizada no macOS Keychain."
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    SecureField("ElevenLabs API Key (opcional)", text: $elevenLabsKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Salvar") {
                        try? VoiceKeychainStore.saveKey(elevenLabsKeyInput, for: .elevenLabs)
                        orchestrator.refreshResolvedPipeline()
                        keyFeedback = "Chave ElevenLabs atualizada no macOS Keychain."
                    }
                    .buttonStyle(.bordered)
                }

                if let keyFeedback {
                    Text(keyFeedback)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.green)
                }
            }

            Divider()

            permanentDiagnosticsSection
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesktopStyle.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DesktopStyle.line))
        .onAppear {
            orchestrator.modelAssetManager.refreshStorageInfo()
            orchestrator.refreshDependencyInventory()
            orchestrator.telemetry.refreshResources()
        }
    }

    private var permanentDiagnosticsSection: some View {
        let engStats = orchestrator.audioEngine.telemetrySnapshot()
        let res = orchestrator.telemetry.resourceSnapshot
        let sttSnap = orchestrator.componentStatuses[.stt]
        let llmSnap = orchestrator.componentStatuses[.llm]
        let ttsSnap = orchestrator.componentStatuses[.tts]
        let capSnap = orchestrator.componentStatuses[.audioCapture]
        let playSnap = orchestrator.componentStatuses[.audioPlayback]
        let agSnap = orchestrator.componentStatuses[.agentOrchestrator]

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diagnóstico Permanente do Motor de Voz")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Estado: \(orchestrator.state.displayTitle) · Startup: \(String(format: "%.0f ms", orchestrator.lastStartupDurationMs)) · Processos Locais: \(workspace.ready ? "App-Server Ready" : "Modo Local Independente")")
                        .font(.system(size: 11))
                        .foregroundStyle(DesktopStyle.muted)
                }
                Spacer()
                Button("Testar Tudo") {
                    Task {
                        for kind in VoiceComponentKind.allCases {
                            await orchestrator.probeComponent(kind)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Reiniciar Motor") {
                    Task {
                        await orchestrator.restartVoiceEngine()
                        keyFeedback = "Motor de voz reiniciado: \(orchestrator.state.displayTitle)."
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Build: \(WisdVoiceBuildInfo.summary) · Estado Engine: \(engStats.lifecycleState.rawValue) · AudioUnit: \(engStats.audioUnitState)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DesktopStyle.muted)
                Text("Reconhecimento Ativo: \(sttSnap?.activeEngineOrModel ?? orchestrator.resolvedPipeline.activeSTTName) · Cérebro Ativo: \(llmSnap?.activeEngineOrModel ?? orchestrator.brainStatus.rawValue)")
                    .font(.system(size: 11))
                Text("Síntese Vocal Ativa: \(ttsSnap?.activeEngineOrModel ?? orchestrator.resolvedPipeline.activeTTSName) · Vozes PT Instaladas: \(orchestrator.installedPTVoicesCount) · Locales STT: \(orchestrator.installedSpeechLocales.isEmpty ? "verificar via Testar" : orchestrator.installedSpeechLocales.joined(separator: ", "))")
                    .font(.system(size: 11))
                Text("Microfone: \(capSnap?.activeEngineOrModel ?? engStats.inputDeviceName) [\(Int(engStats.inputSampleRateHz))Hz/\(engStats.inputChannels)ch] (RMS \(String(format: "%.3f", orchestrator.audioEngine.liveLevels.micLevel))) · Reprodução: \(playSnap?.activeEngineOrModel ?? engStats.outputDeviceName) [\(Int(engStats.outputSampleRateHz))Hz/\(engStats.outputChannels)ch]")
                    .font(.system(size: 11))
                Text("VPIO=\(engStats.vpioActive ? "ON" : "OFF") · Tap=\(engStats.tapInstalled ? "Instalado" : "Ausente") · Op=\(engStats.lastOperation.rawValue) · Restarts=\(engStats.restartCount) · Recoveries=\(engStats.recoveryCount) · Grafo: \(engStats.nodeGraphSummary)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DesktopStyle.muted)
                Text(String(format: "Recursos: RAM %.1f MB / %.1f GB · CPU %.1f%% (%d núcleos) · GPU %@ (máx %llu MB) · Disco livre %.1f GB",
                            res.residentMemoryMB, res.physicalRAMGB, res.cpuPercent, res.cpuCoreCount, res.gpuName, res.gpuMaxRecommendedMB, orchestrator.modelAssetManager.availableDiskGB))
                    .font(.system(size: 11))
                    .foregroundStyle(DesktopStyle.muted)
                Text("Agentes Externos: \(agSnap?.activeEngineOrModel ?? "Independente") · Último Erro: \(engStats.lastFailure?.formattedSummary ?? orchestrator.lastErrorSummary ?? orchestrator.activeBannerNotice ?? "Nenhum erro registrado")")
                    .font(.system(size: 11))
                    .foregroundStyle((engStats.lastFailure != nil || orchestrator.lastErrorSummary != nil) ? Color.red : DesktopStyle.muted)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesktopStyle.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

            ForEach(VoiceComponentKind.allCases) { kind in
                let snap = orchestrator.componentStatuses[kind] ?? VoiceComponentStatusSnapshot(kind: kind)
                HStack(spacing: 8) {
                    Circle()
                        .fill(diagColor(snap.state))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(kind.displayName)
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("(\(snap.state.rawValue))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(diagColor(snap.state))
                            if let lat = snap.latencyMs {
                                Text(String(format: "· %.0f ms", lat))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(DesktopStyle.muted)
                            }
                        }
                        Text(snap.lastError ?? snap.dependencyHint ?? snap.activeEngineOrModel)
                            .font(.system(size: 10.5))
                            .foregroundStyle(snap.lastError != nil ? Color.red : DesktopStyle.muted)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Testar") {
                        Task { await orchestrator.probeComponent(kind) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.vertical, 3)
            }

            HStack(spacing: 10) {
                Button("Copiar Logs Sanitizados") {
                    let report = orchestrator.exportSanitizedDiagnosticsReport()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    keyFeedback = "Relatório de diagnóstico sanitizado copiado para a área de transferência."
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Exportar Logs (.txt)") {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "wisdai-voice-diagnostics.txt"
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        let report = orchestrator.exportSanitizedDiagnosticsReport()
                        try? report.write(to: url, atomically: true, encoding: .utf8)
                        keyFeedback = "Logs exportados com segurança em \(url.lastPathComponent)."
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
    }

    private func diagColor(_ state: VoiceComponentHealthState) -> Color {
        switch state {
        case .ready: return .green
        case .initializing: return .yellow
        case .degraded: return .orange
        case .unavailable, .error: return .red
        case .idle: return .gray
        }
    }
}
