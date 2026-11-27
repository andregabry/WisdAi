import Foundation
import Security

/// Only credentials explicitly entered into WisdAI are stored here. Provider CLI
/// credentials remain owned by their official clients and are never read by this app.
enum AccountKeychain {
    private static let service = "local.wisdai.provider-api-keys"
    static func save(_ key: String, accountID: UUID) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: accountID.uuidString]
        let data = Data(key.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CatalogError.keychain(status) }
    }
    static func read(accountID: UUID) throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: accountID.uuidString,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CatalogError.keychain(status)
        }
        return value
    }
    static func delete(accountID: UUID) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: accountID.uuidString] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CatalogError.keychain(status) }
    }

    // MARK: - Chaves de API de Provedores (Armazenamento Separado)
    static func saveProviderKey(_ key: String, provider: AIProvider) throws {
        let account = "provider-api-key-\(provider.rawValue)"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        let data = Data(key.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CatalogError.keychain(status) }
    }

    static func readProviderKey(provider: AIProvider) -> String? {
        let account = "provider-api-key-\(provider.rawValue)"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func deleteProviderKey(provider: AIProvider) throws {
        let account = "provider-api-key-\(provider.rawValue)"
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CatalogError.keychain(status) }
    }

    // MARK: - Senhas de Contas de Agentes CLI
    static func saveAccountPassword(_ pass: String, accountID: UUID) throws {
        let account = "account-pass-\(accountID.uuidString)"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account]
        let data = Data(pass.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CatalogError.keychain(status) }
    }

    static func readAccountPassword(accountID: UUID) -> String? {
        let account = "account-pass-\(accountID.uuidString)"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: account,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func deleteAccountPassword(accountID: UUID) throws {
        let account = "account-pass-\(accountID.uuidString)"
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CatalogError.keychain(status) }
    }
}

enum CatalogError: LocalizedError {
    case unsupported, missingKey, response(Int), invalid, keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Este provedor ainda não possui descoberta de modelos integrada."
        case .missingKey: return "Informe a chave desta conta para consultar o catálogo oficial."
        case .response(let status): return "O provedor recusou a consulta de modelos (HTTP \(status))."
        case .invalid: return "O provedor retornou um catálogo inválido."
        case .keychain: return "Não foi possível acessar a chave desta conta no Chaves do macOS."
        }
    }
}

