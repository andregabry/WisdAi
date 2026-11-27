import AppKit
import Foundation
import SwiftUI

// MARK: - Componente da Marca Oficial do WisdAI

public struct BrandLogoView: View {
    public var height: CGFloat

    public init(height: CGFloat = 26) {
        self.height = height
    }

    public var body: some View {
        if let url = Bundle.main.url(forResource: "BrandLogo", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: height * 0.7))
                    .foregroundStyle(Color.blue)
                Text("WisdAI")
                    .font(.system(size: height * 0.75, weight: .bold))
            }
        }
    }
}

// MARK: - Helper de Cores para Projetos e Badges (Conforme Design da Imagem)

public enum DesktopColorHelper {
    public static let availableColors: [String] = [
        "white", "red", "orange", "yellow", "green", "blue", "purple", "pink"
    ]

    public static func color(named name: String) -> Color {
        switch name.lowercased() {
        case "white": return Color(white: 0.95)
        case "red": return Color(red: 0.95, green: 0.35, blue: 0.35)
        case "orange": return Color(red: 0.98, green: 0.52, blue: 0.18)
        case "yellow": return Color(red: 0.98, green: 0.80, blue: 0.20)
        case "green": return Color(red: 0.20, green: 0.78, blue: 0.48)
        case "blue": return Color(red: 0.25, green: 0.60, blue: 0.98)
        case "purple": return Color(red: 0.65, green: 0.42, blue: 0.98)
        case "pink": return Color(red: 0.95, green: 0.45, blue: 0.68)
        default: return Color.primary
        }
    }
}

// MARK: - Modelo de Projeto Rico com Suporte a Múltiplas Pastas de Origem

public struct ProjectItem: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var path: String // Pasta de origem principal
    public var additionalPaths: [String] // Pastas adicionais
    public var icon: String
    public var iconColor: String
    public var nameColor: String
    public var pinned: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        additionalPaths: [String] = [],
        icon: String = "terminal",
        iconColor: String = "red",
        nameColor: String = "primary",
        pinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.additionalPaths = additionalPaths
        self.icon = icon
        self.iconColor = iconColor
        self.nameColor = nameColor
        self.pinned = pinned
    }

    public var allPaths: [String] {
        var paths: [String] = []
        if !path.isEmpty { paths.append(path) }
        for p in additionalPaths where !p.isEmpty && !paths.contains(p) {
            paths.append(p)
        }
        return paths
    }

    public var resolvedIconColor: Color {
        DesktopColorHelper.color(named: iconColor)
    }

    public var resolvedNameColor: Color {
        nameColor == "primary" ? Color.primary : DesktopColorHelper.color(named: nameColor)
    }

    public func matchesPath(_ rawPath: String) -> Bool {
        guard !rawPath.isEmpty else { return false }
        let targetNorm = URL(fileURLWithPath: rawPath).standardized.resolvingSymlinksInPath().path
        for p in allPaths where !p.isEmpty {
            let pNorm = URL(fileURLWithPath: p).standardized.resolvingSymlinksInPath().path
            if pNorm == targetNorm || targetNorm.hasPrefix(pNorm.hasSuffix("/") ? pNorm : pNorm + "/") {
                return true
            }
        }
        return false
    }
}

// MARK: - Provedores de IA Suportados

public enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openai = "openai"
    case claude = "claude"
    case gemini = "gemini"
    case deepseek = "deepseek"
    case nvidia = "nvidia"
    case grok = "grok"
    case kimi = "kimi"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .claude: return "Claude (Anthropic)"
        case .gemini: return "Gemini (Antigravity)"
        case .deepseek: return "DeepSeek"
        case .nvidia: return "NVIDIA NIM"
        case .grok: return "Grok (xAI)"
        case .kimi: return "Kimi Code (Moonshot)"
        }
    }

    public var iconName: String {
        switch self {
        case .openai: return "sparkles"
        case .claude: return "brain.head.profile"
        case .gemini: return "atom"
        case .deepseek: return "magnifyingglass.circle.fill"
        case .nvidia: return "cpu.fill"
        case .grok: return "bolt.shield.fill"
        case .kimi: return "moon.stars.fill"
        }
    }

    public var cliName: String {
        switch self {
        case .openai: return "codex"
        case .claude: return "claude"
        case .gemini: return "agy"
        case .deepseek: return "deepseek"
        case .nvidia: return "nvidia-nim"
        case .grok: return "grok"
        case .kimi: return "kimi"
        }
    }

    public var defaultModels: [String] {
        switch self {
        case .openai: return ["gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]
        case .claude: return ["claude-3-7-sonnet", "claude-3-5-sonnet", "claude-3-5-haiku", "claude-3-opus"]
        case .gemini: return ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash", "gemini-1.5-pro"]
        case .deepseek: return ["deepseek-chat", "deepseek-reasoner"]
        case .nvidia: return ["meta/llama-3.3-70b-instruct", "mistralai/mistral-large-2-instruct"]
        case .grok: return ["grok-3", "grok-2"]
        case .kimi: return ["kimi-k1.5", "moonshot-v1-128k"]
        }
    }

    public static func modelDisplayName(for modelId: String) -> String {
        switch modelId {
        case "gpt-6-astra": return "GPT-6-Astra"
        case "gpt-5.6-sol": return "GPT-5.6-Sol"
        case "gpt-5.6-terra": return "GPT-5.6-Terra"
        case "gpt-5.6-luna": return "GPT-5.6-Luna"
        case "claude-sonnet-4-6": return "Claude Sonnet 4.6"
        case "claude-opus-4-6-thinking": return "Claude Opus 4.6"
        case "claude-3-7-sonnet": return "Claude 3.7 Sonnet"
        case "claude-3-5-sonnet": return "Claude 3.5 Sonnet"
        case "claude-3-5-haiku": return "Claude 3.5 Haiku"
        case "claude-3-opus": return "Claude 3 Opus"
        case "gemini-3.8-flash-high": return "Gemini 3.8 Flash (High)"
        case "gemini-3.8-flash-medium": return "Gemini 3.8 Flash (Medium)"
        case "gemini-3.8-flash-low": return "Gemini 3.8 Flash (Low)"
        case "gemini-2.5-pro": return "Gemini 2.5 Pro"
        case "gemini-2.5-flash": return "Gemini 2.5 Flash"
        case "gemini-2.0-flash": return "Gemini 2.0 Flash"
        case "gemini-1.5-pro": return "Gemini 1.5 Pro"
        case "deepseek-chat": return "DeepSeek-V3"
        case "deepseek-reasoner": return "DeepSeek-R1"
        case "gpt-oss-120b-medium": return "GPT-OSS 120B"
        default: return modelId
        }
    }

    public func ownsModel(_ modelID: String) -> Bool {
        let lower = modelID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty || lower == "auto" { return true }
        switch self {
        case .openai:
            let foreign = ["claude", "gemini", "deepseek", "grok", "kimi", "moonshot", "meta/", "mistral", "gpt-oss"]
            return !foreign.contains(where: { lower.contains($0) })
        case .gemini:
            return lower.contains("gemini")
        case .claude:
            return lower.contains("claude")
        case .deepseek:
            return lower.contains("deepseek")
        case .nvidia:
            return lower.contains("/") || lower.contains("llama") || lower.contains("mistral") || lower.contains("nim")
        case .grok:
            return lower.contains("grok")
        case .kimi:
            return lower.contains("kimi") || lower.contains("moonshot")
        }
    }
}

