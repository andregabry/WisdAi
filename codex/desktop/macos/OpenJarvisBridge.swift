import AppKit
import Darwin
import Foundation
import Security

// MARK: - OpenJarvis Native Contracts, Lifecycle States & UDS Transport

public enum OpenJarvisToolName: String, CaseIterable, Codable, Sendable {
    case listProjects = "list_projects"
    case getActiveProject = "get_active_project"
    case getProjectContext = "get_project_context"
    case listAvailableAgents = "list_available_agents"
    case executeAgentTask = "execute_agent_task"
    case getTaskStatus = "get_task_status"
    case getTaskEvents = "get_task_events"
    case sendTaskInstruction = "send_task_instruction"
    case cancelTask = "cancel_task"
    case getTaskResult = "get_task_result"
    case listRunningTasks = "list_running_tasks"
    case requestTaskApproval = "request_task_approval"
}

public enum OpenJarvisLifecycleState: Equatable, Sendable {
    case stopped
    case bootstrappingRuntime
    case startingLLM
    case startingDaemon
    case ready
    case recovering(attempt: Int)
    case failed(String)

    public var displayTitle: String {
        switch self {
        case .stopped: return "Parado"
        case .bootstrappingRuntime: return "Preparando runtime OpenJarvis…"
        case .startingLLM: return "Carregando cérebro local Metal…"
        case .startingDaemon: return "Iniciando OpenJarvis…"
        case .ready: return "OpenJarvis conectado"
        case .recovering(let attempt): return "Recuperando OpenJarvis (#\(attempt))…"
        case .failed(let msg): return "Falha no OpenJarvis: \(msg)"
        }
    }

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

public struct OpenJarvisHealthSnapshot: Codable, Equatable, Sendable {
    public let status: String
    public let runtime: String
    public let model: String
    public let llmKind: String
    public let llmHost: String
    public let llmHealthy: Bool
    public let toolsCount: Int
    public let tools: [String]
    public let memoryFactsCount: Int
    public let ttsCleanHealthy: Bool
    public let ttsVoices: [String]
    public let sttBackend: String
    public let sttLoaded: Bool
    public let rssMB: Double
    public let pid: Int

    enum CodingKeys: String, CodingKey {
        case status, runtime, model, tools
        case llmKind = "llm_kind"
        case llmHost = "llm_host"
        case llmHealthy = "llm_healthy"
        case toolsCount = "tools_count"
        case memoryFactsCount = "memory_facts_count"
        case ttsCleanHealthy = "tts_clean_healthy"
        case ttsVoices = "tts_voices"
        case sttBackend = "stt_backend"
        case sttLoaded = "stt_loaded"
        case rssMB = "rss_mb"
        case pid
    }
}

public enum OpenJarvisVoiceStreamEvent: Sendable {
    case started(turnID: String, language: String)
    case toolStart(tool: String, arguments: [String: String])
    case toolResult(tool: String, success: Bool, outputPreview: String)
    case tokenDelta(String)
    case sentence(index: Int, text: String)
    case done(turnID: String, fullText: String, language: String, latencyMS: Double)
    case cancelled(turnID: String, reason: String)
    case error(String)
}

public final class OpenJarvisStreamCancellationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var fileDescriptor: Int32 = -1
    private var cancelledFlag = false

    public init() {}

    func attach(fd: Int32) {
        lock.withLock {
            self.fileDescriptor = fd
            if cancelledFlag && fd >= 0 {
                Darwin.shutdown(fd, SHUT_RDWR)
                Darwin.close(fd)
                self.fileDescriptor = -1
            }
        }
    }

    func detach() {
        lock.withLock {
            self.fileDescriptor = -1
        }
    }

    public var isCancelled: Bool {
        lock.withLock { cancelledFlag }
    }

    public func cancel() {
        lock.withLock {
            cancelledFlag = true
            if fileDescriptor >= 0 {
                Darwin.shutdown(fileDescriptor, SHUT_RDWR)
                Darwin.close(fileDescriptor)
                fileDescriptor = -1
            }
        }
    }
}

// MARK: - Low-Level POSIX AF_UNIX HTTP/1.1 + SSE Client (Zero Exposed TCP Ports)

public enum OpenJarvisUDSError: LocalizedError {
    case invalidSocketPath(String)
    case socketConnectFailed(String)
    case invalidHTTPResponse(String)
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .invalidSocketPath(let p): return "Caminho UDS inválido: \(p)"
        case .socketConnectFailed(let msg): return "Falha ao conectar ao socket OpenJarvis: \(msg)"
        case .invalidHTTPResponse(let msg): return "Resposta HTTP inválida do OpenJarvis: \(msg)"
        case .httpStatus(let code, let body): return "OpenJarvis HTTP \(code): \(body)"
        }
    }
}

private func makeUnixSocketAddress(path: String) throws -> (sockaddr_un, socklen_t) {
    let pathUTF8 = Array(path.utf8)
    var addr = sockaddr_un()
    let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
    guard !pathUTF8.isEmpty, pathUTF8.count < maxLen else {
        throw OpenJarvisUDSError.invalidSocketPath(path)
    }
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &addr.sun_path) { rawPtr in
        rawPtr.initializeMemory(as: UInt8.self, repeating: 0)
        for (idx, byte) in pathUTF8.enumerated() {
            rawPtr[idx] = byte
        }
    }
    let addrLen = UInt8(MemoryLayout<sockaddr_un>.offset(of: \.sun_path)! + pathUTF8.count + 1)
    addr.sun_len = addrLen
    return (addr, socklen_t(addrLen))
}