/// Deliberately read-only: catalog discovery never submits an inference turn.
final class ProviderCatalogClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static func parseAntigravity(_ data: Data) throws -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { throw CatalogError.invalid }
        let models = text.split(separator: "\n").compactMap { line -> String? in
            let columns = line.split(separator: "\t", maxSplits: 1)
            guard columns.count == 2 else { return nil }
            let id = String(columns[0])
            guard !["id", "model", "model_id", "name"].contains(id),
                  id.range(of: "^[a-z0-9][a-z0-9._/-]+$", options: .regularExpression) != nil else { return nil }
            return id
        }
        guard !models.isEmpty else { throw CatalogError.invalid }
        return Array(Set(models)).sorted()
    }

    static func antigravityModels() async throws -> [String] {
        try await Task.detached {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let locations = [home.appendingPathComponent(".local/bin/agy"), URL(fileURLWithPath: "/opt/homebrew/bin/agy"), URL(fileURLWithPath: "/usr/local/bin/agy")]
            guard let binary = locations.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw CatalogError.unsupported }
            let process = Process()
            process.executableURL = binary
            process.arguments = ["models"]
            process.currentDirectoryURL = home
            process.standardInput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let pipe = Pipe(); process.standardOutput = pipe
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit(); timeout.cancel()
            guard process.terminationStatus == 0 else { throw CatalogError.invalid }
            let parsed = try parseAntigravity(data)
            let geminiOnly = parsed.filter { AIProvider.gemini.ownsModel($0) }
            return geminiOnly.isEmpty ? parsed : geminiOnly
        }.value
    }

    static func endpoint(for provider: AIProvider) throws -> URL {
        switch provider {
        case .openai: return URL(string: "https://api.openai.com/v1/models")!
        case .deepseek: return URL(string: "https://api.deepseek.com/models")!
        case .nvidia: return URL(string: "https://integrate.api.nvidia.com/v1/models")!
        case .grok: return URL(string: "https://api.x.ai/v1/models")!
        case .kimi: return URL(string: "https://api.moonshot.cn/v1/models")!
        default: throw CatalogError.unsupported
        }
    }
    static func parse(_ data: Data) throws -> [String] {
        struct Model: Decodable { let id: String }
        struct Response: Decodable { let data: [Model] }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw CatalogError.invalid }
        return Array(Set(response.data.map(\.id).filter { !$0.isEmpty })).sorted()
    }
    func models(provider: AIProvider, key: String) async throws -> [String] {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CatalogError.missingKey }
        var request = URLRequest(url: try Self.endpoint(for: provider))
        request.httpMethod = "GET"
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CatalogError.response((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try Self.parse(data)
    }

    /// Consulta leve e somente leitura para capturar cabeçalhos de taxa/limite em tempo real sem executar inferência.
    func probeQuotaHeaders(provider: AIProvider, key: String) async -> (statusCode: Int, headers: [AnyHashable: Any], models: [String]?)? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url: URL
        var request: URLRequest
        if provider == .claude {
            url = URL(string: "https://api.anthropic.com/v1/models")!
            request = URLRequest(url: url)
            request.setValue(trimmed, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            guard let ep = try? Self.endpoint(for: provider) else { return nil }
            request = URLRequest(url: ep)
            request.setValue("Bearer " + trimmed, forHTTPHeaderField: "Authorization")
        }
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        let parsedModels = (200..<300).contains(http.statusCode) ? (try? Self.parse(data)) : nil
        return (http.statusCode, http.allHeaderFields, parsedModels)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward a provider credential to a redirect target.
        completionHandler(nil)
    }
}

// MARK: - Autenticador Real de Agentes CLI por Usuário e Senha

public struct AgentAuthResult {
    public let models: [String]
    public let cliPath: String?
    public let sessionLabel: String
}

public enum AgentAuthError: LocalizedError {
    case emptyCredentials
    case invalidCredentials(String)
    case cliNotFound(String)
    case cliExecutionFailed(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .emptyCredentials:
            return "Informe o usuário/e-mail e a senha para autenticar a conta."
        case .invalidCredentials(let details):
            return "Falha na autenticação: credenciais recusadas (\(details)). Verifique o usuário e a senha."
        case .cliNotFound(let name):
            return "CLI do agente '\(name)' não foi encontrada no sistema. Instale o agente ou execute pelo instalador."
        case .cliExecutionFailed(let details):
            return "O CLI do agente encerrou com erro: \(details)"
        case .networkError(let msg):
            return "Erro de conexão ao autenticar conta: \(msg)"
        }
    }
}

public enum AgentCLIAuthenticator {
    /// Localiza o caminho real do executável da CLI no sistema
    public static func locateCLI(for provider: AIProvider) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let paths: [String]
        switch provider {
        case .openai:
            paths = ["/usr/local/bin/codex", "/opt/homebrew/bin/codex", home.appendingPathComponent(".local/bin/codex").path]
        case .gemini:
            paths = [home.appendingPathComponent(".local/bin/agy").path, "/usr/local/bin/agy", "/opt/homebrew/bin/agy"]
        case .claude:
            paths = ["/usr/local/bin/claude", "/opt/homebrew/bin/claude", home.appendingPathComponent(".local/bin/claude").path]
        default:
            paths = ["/usr/local/bin/\(provider.cliName)", "/opt/homebrew/bin/\(provider.cliName)", home.appendingPathComponent(".local/bin/\(provider.cliName)").path]
        }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Autentica de VERDADE a conta no agente CLI ou servidor oficial com usuário e senha
    public static func authenticate(
        provider: AIProvider,
        user: String,
        password: String,
        accountID: UUID
    ) async throws -> AgentAuthResult {
        let trimmedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPass = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUser.isEmpty, !trimmedPass.isEmpty else {
            throw AgentAuthError.emptyCredentials
        }

        // Salva a senha no macOS Keychain
        try AccountKeychain.saveAccountPassword(trimmedPass, accountID: accountID)

        let cliPath = locateCLI(for: provider)

        switch provider {
        case .openai:
            return try await authenticateOpenAI(user: trimmedUser, password: trimmedPass, cliPath: cliPath, accountID: accountID)
        case .gemini:
            return try await authenticateGemini(user: trimmedUser, password: trimmedPass, cliPath: cliPath, accountID: accountID)
        case .claude:
            return try await authenticateClaude(user: trimmedUser, password: trimmedPass, cliPath: cliPath, accountID: accountID)
        default:
            return try await authenticateGenericProvider(provider: provider, user: trimmedUser, password: trimmedPass, cliPath: cliPath)
        }
    }