// MARK: - Modelo de Conta de IA

public struct AIAccount: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var provider: AIProvider
    public var emailOrIdentity: String
    public var apiKeyOrToken: String?
    public var cliInstalled: Bool
    public var cliPath: String?
    public var models: [String]
    public var activeModelIndex: Int
    public var isActive: Bool
    public var sessionID: String?
    public var workspaceID: String?
    public var profileDirectory: String?
    public var modelsUpdatedAt: Date?
    public var catalogSource: String?
    public var exhaustedModelIndices: [Int]

    public init(
        id: UUID = UUID(),
        name: String,
        provider: AIProvider,
        emailOrIdentity: String = "",
        apiKeyOrToken: String? = nil,
        cliInstalled: Bool = true,
        cliPath: String? = nil,
        models: [String] = [],
        activeModelIndex: Int = 0,
        isActive: Bool = false,
        exhaustedModelIndices: [Int] = []
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.emailOrIdentity = emailOrIdentity
        self.apiKeyOrToken = apiKeyOrToken
        self.cliInstalled = cliInstalled
        self.cliPath = cliPath
        self.models = models
        self.activeModelIndex = activeModelIndex
        self.isActive = isActive
        self.exhaustedModelIndices = exhaustedModelIndices
    }

    // Refuse to serialize legacy plaintext keys. DesktopLocalData migrates only
    // keys previously supplied to this app before saving account metadata.
    enum CodingKeys: String, CodingKey {
        case id, name, provider, emailOrIdentity, apiKeyOrToken, cliInstalled, cliPath, models,
             activeModelIndex, isActive, sessionID, workspaceID, profileDirectory, modelsUpdatedAt,
             catalogSource, exhaustedModelIndices
    }
    public func encode(to encoder: Encoder) throws {
        guard apiKeyOrToken == nil else {
            throw EncodingError.invalidValue("legacy credential", .init(codingPath: encoder.codingPath, debugDescription: "Credential must be stored in Keychain first"))
        }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(provider, forKey: .provider)
        try c.encode(emailOrIdentity, forKey: .emailOrIdentity); try c.encode(cliInstalled, forKey: .cliInstalled)
        try c.encodeIfPresent(cliPath, forKey: .cliPath); try c.encode(models, forKey: .models)
        try c.encode(activeModelIndex, forKey: .activeModelIndex); try c.encode(isActive, forKey: .isActive)
        try c.encodeIfPresent(sessionID, forKey: .sessionID); try c.encodeIfPresent(workspaceID, forKey: .workspaceID)
        try c.encodeIfPresent(profileDirectory, forKey: .profileDirectory); try c.encodeIfPresent(modelsUpdatedAt, forKey: .modelsUpdatedAt)
        try c.encodeIfPresent(catalogSource, forKey: .catalogSource); try c.encode(exhaustedModelIndices, forKey: .exhaustedModelIndices)
    }

    public var supportsExecution: Bool {
        if provider == .openai {
            return sessionID != nil
        }
        return cliInstalled || cliPath != nil || modelsUpdatedAt != nil
    }
    public var connectionLabel: String {
        if provider == .openai && sessionID != nil { return "Sessão oficial conectada" }
        if provider == .gemini && (cliInstalled || cliPath != nil) { return "CLI Antigravity conectado" }
        if cliInstalled || cliPath != nil { return "CLI \(provider.displayName) conectado" }
        if modelsUpdatedAt != nil { return "Conta ativa · modelos carregados" }
        return "Configuração pendente"
    }

    public var currentModel: String {
        guard !models.isEmpty else { return "auto" }
        let index = min(max(0, activeModelIndex), models.count - 1)
        return models[index]
    }

    public var hasAvailableModels: Bool {
        let exhaustedSet = Set(exhaustedModelIndices)
        return models.indices.contains { !exhaustedSet.contains($0) }
    }

    public mutating func advanceToNextAvailableModel() -> String? {
        if !exhaustedModelIndices.contains(activeModelIndex) {
            exhaustedModelIndices.append(activeModelIndex)
        }
        let exhaustedSet = Set(exhaustedModelIndices)
        if let next = models.indices.first(where: { !exhaustedSet.contains($0) }) {
            activeModelIndex = next
            return models[next]
        }
        return nil
    }

    public mutating func resetExhaustedModels() {
        exhaustedModelIndices.removeAll()
    }
}

// MARK: - Passos de Atividade em Tempo Real

public struct TaskActivityStep: Identifiable, Equatable {
    public var id = UUID()
    public var title: String
    public var detail: String?
    public var timestamp: Date = Date()
    public var isCompleted: Bool = false
    public var kind: StepKind = .generic

    public enum StepKind: String, Equatable {
        case generic
        case thinking
        case command
        case fileChange
        case tool
        case search
        case response
    }

    public init(title: String, detail: String? = nil, isCompleted: Bool = false, kind: StepKind = .generic) {
        self.title = title
        self.detail = detail
        self.isCompleted = isCompleted
        self.kind = kind
    }
}

// MARK: - Tarefa Ativa em Paralelo (Até 5 Simultâneas)

public struct ActiveThreadTask: Identifiable, Equatable {
    public var id: String { threadId }
    public var threadId: String
    public var turnId: String?
    public var prompt: String
    public var status: String
    public var accountId: UUID?
    public var accountName: String
    public var modelName: String
    public var startedAt: Date
    public var progressNote: String
    public var steps: [TaskActivityStep]

    public init(
        threadId: String,
        turnId: String? = nil,
        prompt: String,
        status: String = "executando",
        accountId: UUID? = nil,
        accountName: String = "Padrão",
        modelName: String = "auto",
        startedAt: Date = Date(),
        progressNote: String = "Executando no motor WisdAI…",
        steps: [TaskActivityStep] = []
    ) {
        self.threadId = threadId
        self.turnId = turnId
        self.prompt = prompt
        self.status = status
        self.accountId = accountId
        self.accountName = accountName
        self.modelName = modelName
        self.startedAt = startedAt
        self.progressNote = progressNote
        self.steps = steps
    }

    public mutating func addStep(_ title: String, detail: String? = nil, kind: TaskActivityStep.StepKind = .generic) {
        if let last = steps.indices.last {
            steps[last].isCompleted = true
        }
        steps.append(TaskActivityStep(title: title, detail: detail, isCompleted: false, kind: kind))
        progressNote = title
    }

    public mutating func completeCurrentStep() {
        if let last = steps.indices.last {
            steps[last].isCompleted = true
        }
    }
}

// MARK: - Níveis de Esforço de Raciocínio