public enum OpenJarvisUDSHTTPClient {
    private static func openConnectedUnixSocket(path: String, timeoutSeconds: TimeInterval) throws -> Int32 {
        var (addr, addrLen) = try makeUnixSocketAddress(path: path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw OpenJarvisUDSError.socketConnectFailed(String(cString: strerror(errno)))
        }

        // Prevent SIGPIPE when server drops or client aborts mid-stream
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var tv = timeval(
            tv_sec: Int(max(1, Int(timeoutSeconds))),
            tv_usec: Int32((timeoutSeconds - floor(timeoutSeconds)) * 1_000_000)
        )
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let connectRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, addrLen)
            }
        }
        guard connectRes == 0 else {
            let err = String(cString: strerror(errno))
            Darwin.close(fd)
            throw OpenJarvisUDSError.socketConnectFailed(err)
        }
        return fd
    }

    private static func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            var sentTotal = 0
            while sentTotal < data.count {
                let n = Darwin.send(fd, base.advanced(by: sentTotal), data.count - sentTotal, 0)
                if n <= 0 {
                    throw OpenJarvisUDSError.socketConnectFailed(String(cString: strerror(errno)))
                }
                sentTotal += n
            }
        }
    }

    private static func buildHTTPRequest(
        method: String,
        path: String,
        token: String,
        body: Data?,
        contentType: String = "application/json"
    ) -> Data {
        var headers = "\(method) \(path) HTTP/1.1\r\n"
        headers += "Host: openjarvis.local\r\n"
        headers += "Connection: close\r\n"
        if !token.isEmpty {
            headers += "Authorization: Bearer \(token)\r\n"
        }
        if let body {
            headers += "Content-Type: \(contentType)\r\n"
            headers += "Content-Length: \(body.count)\r\n"
        }
        headers += "\r\n"
        var out = Data(headers.utf8)
        if let body {
            out.append(body)
        }
        return out
    }

    private static func parseHTTPHeaderBlock(_ headerData: Data) throws -> (status: Int, headers: [String: String]) {
        guard let str = String(data: headerData, encoding: .utf8) else {
            throw OpenJarvisUDSError.invalidHTTPResponse("Cabeçalho não UTF-8")
        }
        let lines = str.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else {
            throw OpenJarvisUDSError.invalidHTTPResponse("Linha de status ausente")
        }
        let parts = statusLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, let code = Int(parts[1]) else {
            throw OpenJarvisUDSError.invalidHTTPResponse(statusLine)
        }
        var map: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            if let colon = line.firstIndex(of: ":") {
                let k = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                let v = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                map[k] = v
            }
        }
        return (code, map)
    }

    private static func decodeChunkedBody(_ raw: Data) -> Data {
        var decoded = Data()
        var idx = raw.startIndex
        let crlf = Data("\r\n".utf8)
        while idx < raw.endIndex {
            guard let lineEnd = raw.range(of: crlf, options: [], in: idx..<raw.endIndex) else {
                break
            }
            let sizeLine = String(data: raw[idx..<lineEnd.lowerBound], encoding: .ascii)?
                .split(separator: ";").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let chunkSize = Int(sizeLine, radix: 16) else { break }
            idx = lineEnd.upperBound
            if chunkSize == 0 { break }
            let endChunk = min(raw.endIndex, raw.index(idx, offsetBy: chunkSize, limitedBy: raw.endIndex) ?? raw.endIndex)
            decoded.append(raw[idx..<endChunk])
            idx = endChunk
            if raw[idx...].starts(with: crlf) {
                idx = raw.index(idx, offsetBy: 2)
            }
        }
        return decoded
    }

    public static func request(
        udsPath: String,
        method: String,
        path: String,
        token: String,
        body: Data? = nil,
        timeoutSeconds: TimeInterval = 30.0
    ) async throws -> (status: Int, headers: [String: String], body: Data) {
        try await Task.detached(priority: .userInitiated) {
            let fd = try openConnectedUnixSocket(path: udsPath, timeoutSeconds: timeoutSeconds)
            defer { Darwin.close(fd) }

            let payload = buildHTTPRequest(method: method, path: path, token: token, body: body)
            try writeAll(fd: fd, data: payload)

            var all = Data()
            var buf = [UInt8](repeating: 0, count: 16_384)
            while true {
                let n = Darwin.recv(fd, &buf, buf.count, 0)
                if n > 0 {
                    all.append(buf, count: n)
                } else {
                    break
                }
            }

            let sep = Data("\r\n\r\n".utf8)
            guard let split = all.range(of: sep) else {
                throw OpenJarvisUDSError.invalidHTTPResponse("Separador HTTP ausente")
            }
            let (status, headers) = try parseHTTPHeaderBlock(all[..<split.lowerBound])
            let rawBody = Data(all[split.upperBound...])
            let finalBody = (headers["transfer-encoding"]?.lowercased().contains("chunked") == true)
                ? decodeChunkedBody(rawBody)
                : rawBody
            if status >= 400 {
                let txt = String(data: finalBody, encoding: .utf8) ?? ""
                throw OpenJarvisUDSError.httpStatus(status, txt)
            }
            return (status, headers, finalBody)
        }.value
    }

    public static func streamSSE(
        udsPath: String,
        path: String,
        token: String,
        body: Data,
        cancellation: OpenJarvisStreamCancellationHandle,
        timeoutSeconds: TimeInterval = 180.0,
        onEvent: @escaping @Sendable (String, Data) -> Void
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            let fd = try openConnectedUnixSocket(path: udsPath, timeoutSeconds: timeoutSeconds)
            cancellation.attach(fd: fd)
            defer {
                cancellation.detach()
                Darwin.close(fd)
            }

            let req = buildHTTPRequest(method: "POST", path: path, token: token, body: body)
            try writeAll(fd: fd, data: req)

            var headerParsed = false
            var isChunked = false
            var headerAcc = Data()
            var chunkAcc = Data()
            var sseTextAcc = ""
            let headerSep = Data("\r\n\r\n".utf8)
            let crlf = Data("\r\n".utf8)
            var buf = [UInt8](repeating: 0, count: 8192)

            func consumeSSEBytes(_ data: Data) {
                guard let piece = String(data: data, encoding: .utf8), !piece.isEmpty else { return }
                sseTextAcc += piece.replacingOccurrences(of: "\r\n", with: "\n")
                while let frameRange = sseTextAcc.range(of: "\n\n") {
                    let frame = String(sseTextAcc[..<frameRange.lowerBound])
                    sseTextAcc = String(sseTextAcc[frameRange.upperBound...])
                    var eventName = "message"
                    var dataLines: [String] = []
                    for line in frame.components(separatedBy: "\n") {
                        if line.hasPrefix("event:") {
                            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                    }
                    let joined = dataLines.joined(separator: "\n")
                    if !joined.isEmpty, let payload = joined.data(using: .utf8) {
                        onEvent(eventName, payload)
                    }
                }
            }

            func consumeBodyBytes(_ incoming: Data) {
                if !isChunked {
                    consumeSSEBytes(incoming)
                    return
                }
                chunkAcc.append(incoming)
                while !chunkAcc.isEmpty {
                    guard let lineEnd = chunkAcc.range(of: crlf) else { break }
                    let sizeStr = String(data: chunkAcc[chunkAcc.startIndex..<lineEnd.lowerBound], encoding: .ascii)?
                        .split(separator: ";").first?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard let sz = Int(sizeStr, radix: 16) else { break }
                    let bodyStart = lineEnd.upperBound
                    if sz == 0 {
                        chunkAcc.removeAll(keepingCapacity: false)
                        return
                    }
                    let bodyEnd = bodyStart + sz
                    guard chunkAcc.endIndex >= bodyEnd + 2 else { break }
                    let piece = Data(chunkAcc[bodyStart..<bodyEnd])
                    consumeSSEBytes(piece)
                    chunkAcc = Data(chunkAcc[(bodyEnd + 2)...])
                }
            }

            while !cancellation.isCancelled {
                let n = Darwin.recv(fd, &buf, buf.count, 0)
                if n <= 0 { break }
                let chunk = Data(buf[0..<n])
                if !headerParsed {
                    headerAcc.append(chunk)
                    if let sepRange = headerAcc.range(of: headerSep) {
                        let (status, headers) = try parseHTTPHeaderBlock(Data(headerAcc[..<sepRange.lowerBound]))
                        if status >= 400 {
                            let errBody = Data(headerAcc[sepRange.upperBound...])
                            let msg = String(data: errBody, encoding: .utf8) ?? ""
                            throw OpenJarvisUDSError.httpStatus(status, msg)
                        }
                        isChunked = headers["transfer-encoding"]?.lowercased().contains("chunked") == true
                        headerParsed = true
                        let remainder = Data(headerAcc[sepRange.upperBound...])
                        headerAcc.removeAll(keepingCapacity: false)
                        if !remainder.isEmpty {
                            consumeBodyBytes(remainder)
                        }
                    }
                } else {
                    consumeBodyBytes(chunk)
                }
            }
        }.value
    }
}