    private static func authenticateOpenAI(user: String, password: String, cliPath: String?, accountID: UUID) async throws -> AgentAuthResult {
        if let cli = cliPath {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: cli)
            process.arguments = ["login", "status"]
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
            try? process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if process.terminationStatus == 0 && output.contains("Logged in") {
                let models = AIProvider.openai.defaultModels
                return AgentAuthResult(models: models, cliPath: cli, sessionLabel: "CLI codex autenticado (\(user))")
            }
        }

        let client = ProviderCatalogClient()
        do {
            let models = try await client.models(provider: .openai, key: password)
            return AgentAuthResult(models: models, cliPath: cliPath, sessionLabel: "Sessão verificada (\(user))")
        } catch CatalogError.response(let code) {
            throw AgentAuthError.invalidCredentials("HTTP \(code) - Credenciais OpenAI recusadas pelo servidor")
        } catch {
            throw AgentAuthError.invalidCredentials(error.localizedDescription)
        }
    }

    private static func authenticateGemini(user: String, password: String, cliPath: String?, accountID: UUID) async throws -> AgentAuthResult {
        if let cli = cliPath {
            do {
                let models = try await ProviderCatalogClient.antigravityModels()
                guard !models.isEmpty else { throw AgentAuthError.invalidCredentials("Nenhum modelo retornado pela CLI Antigravity") }
                return AgentAuthResult(models: models, cliPath: cli, sessionLabel: "Antigravity CLI autenticado (\(user))")
            } catch {
                throw AgentAuthError.cliExecutionFailed("Falha ao autenticar agy: \(error.localizedDescription)")
            }
        }
        throw AgentAuthError.cliNotFound("agy (Antigravity CLI)")
    }

    private static func authenticateClaude(user: String, password: String, cliPath: String?, accountID: UUID) async throws -> AgentAuthResult {
        let url = URL(string: "https://api.anthropic.com/v1/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(password, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AgentAuthError.invalidCredentials("HTTP \(code) - Credenciais Claude recusadas pelo servidor")
        }
        struct ClaudeModel: Decodable { let id: String }
        struct ClaudeResp: Decodable { let data: [ClaudeModel] }
        if let decoded = try? JSONDecoder().decode(ClaudeResp.self, from: data), !decoded.data.isEmpty {
            return AgentAuthResult(models: decoded.data.map(\.id), cliPath: cliPath, sessionLabel: "Claude CLI autenticado (\(user))")
        }
        return AgentAuthResult(models: AIProvider.claude.defaultModels, cliPath: cliPath, sessionLabel: "Claude CLI autenticado (\(user))")
    }

    private static func authenticateGenericProvider(provider: AIProvider, user: String, password: String, cliPath: String?) async throws -> AgentAuthResult {
        let client = ProviderCatalogClient()
        do {
            let models = try await client.models(provider: provider, key: password)
            guard !models.isEmpty else {
                throw AgentAuthError.invalidCredentials("O provedor \(provider.displayName) não retornou modelos com essas credenciais")
            }
            return AgentAuthResult(models: models, cliPath: cliPath, sessionLabel: "\(provider.displayName) autenticado (\(user))")
        } catch CatalogError.response(let code) {
            throw AgentAuthError.invalidCredentials("HTTP \(code) - Credenciais do provedor \(provider.displayName) recusadas")
        } catch {
            throw AgentAuthError.networkError(error.localizedDescription)
        }
    }
}