public enum ReasoningEffortLevel: Int, CaseIterable, Identifiable {
    case leve = 0
    case medio = 1
    case alto = 2
    case extraAlto = 3
    case ultra = 4

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .leve: return "Leve"
        case .medio: return "Médio"
        case .alto: return "Alto"
        case .extraAlto: return "Extra alto"
        case .ultra: return "Ultra"
        }
    }

    public var effortValue: String {
        switch self {
        case .leve: return "low"
        case .medio: return "medium"
        case .alto: return "high"
        case .extraAlto: return "xhigh"
        case .ultra: return "ultra"
        }
    }

    public var cliEffortValue: String {
        switch self {
        case .leve: return "low"
        case .medio: return "medium"
        case .alto: return "high"
        case .extraAlto: return "xhigh"
        case .ultra: return "max"
        }
    }

    public static func from(value: String) -> ReasoningEffortLevel {
        switch value.lowercased() {
        case "low", "minimal", "leve": return .leve
        case "medium", "default", "médio", "medio": return .medio
        case "high", "alto": return .alto
        case "xhigh", "extra alto", "extraalto": return .extraAlto
        case "ultra", "max": return .ultra
        default: return .medio
        }
    }
}

// MARK: - Telemetria em Memória e Roteamento Preventivo (Contas e Modelos)

public enum QuotaAvailability: String, Codable, Equatable {
    case available
    case nearLimit
    case exhausted
    case unknown

    public var label: String {
        switch self {
        case .available: return "Disponível"
        case .nearLimit: return "Perto do limite"
        case .exhausted: return "Limite esgotado"
        case .unknown: return "Monitorando"
        }
    }
}

public struct ModelUsageMetrics: Identifiable, Equatable {
    public var id: String { "\(accountID.uuidString)::\(modelID)" }
    public let accountID: UUID
    public let modelID: String
    public var limitID: String?
    public var primaryUsedPercent: Int?
    public var primaryWindowMins: Int?
    public var primaryResetsAt: Date?
    public var secondaryUsedPercent: Int?
    public var secondaryWindowMins: Int?
    public var secondaryResetsAt: Date?
    public var remainingRequests: Int?
    public var limitRequests: Int?
    public var remainingTokens: Int?
    public var limitTokens: Int?
    public var totalTokensConsumed: Int = 0
    public var requestCount: Int = 0
    public var cooldownUntil: Date?
    public var blockReason: String?
    public var lastUpdated: Date = Date()

    public init(accountID: UUID, modelID: String) {
        self.accountID = accountID
        self.modelID = modelID
    }

    public var effectiveUsedPercent: Int? {
        let now = Date()
        if let cooled = cooldownUntil, cooled > now { return 100 }
        let activePrimary = primaryUsedPercent.flatMap { used in
            (used >= 100 && (primaryResetsAt ?? .distantFuture) <= now) ? nil : used
        }
        let activeSecondary = secondaryUsedPercent.flatMap { used in
            (used >= 100 && (secondaryResetsAt ?? .distantFuture) <= now) ? nil : used
        }
        let values = [activePrimary, activeSecondary].compactMap { $0 }
        if !values.isEmpty { return values.max() }
        if let rem = remainingRequests, let lim = limitRequests, lim > 0 {
            return min(100, max(0, Int(round(Double(lim - rem) / Double(lim) * 100.0))))
        }
        if let remT = remainingTokens, let limT = limitTokens, limT > 0 {
            return min(100, max(0, Int(round(Double(limT - remT) / Double(limT) * 100.0))))
        }
        return nil
    }

    public var remainingPercent: Int? {
        effectiveUsedPercent.map { max(0, min(100, 100 - $0)) }
    }

    public var nextResetAt: Date? {
        let now = Date()
        let candidates = [cooldownUntil, primaryResetsAt, secondaryResetsAt]
            .compactMap { $0 }
            .filter { $0 > now }
        return candidates.min()
    }

    public var availability: QuotaAvailability {
        let now = Date()
        if let cooled = cooldownUntil, cooled > now { return .exhausted }
        if let remReq = remainingRequests, remReq <= 0 {
            if let reset = nextResetAt, reset > now { return .exhausted }
            if nextResetAt == nil { return .exhausted }
        }
        if let remTok = remainingTokens, remTok <= 0 {
            if let reset = nextResetAt, reset > now { return .exhausted }
            if nextResetAt == nil { return .exhausted }
        }
        if let used = effectiveUsedPercent {
            if used >= 100 { return .exhausted }
            if used >= 85 { return .nearLimit }
            return .available
        }
        return .unknown
    }
}

public struct AccountUsageSnapshot: Identifiable, Equatable {
    public var id: UUID { accountID }
    public let accountID: UUID
    public var ordinaryUsageAllowed: Bool?
    public var spendControlReached: Bool?
    public var primaryUsedPercent: Int?
    public var primaryWindowMins: Int?
    public var primaryResetsAt: Date?
    public var secondaryUsedPercent: Int?
    public var secondaryWindowMins: Int?
    public var secondaryResetsAt: Date?
    public var individualRemainingPercent: Int?
    public var creditBalance: String?
    public var unlimitedCredits: Bool = false
    public var resetCreditsAvailable: Int?
    public var cooldownUntil: Date?
    public var blockReason: String?
    public var totalTokensConsumed: Int = 0
    public var lastSyncedAt: Date = Date()
    public var syncSource: String = ""

    public init(accountID: UUID) {
        self.accountID = accountID
    }

    public var effectiveUsedPercent: Int? {
        let now = Date()
        if let cooled = cooldownUntil, cooled > now { return 100 }
        let p = primaryUsedPercent.flatMap { ($0 >= 100 && (primaryResetsAt ?? .distantFuture) <= now) ? nil : $0 }
        let s = secondaryUsedPercent.flatMap { ($0 >= 100 && (secondaryResetsAt ?? .distantFuture) <= now) ? nil : $0 }
        var maxUsed = [p, s].compactMap { $0 }.max()
        if let indRem = individualRemainingPercent {
            let indUsed = max(0, min(100, 100 - indRem))
            maxUsed = max(maxUsed ?? 0, indUsed)
        }
        return maxUsed
    }

    public var remainingPercent: Int? {
        effectiveUsedPercent.map { max(0, min(100, 100 - $0)) }
    }

    public var nextResetAt: Date? {
        let now = Date()
        let candidates = [cooldownUntil, primaryResetsAt, secondaryResetsAt]
            .compactMap { $0 }
            .filter { $0 > now }
        return candidates.min()
    }

    public var isExhausted: Bool {
        let now = Date()
        if unlimitedCredits { return false }
        if let cooled = cooldownUntil, cooled > now { return true }
        if ordinaryUsageAllowed == false || spendControlReached == true { return true }
        if let used = effectiveUsedPercent, used >= 100 { return true }
        if let indRem = individualRemainingPercent, indRem <= 0 { return true }
        return false
    }

    public var availability: QuotaAvailability {
        if isExhausted { return .exhausted }
        if let used = effectiveUsedPercent, used >= 85 { return .nearLimit }
        if effectiveUsedPercent != nil || ordinaryUsageAllowed == true || unlimitedCredits { return .available }
        return .unknown
    }
}