// MARK: - Authenticated POSIX AF_UNIX Host Callback Server (12 Tools -> Workspace)

public final class OpenJarvisHostCallbackServer: @unchecked Sendable {
    public typealias ToolHandler = @Sendable (_ toolName: String, _ params: [String: Any]) async -> [String: Any]

    private let socketPath: String
    private let bearerToken: String
    private let handler: ToolHandler
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var running = false
    private let acceptQueue = DispatchQueue(label: "com.wisdai.openjarvis.host-uds-accept", qos: .userInitiated)
    private let workerQueue = DispatchQueue(label: "com.wisdai.openjarvis.host-uds-worker", qos: .userInitiated, attributes: .concurrent)

    public init(socketPath: String, bearerToken: String, handler: @escaping ToolHandler) {
        self.socketPath = socketPath
        self.bearerToken = bearerToken
        self.handler = handler
    }

    public func start() throws {
        stop()
        let dir = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        unlink(socketPath)

        var (addr, addrLen) = try makeUnixSocketAddress(path: socketPath)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw OpenJarvisUDSError.socketConnectFailed(String(cString: strerror(errno)))
        }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, addrLen)
            }
        }
        guard bindRes == 0, Darwin.listen(fd, 32) == 0 else {
            let err = String(cString: strerror(errno))
            Darwin.close(fd)
            throw OpenJarvisUDSError.socketConnectFailed("bind/listen host UDS: \(err)")
        }
        chmod(socketPath, S_IRUSR | S_IWUSR)

        lock.withLock {
            self.listenFD = fd
            self.running = true
        }

        acceptQueue.async { [weak self] in
            self?.acceptLoop(listenFD: fd)
        }
    }

    public func stop() {
        let fdToClose: Int32 = lock.withLock {
            running = false
            let old = listenFD
            listenFD = -1
            return old
        }
        if fdToClose >= 0 {
            Darwin.shutdown(fdToClose, SHUT_RDWR)
            Darwin.close(fdToClose)
        }
        unlink(socketPath)
    }

    private func acceptLoop(listenFD: Int32) {
        while lock.withLock({ running }) {
            let clientFD = Darwin.accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                break
            }
            workerQueue.async { [weak self] in
                self?.handleClient(clientFD: clientFD)
            }
        }
    }

    private func handleClient(clientFD: Int32) {
        defer { Darwin.close(clientFD) }
        var noSigPipe: Int32 = 1
        setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var raw = Data()
        var buf = [UInt8](repeating: 0, count: 8192)
        let sep = Data("\r\n\r\n".utf8)
        var headerEnd: Range<Data.Index>?
        var contentLength = 0

        while true {
            let n = Darwin.recv(clientFD, &buf, buf.count, 0)
            if n <= 0 { break }
            raw.append(buf, count: n)
            if headerEnd == nil, let found = raw.range(of: sep) {
                headerEnd = found
                if let hdr = String(data: raw[..<found.lowerBound], encoding: .utf8) {
                    for line in hdr.components(separatedBy: "\r\n") {
                        let lower = line.lowercased()
                        if lower.hasPrefix("content-length:"),
                           let v = Int(lower.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) {
                            contentLength = v
                        }
                    }
                }
            }
            if let found = headerEnd {
                let bodyCount = raw.count - found.upperBound
                if bodyCount >= contentLength { break }
            }
        }

        guard let found = headerEnd,
              let hdrStr = String(data: raw[..<found.lowerBound], encoding: .utf8) else {
            writeJSONResponse(fd: clientFD, status: 400, payload: ["ok": false, "error": "Malformed HTTP request"])
            return
        }

        let lines = hdrStr.components(separatedBy: "\r\n")
        var authHeader = ""
        for line in lines.dropFirst() {
            if line.lowercased().hasPrefix("authorization:") {
                authHeader = String(line.dropFirst("authorization:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        guard bearerToken.isEmpty || authHeader == "Bearer \(bearerToken)" else {
            writeJSONResponse(fd: clientFD, status: 401, payload: ["ok": false, "error": "Unauthorized host callback"])
            return
        }

        let bodySlice = raw[found.upperBound..<min(raw.endIndex, found.upperBound + contentLength)]
        guard let reqObj = (try? JSONSerialization.jsonObject(with: Data(bodySlice))) as? [String: Any],
              let toolName = reqObj["tool"] as? String else {
            writeJSONResponse(fd: clientFD, status: 400, payload: ["ok": false, "error": "Missing tool payload"])
            return
        }
        let params = (reqObj["params"] as? [String: Any]) ?? [:]

        let sem = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var result: [String: Any] = ["ok": false, "error": "No result"] }
        let box = Box()
        let handler = self.handler
        Task {
            box.result = await handler(toolName, params)
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 25.0)
        writeJSONResponse(fd: clientFD, status: 200, payload: box.result)
    }

    private func writeJSONResponse(fd: Int32, status: Int, payload: [String: Any]) {
        let jsonData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{\"ok\":false}".utf8)
        let statusText = status == 200 ? "OK" : (status == 401 ? "Unauthorized" : "Bad Request")
        var head = "HTTP/1.1 \(status) \(statusText)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(jsonData.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(jsonData)
        out.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            var sent = 0
            while sent < out.count {
                let n = Darwin.send(fd, base.advanced(by: sent), out.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }
}

// MARK: - Managed OpenJarvis Runtime Process Manager

@MainActor
public final class OpenJarvisProcessManager: ObservableObject {
    @Published public private(set) var lifecycleState: OpenJarvisLifecycleState = .stopped
    @Published public private(set) var lastHealth: OpenJarvisHealthSnapshot?
    @Published public private(set) var lastError: String?
    @Published public private(set) var restartCount: Int = 0
    @Published public private(set) var runtimeRootPath: String

    private var daemonProcess: Process?
    private var daemonPID: pid_t = 0
    private var isShuttingDown = false
    private var maxAutoRestarts = 3
    private var hostServer: OpenJarvisHostCallbackServer?
    private var toolHandler: OpenJarvisHostCallbackServer.ToolHandler?
    private var activeCancellation: OpenJarvisStreamCancellationHandle?
    private var activeTurnID: String?

    private let baseDir: URL
    private let runDir: URL
    private let logsDir: URL
    private let memoryDir: URL
    public let daemonSocketPath: String
    public let hostSocketPath: String
    private let apiToken: String
    private let hostToken: String
    private weak var localLlamaRuntime: LocalLlamaServerBrainRuntime?
    private var terminationObserver: Any?
    private var bootTask: Task<OpenJarvisHealthSnapshot, Error>?

    public init(localLlamaRuntime: LocalLlamaServerBrainRuntime? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let ojDir = appSupport.appendingPathComponent("WisdAI/OpenJarvis", isDirectory: true)
        self.baseDir = ojDir
        self.runDir = ojDir.appendingPathComponent("run", isDirectory: true)
        self.logsDir = ojDir.appendingPathComponent("logs", isDirectory: true)
        self.memoryDir = ojDir.appendingPathComponent("memory", isDirectory: true)
        let pidTag = ProcessInfo.processInfo.processIdentifier
        self.daemonSocketPath = runDir.appendingPathComponent("oj-\(pidTag).sock").path
        self.hostSocketPath = runDir.appendingPathComponent("host-\(pidTag).sock").path
        self.apiToken = Self.randomTokenHex(bytes: 24)
        self.hostToken = Self.randomTokenHex(bytes: 24)
        self.localLlamaRuntime = localLlamaRuntime
        self.runtimeRootPath = ojDir.path

        self.terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.shutdown()
            }
        }
    }

    deinit {
        if let obs = terminationObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if daemonPID > 0 {
            kill(daemonPID, SIGTERM)
        }
        try? FileManager.default.removeItem(atPath: daemonSocketPath)
        try? FileManager.default.removeItem(atPath: hostSocketPath)
    }

    public func attachLocalLlamaRuntime(_ runtime: LocalLlamaServerBrainRuntime) {
        self.localLlamaRuntime = runtime
    }

    public func setHostToolHandler(_ handler: @escaping OpenJarvisHostCallbackServer.ToolHandler) {
        self.toolHandler = handler
    }

    private static func randomTokenHex(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    private func ensurePrivateDirectories() throws {
        let fm = FileManager.default
        for dir in [baseDir, runDir, logsDir, memoryDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
    }

    public static func resolveOpenJarvisSourceDirectory() -> URL? {
        let envPath = ProcessInfo.processInfo.environment["WISDAI_OPENJARVIS_SOURCE_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates: [URL?] = [
            envPath.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) },
            Bundle.main.resourceURL?.appendingPathComponent("OpenJarvisRuntime", isDirectory: true),
            URL(fileURLWithPath: "/Applications/WisdAI.app/Contents/Resources/OpenJarvisRuntime", isDirectory: true),
            URL(fileURLWithPath: "/Users/andregabry/Project/WisdAI/codex/desktop/macos/OpenJarvisRuntime", isDirectory: true),
        ]
        for case let cand? in candidates {
            if FileManager.default.fileExists(atPath: cand.appendingPathComponent("wisdai_bridge/server.py").path) {
                return cand
            }
        }
        return nil
    }

    private func resolveOrProvisionPythonExecutable() async throws -> URL {
        if let envPy = ProcessInfo.processInfo.environment["WISDAI_OPENJARVIS_PYTHON"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envPy.isEmpty,
           FileManager.default.isExecutableFile(atPath: envPy) {
            return URL(fileURLWithPath: envPy)
        }

        let managedPy = baseDir.appendingPathComponent("venv/bin/python")
        if FileManager.default.isExecutableFile(atPath: managedPy.path),
           await Self.verifyPythonCanImportOpenJarvis(pythonURL: managedPy, sourceDir: Self.resolveOpenJarvisSourceDirectory()) {
            return managedPy
        }

        guard let sourceDir = Self.resolveOpenJarvisSourceDirectory() else {
            throw OpenJarvisUDSError.socketConnectFailed("Diretório OpenJarvisRuntime não encontrado no bundle do aplicativo.")
        }

        lifecycleState = .bootstrappingRuntime
        let home = FileManager.default.homeDirectoryForCurrentUser
        let uvCandidates = [
            baseDir.appendingPathComponent("bin/uv").path,
            Bundle.main.resourceURL?.appendingPathComponent("OpenJarvisRuntime/bin/uv").path ?? "",
            home.appendingPathComponent(".local/bin/uv").path,
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
        ]
        guard let uvPath = uvCandidates.first(where: { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw OpenJarvisUDSError.socketConnectFailed("Runtime Python/uv do OpenJarvis ausente. Reinstale os recursos gerenciados em Application Support.")
        }

        let venvDir = baseDir.appendingPathComponent("venv", isDirectory: true)
        let reqFile = sourceDir.appendingPathComponent("requirements-clean.txt")
        let setupOK = await Task.detached(priority: .userInitiated) {
            let p1 = Process()
            p1.executableURL = URL(fileURLWithPath: uvPath)
            p1.arguments = ["venv", "--clear", "--python", "3.12", venvDir.path]
            p1.standardOutput = FileHandle.nullDevice
            p1.standardError = FileHandle.nullDevice
            try? p1.run()
            p1.waitUntilExit()
            guard p1.terminationStatus == 0 else { return false }

            let pyBin = venvDir.appendingPathComponent("bin/python").path
            let p2 = Process()
            p2.executableURL = URL(fileURLWithPath: uvPath)
            p2.arguments = ["pip", "install", "--python", pyBin, "-r", reqFile.path]
            p2.standardOutput = FileHandle.nullDevice
            p2.standardError = FileHandle.nullDevice
            try? p2.run()
            p2.waitUntilExit()
            guard p2.terminationStatus == 0 else { return false }

            // Register sourceDir in venv via a .pth file inside venv instead of `pip install -e`,
            // avoiding writes (*.egg-info / __pycache__) into the signed .app bundle.
            let libDir = venvDir.appendingPathComponent("lib", isDirectory: true)
            let pySubdirs = (try? FileManager.default.contentsOfDirectory(at: libDir, includingPropertiesForKeys: nil)) ?? []
            let pyLibDir = pySubdirs.first(where: { $0.lastPathComponent.hasPrefix("python") })
                ?? libDir.appendingPathComponent("python3.12", isDirectory: true)
            let sitePackages = pyLibDir.appendingPathComponent("site-packages", isDirectory: true)
            try? FileManager.default.createDirectory(at: sitePackages, withIntermediateDirectories: true)
            let pthURL = sitePackages.appendingPathComponent("wisdai_openjarvis_runtime.pth")
            let pthContent = "\(sourceDir.appendingPathComponent("src").path)\n\(sourceDir.path)\n"
            do {
                try pthContent.write(to: pthURL, atomically: true, encoding: .utf8)
                return true
            } catch {
                return false
            }
        }.value

        guard setupOK && FileManager.default.isExecutableFile(atPath: managedPy.path) else {
            throw OpenJarvisUDSError.socketConnectFailed("Falha ao provisionar ambiente OpenJarvis gerenciado.")
        }
        return managedPy
    }

    private static func verifyPythonCanImportOpenJarvis(pythonURL: URL, sourceDir: URL?) async -> Bool {
        await Task.detached(priority: .utility) {
            let p = Process()
            p.executableURL = pythonURL
            p.arguments = ["-B", "-c", "import fastapi, uvicorn, httpx, openjarvis, wisdai_bridge.server"]
            var env = ProcessInfo.processInfo.environment
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            if let sourceDir {
                env["PYTHONPATH"] = "\(sourceDir.appendingPathComponent("src").path):\(sourceDir.path)"
            }
            p.environment = env
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            do {
                try p.run()
                p.waitUntilExit()
                return p.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }

    public func ensureRunning(
        llmHostOverride: String? = nil,
        llmKindOverride: String? = nil,
        modelOverride: String? = nil,
        llmAPIKeyOverride: String? = nil
    ) async throws -> OpenJarvisHealthSnapshot {
        if let proc = daemonProcess, proc.isRunning, FileManager.default.fileExists(atPath: daemonSocketPath) {
            if let health = try? await probeHealth() {
                self.lastHealth = health
                self.lifecycleState = .ready
                return health
            }
        }
        if let existingBoot = bootTask {
            return try await existingBoot.value
        }

        let task = Task<OpenJarvisHealthSnapshot, Error> { @MainActor in
            defer { self.bootTask = nil }
            return try await self.performEnsureRunning(
                llmHostOverride: llmHostOverride,
                llmKindOverride: llmKindOverride,
                modelOverride: modelOverride,
                llmAPIKeyOverride: llmAPIKeyOverride
            )
        }
        self.bootTask = task
        return try await task.value
    }

    private func performEnsureRunning(
        llmHostOverride: String?,
        llmKindOverride: String?,
        modelOverride: String?,
        llmAPIKeyOverride: String?
    ) async throws -> OpenJarvisHealthSnapshot {
        if let proc = daemonProcess, proc.isRunning, FileManager.default.fileExists(atPath: daemonSocketPath) {
            if let health = try? await probeHealth() {
                self.lastHealth = health
                self.lifecycleState = .ready
                return health
            }
        }

        isShuttingDown = false
        lastError = nil
        try ensurePrivateDirectories()

        // 1. Bind authenticated WisdAI host tool callback UDS first
        if hostServer == nil, let toolHandler {
            let srv = OpenJarvisHostCallbackServer(
                socketPath: hostSocketPath,
                bearerToken: hostToken,
                handler: toolHandler
            )
            try srv.start()
            self.hostServer = srv
        }

        // 2. Ensure Python + OpenJarvis runtime ready
        let pythonURL = try await resolveOrProvisionPythonExecutable()
        guard let sourceDir = Self.resolveOpenJarvisSourceDirectory() else {
            throw OpenJarvisUDSError.socketConnectFailed("Código-fonte OpenJarvisRuntime indisponível.")
        }

        // 3. Resolve underlying LLM engine (local llama-server Metal or configured endpoint)
        var resolvedHost = (llmHostOverride ?? ProcessInfo.processInfo.environment["WISDAI_OPENJARVIS_LLM_HOST"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedKind = (llmKindOverride ?? ProcessInfo.processInfo.environment["WISDAI_OPENJARVIS_LLM_KIND"] ?? "llamacpp").trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedModel = (modelOverride ?? "Qwen3-1.7B-Q4_K_M.gguf").trimmingCharacters(in: .whitespacesAndNewlines)

        if resolvedHost.isEmpty {
            lifecycleState = .startingLLM
            guard let llama = localLlamaRuntime else {
                throw OpenJarvisUDSError.socketConnectFailed("Runtime local llama.cpp Metal não anexado.")
            }
            let port = try await llama.ensureServerReady(modelID: nil)
            resolvedHost = "http://127.0.0.1:\(port)"
            resolvedKind = "llamacpp"
            resolvedModel = llama.loadedModelID ?? "Qwen3-1.7B-Q4_K_M.gguf"
        }

        // 4. Launch OpenJarvis daemon over private Unix Domain Socket
        lifecycleState = .startingDaemon
        unlink(daemonSocketPath)

        let logURL = logsDir.appendingPathComponent("daemon.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let logHandle = try FileHandle(forWritingTo: logURL)
        _ = try? logHandle.seekToEnd()

        let proc = Process()
        proc.executableURL = pythonURL
        proc.currentDirectoryURL = sourceDir
        proc.arguments = [
            "-B", "-m", "wisdai_bridge.server",
            "--uds", daemonSocketPath,
            "--llm-kind", resolvedKind,
            "--llm-host", resolvedHost,
            "--model", resolvedModel,
            "--api-token", apiToken,
            "--host-uds", hostSocketPath,
            "--host-token", hostToken,
            "--memory-path", memoryDir.appendingPathComponent("facts.jsonl").path,
            "--prompts-dir", sourceDir.appendingPathComponent("prompts").path,
        ]
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = "\(sourceDir.appendingPathComponent("src").path):\(sourceDir.path)"
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        if let llmAPIKeyOverride, !llmAPIKeyOverride.isEmpty {
            env["OPENAI_COMPAT_API_KEY"] = llmAPIKeyOverride
        }
        proc.environment = env
        proc.standardOutput = logHandle
        proc.standardError = logHandle

        proc.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, !self.isShuttingDown else { return }
                let code = finished.terminationStatus
                self.daemonProcess = nil
                self.daemonPID = 0
                if self.restartCount < self.maxAutoRestarts {
                    self.restartCount += 1
                    self.lifecycleState = .recovering(attempt: self.restartCount)
                    try? await Task.sleep(nanoseconds: UInt64(300_000_000 * self.restartCount))
                    _ = try? await self.ensureRunning(
                        llmHostOverride: llmHostOverride,
                        llmKindOverride: llmKindOverride,
                        modelOverride: modelOverride,
                        llmAPIKeyOverride: llmAPIKeyOverride
                    )
                } else {
                    let msg = "Daemon OpenJarvis encerrou inesperadamente (código \(code)). Veja \(logURL.lastPathComponent)."
                    self.lastError = msg
                    self.lifecycleState = .failed(msg)
                }
            }
        }

        try proc.run()
        self.daemonProcess = proc
        self.daemonPID = proc.processIdentifier

        for _ in 0..<80 {
            if !proc.isRunning {
                let tail = (try? String(contentsOf: logURL, encoding: .utf8))?.suffix(400) ?? ""
                let msg = "OpenJarvis abortou durante boot: \(tail)"
                lastError = msg
                lifecycleState = .failed(msg)
                throw OpenJarvisUDSError.socketConnectFailed(msg)
            }
            if FileManager.default.fileExists(atPath: daemonSocketPath),
               let snap = try? await probeHealth() {
                self.lastHealth = snap
                self.lifecycleState = .ready
                self.restartCount = 0
                return snap
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        let timeoutMsg = "Timeout aguardando /v1/wisdai/health no socket OpenJarvis."
        lastError = timeoutMsg
        lifecycleState = .failed(timeoutMsg)
        throw OpenJarvisUDSError.socketConnectFailed(timeoutMsg)
    }

    public func probeHealth() async throws -> OpenJarvisHealthSnapshot {
        let (_, _, data) = try await OpenJarvisUDSHTTPClient.request(
            udsPath: daemonSocketPath,
            method: "GET",
            path: "/v1/wisdai/health",
            token: apiToken,
            timeoutSeconds: 4.0
        )
        return try JSONDecoder().decode(OpenJarvisHealthSnapshot.self, from: data)
    }

    public func pushWorkspaceSnapshot(_ snapshot: [String: Any]) async {
        guard lifecycleState.isReady else { return }
        guard let body = try? JSONSerialization.data(withJSONObject: snapshot) else { return }
        _ = try? await OpenJarvisUDSHTTPClient.request(
            udsPath: daemonSocketPath,
            method: "POST",
            path: "/v1/wisdai/context",
            token: apiToken,
            body: body,
            timeoutSeconds: 4.0
        )
    }

    public func warmupSTT() async -> Bool {
        guard lifecycleState.isReady else { return false }
        let body = Data("{\"warmup_stt\":true,\"warmup_tts\":false}".utf8)
        let res = try? await OpenJarvisUDSHTTPClient.request(
            udsPath: daemonSocketPath,
            method: "POST",
            path: "/v1/wisdai/warmup",
            token: apiToken,
            body: body,
            timeoutSeconds: 25.0
        )
        return res != nil
    }

    public func fetchMemoryFacts() async throws -> [[String: Any]] {
        _ = try await ensureRunning()
        let (_, _, respData) = try await OpenJarvisUDSHTTPClient.request(
            udsPath: daemonSocketPath,
            method: "GET",
            path: "/v1/wisdai/memory/facts",
            token: apiToken,
            body: nil,
            timeoutSeconds: 10.0
        )
        let obj = (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any]
        return (obj?["facts"] as? [[String: Any]]) ?? []
    }

    public func transcribeWAV(audioData: Data, language: String?, hotwords: [String]) async throws -> String {
        _ = try await ensureRunning()
        let payload: [String: Any] = [
            "audio_base64": audioData.base64EncodedString(),
            "language": language as Any,
            "hotwords": hotwords,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (_, _, respData) = try await OpenJarvisUDSHTTPClient.request(
            udsPath: daemonSocketPath,
            method: "POST",
            path: "/v1/wisdai/transcribe",
            token: apiToken,
            body: body,
            timeoutSeconds: 45.0
        )
        let obj = (try? JSONSerialization.jsonObject(with: respData)) as? [String: Any]
        return (obj?["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func synthesizeCleanWAV(text: String, voiceID: String, speed: Double, language: String) async throws -> Data {
        _ = try await ensureRunning()
        let payload: [String: Any] = [
            "text": text,
            "voice_id": voiceID,
            "speed": speed,
            "language": language,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (_, _, respData) = try await OpenJarvisUDSHTTPClient.request(
            udsPath: daemonSocketPath,
            method: "POST",
            path: "/v1/wisdai/synthesize",
            token: apiToken,
            body: body,
            timeoutSeconds: 30.0
        )
        return respData
    }

    public func streamVoiceTurn(
        userText: String,
        history: [[String: String]],
        personaID: String,
        preferredLanguage: String,
        workspaceSnapshot: [String: Any],
        model: String? = nil,
        onEvent: @escaping @Sendable (OpenJarvisVoiceStreamEvent) -> Void
    ) async throws {
        _ = try await ensureRunning()
        let turnID = "turn-\(UUID().uuidString.prefix(8).lowercased())"
        let handle = OpenJarvisStreamCancellationHandle()
        self.activeCancellation = handle
        self.activeTurnID = turnID
        defer {
            if self.activeTurnID == turnID {
                self.activeCancellation = nil
                self.activeTurnID = nil
            }
        }

        var payload: [String: Any] = [
            "turn_id": turnID,
            "user_text": userText,
            "history": history,
            "persona_id": personaID,
            "preferred_language": preferredLanguage,
            "workspace_snapshot": workspaceSnapshot,
        ]
        if let model, !model.isEmpty {
            payload["model"] = model
        }
        let body = try JSONSerialization.data(withJSONObject: payload)

        try await OpenJarvisUDSHTTPClient.streamSSE(
            udsPath: daemonSocketPath,
            path: "/v1/wisdai/voice/stream",
            token: apiToken,
            body: body,
            cancellation: handle,
            timeoutSeconds: 180.0
        ) { eventName, jsonData in
            guard let obj = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any] else {
                return
            }
            switch eventName {
            case "start":
                onEvent(.started(
                    turnID: obj["turn_id"] as? String ?? turnID,
                    language: obj["language"] as? String ?? preferredLanguage
                ))
            case "tool_start":
                let rawArgs = (obj["arguments"] as? [String: Any]) ?? [:]
                let strArgs = rawArgs.mapValues { "\($0)" }
                onEvent(.toolStart(tool: obj["tool"] as? String ?? "", arguments: strArgs))
            case "tool_result":
                onEvent(.toolResult(
                    tool: obj["tool"] as? String ?? "",
                    success: obj["success"] as? Bool ?? false,
                    outputPreview: obj["output_preview"] as? String ?? ""
                ))
            case "delta":
                if let t = obj["text"] as? String {
                    onEvent(.tokenDelta(t))
                }
            case "sentence":
                if let t = obj["text"] as? String {
                    onEvent(.sentence(index: obj["index"] as? Int ?? 0, text: t))
                }
            case "done":
                onEvent(.done(
                    turnID: obj["turn_id"] as? String ?? turnID,
                    fullText: obj["full_text"] as? String ?? "",
                    language: obj["language"] as? String ?? preferredLanguage,
                    latencyMS: obj["latency_ms"] as? Double ?? 0
                ))
            case "cancelled":
                onEvent(.cancelled(
                    turnID: obj["turn_id"] as? String ?? turnID,
                    reason: obj["reason"] as? String ?? "barge_in"
                ))
            case "error":
                onEvent(.error(obj["message"] as? String ?? "Erro desconhecido"))
            default:
                break
            }
        }
    }

    public func cancelActiveVoiceTurnAudioOnly() {
        let turnID = activeTurnID
        activeCancellation?.cancel()
        activeCancellation = nil
        activeTurnID = nil
        guard lifecycleState.isReady else { return }
        let sock = daemonSocketPath
        let tok = apiToken
        Task.detached(priority: .userInitiated) {
            let body = try? JSONSerialization.data(withJSONObject: turnID != nil ? ["turn_id": turnID!] : [:])
            _ = try? await OpenJarvisUDSHTTPClient.request(
                udsPath: sock,
                method: "POST",
                path: "/v1/wisdai/voice/cancel",
                token: tok,
                body: body,
                timeoutSeconds: 2.0
            )
        }
    }

    public func shutdown() {
        isShuttingDown = true
        bootTask?.cancel()
        bootTask = nil
        activeCancellation?.cancel()
        activeCancellation = nil
        activeTurnID = nil
        if let proc = daemonProcess, proc.isRunning {
            proc.terminate()
            let deadline = Date().addingTimeInterval(2.5)
            while proc.isRunning && Date() < deadline {
                usleep(50_000)
            }
            if proc.isRunning && daemonPID > 0 {
                kill(daemonPID, SIGKILL)
            }
        }
        daemonProcess = nil
        daemonPID = 0
        hostServer?.stop()
        hostServer = nil
        try? FileManager.default.removeItem(atPath: daemonSocketPath)
        try? FileManager.default.removeItem(atPath: hostSocketPath)
        lifecycleState = .stopped
    }
}