@MainActor
public final class UsageQuotaStore: ObservableObject {
    @Published public private(set) var accountSnapshots: [UUID: AccountUsageSnapshot] = [:]
    @Published public private(set) var modelMetrics: [String: ModelUsageMetrics] = [:]
    @Published public private(set) var lastGlobalRefreshAt: Date?
    @Published public var isRefreshing: Bool = false

    public init() {}

    public static func key(accountID: UUID, modelID: String) -> String {
        "\(accountID.uuidString)::\(modelID)"
    }

    public func accountSnapshot(for accountID: UUID) -> AccountUsageSnapshot? {
        accountSnapshots[accountID]
    }

    public func metrics(accountID: UUID, modelID: String) -> ModelUsageMetrics? {
        modelMetrics[Self.key(accountID: accountID, modelID: modelID)]
    }

    public func allMetrics(for accountID: UUID) -> [ModelUsageMetrics] {
        let prefix = accountID.uuidString + "::"
        return modelMetrics
            .filter { $0.key.hasPrefix(prefix) }
            .map(\.value)
            .sorted { $0.modelID < $1.modelID }
    }

    public func availability(accountID: UUID, modelID: String, account: AIAccount? = nil) -> QuotaAvailability {
        if let snap = accountSnapshots[accountID], snap.isExhausted {
            return .exhausted
        }
        if let metric = metrics(accountID: accountID, modelID: modelID) {
            let mAvail = metric.availability
            if mAvail != .unknown { return mAvail }
        }
        if let account,
           let idx = account.models.firstIndex(of: modelID),
           account.exhaustedModelIndices.contains(idx) {
            return .exhausted
        }
        if let snap = accountSnapshots[accountID] {
            return snap.availability
        }
        return .unknown
    }

    public func remainingPercent(accountID: UUID, modelID: String) -> Int? {
        if let rem = metrics(accountID: accountID, modelID: modelID)?.remainingPercent {
            return rem
        }
        return accountSnapshots[accountID]?.remainingPercent
    }

    public func nextResetAt(accountID: UUID, modelID: String? = nil) -> Date? {
        let now = Date()
        var dates: [Date] = []
        if let accReset = accountSnapshots[accountID]?.nextResetAt, accReset > now {
            dates.append(accReset)
        }
        if let modelID, let modReset = metrics(accountID: accountID, modelID: modelID)?.nextResetAt, modReset > now {
            dates.append(modReset)
        }
        return dates.min()
    }

    public func earliestRecoveryDate(across accounts: [AIAccount]) -> Date? {
        let now = Date()
        var candidates: [Date] = []
        for acc in accounts {
            if let accDate = accountSnapshots[acc.id]?.nextResetAt, accDate > now {
                candidates.append(accDate)
            }
            for m in allMetrics(for: acc.id) {
                if let mDate = m.nextResetAt, mDate > now {
                    candidates.append(mDate)
                }
            }
        }
        return candidates.min()
    }

    public func updateFromRateLimits(_ result: [String: Any], account: AIAccount, fallbackModels: [String] = []) {
        let now = Date()
        var snap = accountSnapshots[account.id] ?? AccountUsageSnapshot(accountID: account.id)
        snap.lastSyncedAt = now
        snap.syncSource = "Codex RPC"

        if let allowed = result["ordinaryUsageAllowed"] as? Bool {
            snap.ordinaryUsageAllowed = allowed
        }
        if let resetCredits = (result["rateLimitResetCredits"] as? [String: Any])?["availableCount"] as? Int {
            snap.resetCreditsAvailable = resetCredits
        }

        if let limits = result["rateLimits"] as? [String: Any] {
            applySnapshotFields(limits, into: &snap)
        }
        accountSnapshots[account.id] = snap

        let knownModels = account.models.isEmpty ? fallbackModels : account.models
        if let byId = result["rateLimitsByLimitId"] as? [String: Any] {
            for (limitKey, rawVal) in byId {
                guard let bucket = rawVal as? [String: Any] else { continue }
                let slug = (bucket["normalModelSlug"] as? String) ?? (bucket["limitName"] as? String) ?? limitKey
                let matchingModels = knownModels.filter { modelId in
                    limitKey == "codex" ||
                    modelId.caseInsensitiveCompare(slug) == .orderedSame ||
                    modelId.caseInsensitiveCompare(limitKey) == .orderedSame ||
                    modelId.lowercased().contains(slug.lowercased())
                }
                let targets = matchingModels.isEmpty ? [slug] : matchingModels
                for mId in targets {
                    var metric = metrics(accountID: account.id, modelID: mId) ?? ModelUsageMetrics(accountID: account.id, modelID: mId)
                    metric.limitID = limitKey
                    applyBucketFields(bucket, into: &metric, now: now)
                    modelMetrics[Self.key(accountID: account.id, modelID: mId)] = metric
                }
            }
        } else if let limits = result["rateLimits"] as? [String: Any] {
            for mId in knownModels {
                var metric = metrics(accountID: account.id, modelID: mId) ?? ModelUsageMetrics(accountID: account.id, modelID: mId)
                applyBucketFields(limits, into: &metric, now: now)
                modelMetrics[Self.key(accountID: account.id, modelID: mId)] = metric
            }
        }
        lastGlobalRefreshAt = now
    }

    private func applySnapshotFields(_ limits: [String: Any], into snap: inout AccountUsageSnapshot) {
        if let p = limits["primary"] as? [String: Any] {
            snap.primaryUsedPercent = p["usedPercent"] as? Int
            snap.primaryWindowMins = p["windowDurationMins"] as? Int
            snap.primaryResetsAt = (p["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))
        }
        if let s = limits["secondary"] as? [String: Any] {
            snap.secondaryUsedPercent = s["usedPercent"] as? Int
            snap.secondaryWindowMins = s["windowDurationMins"] as? Int
            snap.secondaryResetsAt = (s["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))
        }
        if let ind = limits["individualLimit"] as? [String: Any], let rem = ind["remainingPercent"] as? Int {
            snap.individualRemainingPercent = rem
        }
        if let spend = limits["spendControlReached"] as? Bool {
            snap.spendControlReached = spend
        }
        if let credits = limits["credits"] as? [String: Any] {
            let unlimited = credits["unlimited"] as? Bool == true
            snap.unlimitedCredits = unlimited
            snap.creditBalance = unlimited ? "Ilimitado" : (credits["balance"] as? String)
        }
        if let pUsed = snap.primaryUsedPercent, pUsed < 100,
           (snap.secondaryUsedPercent ?? 0) < 100,
           snap.ordinaryUsageAllowed != false {
            snap.cooldownUntil = nil
            snap.blockReason = nil
        }
    }

    private func applyBucketFields(_ bucket: [String: Any], into metric: inout ModelUsageMetrics, now: Date) {
        metric.lastUpdated = now
        if let p = bucket["primary"] as? [String: Any] {
            metric.primaryUsedPercent = p["usedPercent"] as? Int
            metric.primaryWindowMins = p["windowDurationMins"] as? Int
            metric.primaryResetsAt = (p["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))
        }
        if let s = bucket["secondary"] as? [String: Any] {
            metric.secondaryUsedPercent = s["usedPercent"] as? Int
            metric.secondaryWindowMins = s["windowDurationMins"] as? Int
            metric.secondaryResetsAt = (s["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))
        }
        if (metric.primaryUsedPercent ?? 0) < 100 && (metric.secondaryUsedPercent ?? 0) < 100 {
            if let cooled = metric.cooldownUntil, cooled <= now {
                metric.cooldownUntil = nil
                metric.blockReason = nil
            }
        }
    }

    public func updateFromHTTPHeaders(
        accountID: UUID,
        models: [String],
        statusCode: Int,
        headers: [AnyHashable: Any],
        source: String
    ) {
        let now = Date()
        var lowerHeaders: [String: String] = [:]
        for (k, v) in headers {
            if let ks = k as? String, let vs = v as? String {
                lowerHeaders[ks.lowercased()] = vs
            }
        }

        let remReq = parseIntHeader(lowerHeaders, keys: ["x-ratelimit-remaining-requests", "anthropic-ratelimit-requests-remaining"])
        let limReq = parseIntHeader(lowerHeaders, keys: ["x-ratelimit-limit-requests", "anthropic-ratelimit-requests-limit"])
        let remTok = parseIntHeader(lowerHeaders, keys: ["x-ratelimit-remaining-tokens", "anthropic-ratelimit-tokens-remaining"])
        let limTok = parseIntHeader(lowerHeaders, keys: ["x-ratelimit-limit-tokens", "anthropic-ratelimit-tokens-limit"])
        let retryAfter = parseDurationHeader(lowerHeaders["retry-after"])
            ?? parseDurationHeader(lowerHeaders["x-ratelimit-reset-requests"])
            ?? parseDurationHeader(lowerHeaders["x-ratelimit-reset-tokens"])

        var snap = accountSnapshots[accountID] ?? AccountUsageSnapshot(accountID: accountID)
        snap.lastSyncedAt = now
        snap.syncSource = source

        if statusCode == 429 || statusCode == 402 {
            let until = now.addingTimeInterval(retryAfter ?? (statusCode == 402 ? 900 : 120))
            snap.cooldownUntil = until
            snap.ordinaryUsageAllowed = false
            snap.blockReason = statusCode == 402 ? "Créditos/cota esgotados (HTTP 402)" : "Limite de taxa atingido (HTTP 429)"
        } else if (200..<300).contains(statusCode) {
            if let remReq, let limReq, limReq > 0 {
                snap.primaryUsedPercent = min(100, max(0, Int(round(Double(limReq - remReq) / Double(limReq) * 100.0))))
                if let resetDur = parseDurationHeader(lowerHeaders["x-ratelimit-reset-requests"]) {
                    snap.primaryResetsAt = now.addingTimeInterval(resetDur)
                }
            }
            if let remTok, let limTok, limTok > 0 {
                snap.secondaryUsedPercent = min(100, max(0, Int(round(Double(limTok - remTok) / Double(limTok) * 100.0))))
                if let resetDur = parseDurationHeader(lowerHeaders["x-ratelimit-reset-tokens"]) {
                    snap.secondaryResetsAt = now.addingTimeInterval(resetDur)
                }
            }
            if (snap.primaryUsedPercent ?? 0) < 100 && (snap.secondaryUsedPercent ?? 0) < 100 {
                snap.ordinaryUsageAllowed = true
                snap.cooldownUntil = nil
                snap.blockReason = nil
            }
        }
        accountSnapshots[accountID] = snap

        for mId in models {
            var metric = metrics(accountID: accountID, modelID: mId) ?? ModelUsageMetrics(accountID: accountID, modelID: mId)
            metric.lastUpdated = now
            metric.remainingRequests = remReq ?? metric.remainingRequests
            metric.limitRequests = limReq ?? metric.limitRequests
            metric.remainingTokens = remTok ?? metric.remainingTokens
            metric.limitTokens = limTok ?? metric.limitTokens
            if statusCode == 429 || statusCode == 402 {
                metric.cooldownUntil = snap.cooldownUntil
                metric.blockReason = snap.blockReason
            } else if (200..<300).contains(statusCode) {
                if let remReq, remReq > 0 { metric.cooldownUntil = nil; metric.blockReason = nil }
                else if remReq == nil && remTok == nil { metric.cooldownUntil = nil; metric.blockReason = nil }
            }
            modelMetrics[Self.key(accountID: accountID, modelID: mId)] = metric
        }
        lastGlobalRefreshAt = now
    }

    public func recordTokenUsage(accountID: UUID, modelID: String, tokens: Int, incrementRequest: Bool = false) {
        let now = Date()
        var metric = metrics(accountID: accountID, modelID: modelID) ?? ModelUsageMetrics(accountID: accountID, modelID: modelID)
        metric.totalTokensConsumed += max(0, tokens)
        if incrementRequest { metric.requestCount += 1 }
        metric.lastUpdated = now
        modelMetrics[Self.key(accountID: accountID, modelID: modelID)] = metric

        var snap = accountSnapshots[accountID] ?? AccountUsageSnapshot(accountID: accountID)
        snap.totalTokensConsumed += max(0, tokens)
        snap.lastSyncedAt = now
        accountSnapshots[accountID] = snap
        lastGlobalRefreshAt = now
    }

    public func markModelLimited(accountID: UUID, modelID: String, until: Date, reason: String) {
        let now = Date()
        var metric = metrics(accountID: accountID, modelID: modelID) ?? ModelUsageMetrics(accountID: accountID, modelID: modelID)
        metric.cooldownUntil = until
        metric.primaryUsedPercent = 100
        metric.primaryResetsAt = until
        metric.blockReason = reason
        metric.lastUpdated = now
        modelMetrics[Self.key(accountID: accountID, modelID: modelID)] = metric
        lastGlobalRefreshAt = now
    }

    public func markAccountLimited(accountID: UUID, models: [String] = [], until: Date, reason: String) {
        let now = Date()
        var snap = accountSnapshots[accountID] ?? AccountUsageSnapshot(accountID: accountID)
        snap.ordinaryUsageAllowed = false
        snap.primaryUsedPercent = 100
        snap.primaryResetsAt = until
        snap.cooldownUntil = until
        snap.blockReason = reason
        snap.lastSyncedAt = now
        accountSnapshots[accountID] = snap

        for mId in models {
            markModelLimited(accountID: accountID, modelID: mId, until: until, reason: reason)
        }
        lastGlobalRefreshAt = now
    }

    public func clearLimits(accountID: UUID, modelID: String? = nil) {
        let now = Date()
        if let modelID {
            let k = Self.key(accountID: accountID, modelID: modelID)
            if var metric = modelMetrics[k] {
                metric.cooldownUntil = nil
                metric.primaryUsedPercent = 0
                metric.primaryResetsAt = nil
                metric.blockReason = nil
                metric.lastUpdated = now
                modelMetrics[k] = metric
            }
        } else {
            if var snap = accountSnapshots[accountID] {
                snap.cooldownUntil = nil
                snap.ordinaryUsageAllowed = true
                snap.spendControlReached = false
                snap.primaryUsedPercent = 0
                snap.primaryResetsAt = nil
                snap.blockReason = nil
                snap.lastSyncedAt = now
                accountSnapshots[accountID] = snap
            }
            for m in allMetrics(for: accountID) {
                var cleared = m
                cleared.cooldownUntil = nil
                cleared.primaryUsedPercent = 0
                cleared.primaryResetsAt = nil
                cleared.blockReason = nil
                cleared.lastUpdated = now
                modelMetrics[Self.key(accountID: accountID, modelID: m.modelID)] = cleared
            }
        }
        lastGlobalRefreshAt = now
    }

    @discardableResult
    public func reconcileExpiredLimits(now: Date = Date(), accounts: inout [AIAccount]) -> Int {
        var recoveredCount = 0
        for accIdx in accounts.indices {
            let accID = accounts[accIdx].id
            if var snap = accountSnapshots[accID] {
                var changed = false
                if let cooled = snap.cooldownUntil, cooled <= now {
                    snap.cooldownUntil = nil
                    snap.blockReason = nil
                    changed = true
                }
                if let pUsed = snap.primaryUsedPercent, pUsed >= 100, let pReset = snap.primaryResetsAt, pReset <= now {
                    snap.primaryUsedPercent = 0
                    snap.primaryResetsAt = nil
                    changed = true
                }
                if let sUsed = snap.secondaryUsedPercent, sUsed >= 100, let sReset = snap.secondaryResetsAt, sReset <= now {
                    snap.secondaryUsedPercent = 0
                    snap.secondaryResetsAt = nil
                    changed = true
                }
                if changed && snap.primaryUsedPercent != 100 && snap.secondaryUsedPercent != 100 {
                    snap.ordinaryUsageAllowed = true
                    snap.spendControlReached = false
                    accountSnapshots[accID] = snap
                    accounts[accIdx].exhaustedModelIndices.removeAll()
                    recoveredCount += 1
                } else if changed {
                    accountSnapshots[accID] = snap
                }
            }

            let prefix = accID.uuidString + "::"
            for (k, metricVal) in modelMetrics where k.hasPrefix(prefix) {
                var metric = metricVal
                var changed = false
                if let cooled = metric.cooldownUntil, cooled <= now {
                    metric.cooldownUntil = nil
                    metric.blockReason = nil
                    changed = true
                }
                if let pUsed = metric.primaryUsedPercent, pUsed >= 100, let pReset = metric.primaryResetsAt, pReset <= now {
                    metric.primaryUsedPercent = 0
                    metric.primaryResetsAt = nil
                    changed = true
                }
                if changed {
                    metric.lastUpdated = now
                    modelMetrics[k] = metric
                    if let mIdx = accounts[accIdx].models.firstIndex(of: metric.modelID) {
                        accounts[accIdx].exhaustedModelIndices.removeAll { $0 == mIdx }
                    }
                    recoveredCount += 1
                }
            }
        }
        return recoveredCount
    }

    public static func isModelCompatible(_ modelID: String, with account: AIAccount) -> Bool {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "auto" { return true }
        guard account.provider.ownsModel(trimmed) else { return false }

        let scopedAccountModels = account.models.filter { account.provider.ownsModel($0) }
        if !scopedAccountModels.isEmpty {
            return scopedAccountModels.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
        }

        if account.provider.defaultModels.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return true
        }

        let lower = trimmed.lowercased()
        switch account.provider {
        case .openai:
            return lower.hasPrefix("gpt") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") || lower.contains("codex")
        case .gemini:
            return lower.contains("gemini")
        case .claude:
            return lower.contains("claude")
        case .deepseek:
            return lower.contains("deepseek")
        case .grok:
            return lower.contains("grok")
        case .kimi:
            return lower.contains("kimi") || lower.contains("moonshot")
        case .nvidia:
            return lower.contains("/") || lower.contains("llama") || lower.contains("mistral") || lower.contains("nim")
        }
    }

    public func selectBestRoute(
        preferredAccount: AIAccount?,
        preferredModel: String,
        allAccounts: [AIAccount],
        canExecuteAccount: ((AIAccount) -> Bool)? = nil,
        isBlocked: ((AIAccount, String) -> Bool)? = nil
    ) -> (account: AIAccount, model: String, switchedReason: String?)? {
        func executable(_ acc: AIAccount) -> Bool {
            canExecuteAccount?(acc) ?? acc.supportsExecution
        }

        func score(account: AIAccount, model: String) -> Int? {
            if !Self.isModelCompatible(model, with: account) { return nil }
            if isBlocked?(account, model) == true { return nil }
            let avail = availability(accountID: account.id, modelID: model, account: account)
            if avail == .exhausted { return nil }
            let rem = remainingPercent(accountID: account.id, modelID: model)
            switch avail {
            case .available:
                return 2000 + (rem ?? 50)
            case .unknown:
                return 1000
            case .nearLimit:
                return 100 + (rem ?? 5)
            case .exhausted:
                return nil
            }
        }

        // 1. Tenta primeiro a rota preferida pelo usuário (garantindo compatibilidade de provedor/modelo)
        if let pref = preferredAccount, executable(pref) {
            let compatiblePreferred = Self.isModelCompatible(preferredModel, with: pref)
            let fallbackPrefModel = Self.isModelCompatible(pref.currentModel, with: pref)
                ? pref.currentModel
                : (pref.models.first ?? pref.provider.defaultModels.first ?? "auto")
            let normalizedModel = (preferredModel.isEmpty || preferredModel == "auto" || !compatiblePreferred)
                ? fallbackPrefModel
                : preferredModel

            if score(account: pref, model: normalizedModel) != nil {
                let reason: String? = (!preferredModel.isEmpty && preferredModel != "auto" && !compatiblePreferred)
                    ? "Modelo \(AIProvider.modelDisplayName(for: preferredModel)) não pertence à conta \(pref.name). Ajustando para \(AIProvider.modelDisplayName(for: normalizedModel))."
                    : nil
                return (pref, normalizedModel, reason)
            }

            // 2. Rota preferida está esgotada em memória: procura outro modelo livre na MESMA conta (se a conta inteira não estiver bloqueada)
            let accExhausted = accountSnapshots[pref.id]?.isExhausted == true
            if !accExhausted {
                let candidateModels = pref.models.isEmpty ? pref.provider.defaultModels : pref.models
                var bestSameAccount: (model: String, score: Int)? = nil
                for m in candidateModels where m != normalizedModel {
                    if let s = score(account: pref, model: m) {
                        if bestSameAccount == nil || s > bestSameAccount!.score {
                            bestSameAccount = (m, s)
                        }
                    }
                }
                if let picked = bestSameAccount {
                    let oldName = AIProvider.modelDisplayName(for: normalizedModel)
                    let newName = AIProvider.modelDisplayName(for: picked.model)
                    let reason = "Modelo \(oldName) já atingiu o limite em \(pref.name) (em memória). Roteando preventivamente para \(newName)."
                    return (pref, picked.model, reason)
                }
            }
        }

        // 3. Conta indisponível ou todos os seus modelos esgotados: escolhe a melhor outra conta executável em memória
        var bestGlobal: (account: AIAccount, model: String, score: Int)? = nil
        for acc in allAccounts where executable(acc) && acc.id != preferredAccount?.id {
            if accountSnapshots[acc.id]?.isExhausted == true { continue }
            let modelsList = acc.models.isEmpty ? acc.provider.defaultModels : acc.models
            var orderedModels: [String] = []
            if !preferredModel.isEmpty && preferredModel != "auto" && Self.isModelCompatible(preferredModel, with: acc) && modelsList.contains(preferredModel) {
                orderedModels.append(preferredModel)
            }
            if !acc.currentModel.isEmpty && acc.currentModel != "auto" && !orderedModels.contains(acc.currentModel) {
                orderedModels.append(acc.currentModel)
            }
            for m in modelsList where !orderedModels.contains(m) {
                orderedModels.append(m)
            }
            for m in orderedModels {
                if let s = score(account: acc, model: m) {
                    let providerBonus = (preferredAccount?.provider == acc.provider) ? 20 : 0
                    let totalScore = s + providerBonus
                    if bestGlobal == nil || totalScore > bestGlobal!.score {
                        bestGlobal = (acc, m, totalScore)
                    }
                    break
                }
            }
        }

        if let best = bestGlobal {
            let fromDesc = preferredAccount.map { "\($0.name)" } ?? "conta atual"
            let newName = AIProvider.modelDisplayName(for: best.model)
            let remText = remainingPercent(accountID: best.account.id, modelID: best.model).map { " (\($0)% livre)" } ?? ""
            let why = (preferredAccount.map { !executable($0) } ?? false)
                ? "\(fromDesc) não possui CLI/sessão ativa disponível"
                : "Limite de \(fromDesc) esgotado em memória"
            let reason = "\(why). Roteando automaticamente para \(best.account.name) · \(newName)\(remText)."
            return (best.account, best.model, reason)
        }

        return nil
    }

    public static func parseRetryDelaySeconds(from text: String) -> TimeInterval? {
        let lower = text.lowercased()
        let patterns: [(String, Double)] = [
            (#"(\d+(?:\.\d+)?)\s*(?:h|hora|horas|hour|hours)"#, 3600),
            (#"(\d+(?:\.\d+)?)\s*(?:m|min|mins|minuto|minutos|minute|minutes)"#, 60),
            (#"(\d+(?:\.\d+)?)\s*(?:s|sec|secs|seg|segundos|second|seconds)"#, 1)
        ]
        for (regex, multiplier) in patterns {
            if let range = lower.range(of: regex, options: .regularExpression) {
                let slice = String(lower[range])
                let digits = slice.prefix { $0.isNumber || $0 == "." }
                if let val = Double(digits), val > 0 {
                    return min(86_400, max(5, val * multiplier))
                }
            }
        }
        return nil
    }

    private func parseIntHeader(_ headers: [String: String], keys: [String]) -> Int? {
        for k in keys {
            if let val = headers[k], let parsed = Int(val.trimmingCharacters(in: .whitespaces)) {
                return parsed
            }
        }
        return nil
    }

    private func parseDurationHeader(_ raw: String?) -> TimeInterval? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let secs = Double(raw), secs > 0 { return secs }
        return Self.parseRetryDelaySeconds(from: raw)
    }
}

// MARK: - Sistema de Design Unificado (Modais e Dropdowns/Popovers WisdAI)

public enum WisdTheme {
    public static let accent = Color(red: 0.48, green: 0.29, blue: 0.82)
    public static let iconAccent = Color(red: 0.64, green: 0.46, blue: 0.98)
    public static let softAccentText = Color(red: 0.74, green: 0.60, blue: 0.99)
    public static let success = Color(red: 0.20, green: 0.82, blue: 0.48)
    public static let warning = Color(red: 0.96, green: 0.68, blue: 0.24)
    public static let danger = Color(red: 0.92, green: 0.34, blue: 0.34)

    public static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.135, green: 0.138, blue: 0.148)
            : Color(red: 0.96, green: 0.96, blue: 0.975)
    }

    public static func modalSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.118, green: 0.121, blue: 0.132)
            : Color(red: 0.975, green: 0.975, blue: 0.985)
    }

    public static func elevated(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.055)
            : Color.black.opacity(0.04)
    }

    public static func border(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.085)
            : Color.black.opacity(0.09)
    }

    public static func divider(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.075)
            : Color.black.opacity(0.075)
    }

    public static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.94) : Color.black.opacity(0.88)
    }

    public static func muted(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.56) : Color.black.opacity(0.56)
    }
}

public struct WisdPopoverShell<HeaderTrailing: View, Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let subtitle: String?
    let statusColor: Color?
    let width: CGFloat
    let cornerRadius: CGFloat
    let headerTrailing: HeaderTrailing
    let content: Content

    public init(
        title: String,
        subtitle: String? = nil,
        statusColor: Color? = nil,
        width: CGFloat = 340,
        cornerRadius: CGFloat = 18,
        @ViewBuilder headerTrailing: () -> HeaderTrailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusColor = statusColor
        self.width = width
        self.cornerRadius = cornerRadius
        self.headerTrailing = headerTrailing()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(WisdTheme.ink(scheme))
                    if let subtitle, !subtitle.isEmpty {
                        HStack(spacing: 5) {
                            if let statusColor {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 6, height: 6)
                            }
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(WisdTheme.muted(scheme))
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 8)
                headerTrailing
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Rectangle()
                .fill(WisdTheme.divider(scheme))
                .frame(height: 1)

            content
        }
        .frame(width: width)
        .background(
            ZStack {
                WisdTheme.surface(scheme).opacity(0.95)
                Rectangle().fill(.ultraThinMaterial).opacity(scheme == .dark ? 0.35 : 0.65)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(WisdTheme.border(scheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.42 : 0.16), radius: 20, x: 0, y: 10)
    }
}

public struct WisdPopoverSection<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String?
    let content: Content

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(WisdTheme.muted(scheme))
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
            }
            content
        }
        .padding(.bottom, 8)
    }
}

public struct WisdHeaderPillButton: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String?
    let title: String?
    let helpText: String?
    let isDisabled: Bool
    let action: () -> Void
    @State private var hovered = false

    public init(
        icon: String? = nil,
        title: String? = nil,
        help: String? = nil,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.helpText = help
        self.isDisabled = disabled
        self.action = action
    }

    public var body: some View {
        let base = Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                if let title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                }
            }
            .foregroundStyle(WisdTheme.softAccentText)
            .padding(.horizontal, title == nil ? 8 : 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WisdTheme.accent.opacity(hovered ? 0.24 : 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(WisdTheme.accent.opacity(hovered ? 0.45 : 0.26), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { hovered = $0 }

        if let helpText {
            base.help(helpText)
        } else {
            base
        }
    }
}

public struct WisdSelectableRow<Trailing: View>: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String?
    let iconColor: Color?
    let title: String
    let subtitle: String?
    let selected: Bool
    let badge: String?
    let badgeColor: Color
    let disabled: Bool
    let trailing: Trailing
    let action: () -> Void
    @State private var hovered = false

    public init(
        icon: String? = nil,
        iconColor: Color? = nil,
        title: String,
        subtitle: String? = nil,
        selected: Bool = false,
        badge: String? = nil,
        badgeColor: Color = WisdTheme.danger,
        disabled: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        self.badge = badge
        self.badgeColor = badgeColor
        self.disabled = disabled
        self.trailing = trailing()
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(iconColor ?? WisdTheme.iconAccent)
                        .frame(width: 20, alignment: .center)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WisdTheme.ink(scheme))
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(WisdTheme.muted(scheme))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(badgeColor == WisdTheme.danger ? Color(red: 0.96, green: 0.45, blue: 0.45) : badgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badgeColor.opacity(0.16), in: Capsule())
                        .overlay(Capsule().stroke(badgeColor.opacity(0.28), lineWidth: 1))
                }

                trailing

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(WisdTheme.iconAccent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        selected
                            ? WisdTheme.elevated(scheme)
                            : (hovered ? WisdTheme.elevated(scheme).opacity(0.85) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? WisdTheme.border(scheme) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.48 : 1)
        .onHover { hovered = $0 }
    }
}

public struct WisdModalShell<HeaderTrailing: View, Footer: View, Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let subtitle: String?
    let statusColor: Color?
    let width: CGFloat
    let maxHeight: CGFloat?
    let onClose: (() -> Void)?
    let headerTrailing: HeaderTrailing
    let footer: Footer
    let content: Content

    public init(
        title: String,
        subtitle: String? = nil,
        statusColor: Color? = nil,
        width: CGFloat = 520,
        maxHeight: CGFloat? = nil,
        onClose: (() -> Void)? = nil,
        @ViewBuilder headerTrailing: () -> HeaderTrailing = { EmptyView() },
        @ViewBuilder footer: () -> Footer = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.statusColor = statusColor
        self.width = width
        self.maxHeight = maxHeight
        self.onClose = onClose
        self.headerTrailing = headerTrailing()
        self.footer = footer()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WisdTheme.ink(scheme))
                    if let subtitle, !subtitle.isEmpty {
                        HStack(spacing: 6) {
                            if let statusColor {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 6, height: 6)
                            }
                            Text(subtitle)
                                .font(.system(size: 11.5))
                                .foregroundStyle(WisdTheme.muted(scheme))
                        }
                    }
                }
                Spacer(minLength: 10)
                headerTrailing
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WisdTheme.muted(scheme))
                            .frame(width: 26, height: 26)
                            .background(WisdTheme.elevated(scheme), in: Circle())
                            .overlay(Circle().stroke(WisdTheme.border(scheme), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Rectangle()
                .fill(WisdTheme.divider(scheme))
                .frame(height: 1)

            if let maxHeight {
                ScrollView {
                    content
                        .padding(20)
                }
                .frame(maxHeight: maxHeight)
            } else {
                content
                    .padding(20)
            }

            if Footer.self != EmptyView.self {
                Rectangle()
                    .fill(WisdTheme.divider(scheme))
                    .frame(height: 1)
                footer
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
            }
        }
        .frame(width: width)
        .background(
            ZStack {
                WisdTheme.modalSurface(scheme).opacity(0.97)
                Rectangle().fill(.ultraThinMaterial).opacity(scheme == .dark ? 0.30 : 0.65)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(WisdTheme.border(scheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.50 : 0.20), radius: 28, x: 0, y: 14)
    }
}

public struct WisdPrimaryButton: View {
    let title: String
    let icon: String?
    let disabled: Bool
    let action: () -> Void
    @State private var hovered = false

    public init(_ title: String, icon: String? = nil, disabled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.disabled = disabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(WisdTheme.accent.opacity(hovered ? 0.92 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(WisdTheme.iconAccent.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onHover { hovered = $0 }
    }
}

public struct WisdSecondaryButton: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let icon: String?
    let action: () -> Void
    @State private var hovered = false

    public init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(WisdTheme.ink(scheme).opacity(0.86))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovered ? WisdTheme.elevated(scheme).opacity(1.3) : WisdTheme.elevated(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(WisdTheme.border(scheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

public struct WisdDropdownTrigger: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String?
    let iconColor: Color?
    let title: String
    let subtitle: String?
    let isPresented: Bool
    let action: () -> Void
    @State private var hovered = false

    public init(
        icon: String? = nil,
        iconColor: Color? = nil,
        title: String,
        subtitle: String? = nil,
        isPresented: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.isPresented = isPresented
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(iconColor ?? WisdTheme.iconAccent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WisdTheme.ink(scheme))
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(WisdTheme.muted(scheme))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(WisdTheme.muted(scheme))
                    .rotationEffect(.degrees(isPresented ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovered || isPresented ? WisdTheme.elevated(scheme).opacity(1.2) : WisdTheme.elevated(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isPresented ? WisdTheme.accent.opacity(0.65) : WisdTheme.border(scheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

public extension View {
    func wisdFieldSurface(focused: Bool = false, cornerRadius: CGFloat = 10) -> some View {
        modifier(WisdFieldSurfaceModifier(focused: focused, cornerRadius: cornerRadius))
    }
}

private struct WisdFieldSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let focused: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(WisdTheme.elevated(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(focused ? WisdTheme.accent.opacity(0.65) : WisdTheme.border(scheme), lineWidth: 1)
            )
    }
}

// MARK: - Divisor Redimensionável (Estilo Antigravity)

private struct SplitResizeCursorOverlay: NSViewRepresentable {
    final class CursorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func resetCursorRects() {
            discardCursorRects()
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            window?.invalidateCursorRects(for: self)
        }
    }

    func makeNSView(context: Context) -> CursorView {
        let view = CursorView()
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: CursorView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

public struct WisdSplitHandle: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double
    let defaultWidth: Double
    let invertDelta: Bool

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var dragStartWidth: Double? = nil

    public init(
        width: Binding<Double>,
        minWidth: Double,
        maxWidth: Double,
        defaultWidth: Double,
        invertDelta: Bool = false
    ) {
        self._width = width
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.defaultWidth = defaultWidth
        self.invertDelta = invertDelta
    }

    public var body: some View {
        let active = isHovering || isDragging
        let safeMax = max(minWidth, maxWidth)

        ZStack {
            Color.clear
            Rectangle()
                .fill(active ? WisdTheme.iconAccent.opacity(0.9) : WisdTheme.divider(scheme))
                .frame(width: active ? 2 : 1)
                .animation(.easeOut(duration: 0.12), value: active)
        }
        .frame(width: 6)
        .frame(maxHeight: .infinity)
        .background(SplitResizeCursorOverlay())
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.18)) {
                width = min(safeMax, max(minWidth, defaultWidth))
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = min(safeMax, max(minWidth, width))
                        isDragging = true
                    }
                    let base = dragStartWidth ?? width
                    let delta = invertDelta ? -Double(value.translation.width) : Double(value.translation.width)
                    width = min(safeMax, max(minWidth, base + delta))
                }
                .onEnded { _ in
                    dragStartWidth = nil
                    isDragging = false
                }
        )
    }
}
