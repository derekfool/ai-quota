import Foundation
import QuotaCore

@MainActor final class CodexClient {
    private var process: Process?
    private var input: FileHandle?
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextID = 0
    private var buffer = Data()
    private var generation = UUID()

    func fetch() async throws -> QuotaSnapshot {
        if process?.isRunning != true { try await start() }
        let value = try await request("account/rateLimits/read")
        return try QuotaParser.codex(JSONSerialization.data(withJSONObject: value))
    }

    private func start() async throws {
        stop()
        let candidates = [UserDefaults.standard.string(forKey: "codexPath"), "/Applications/ChatGPT.app/Contents/Resources/codex", "/Applications/Codex.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"].compactMap { $0 }
        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else { throw QuotaError.invalidData("未找到 Codex，请安装 Codex 或选择程序路径") }
        let child = Process(), stdinPipe = Pipe(), stdoutPipe = Pipe()
        child.executableURL = URL(fileURLWithPath: path)
        child.arguments = ["app-server"]
        child.standardInput = stdinPipe; child.standardOutput = stdoutPipe; child.standardError = FileHandle.nullDevice
        child.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let token = generation
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if data.isEmpty { self.stop() } else { self.receive(data) }
            }
        }
        child.terminationHandler = { [weak self] _ in Task { @MainActor in if self?.generation == token { self?.stop() } } }
        try child.run()
        process = child; input = stdinPipe.fileHandleForWriting
        _ = try await request("initialize", params: ["clientInfo": ["name": "ai_quota", "version": "0.1.0"]])
        try send(["method": "initialized", "params": [:]])
    }
    private func request(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try send(["id": id, "method": method, "params": params]) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error); return }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, self.pending[id] != nil else { return }
                self.stop(reason: "Codex 请求超时，请重试")
            }
        }
    }
    private func send(_ message: [String: Any]) throws {
        guard let input else { throw QuotaError.invalidData("Codex 服务未连接") }
        var data = try JSONSerialization.data(withJSONObject: message); data.append(10)
        try input.write(contentsOf: data)
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]; buffer.removeSubrange(...newline)
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let id = message["id"] as? Int, let continuation = pending.removeValue(forKey: id) else { continue }
            if let result = message["result"] as? [String: Any] { continuation.resume(returning: result) }
            else { continuation.resume(throwing: QuotaError.invalidData("Codex 无法读取额度，请检查账号登录后重试")) }
        }
    }
    func stop(reason: String = "Codex 服务已断开") {
        generation = UUID()
        if let pipe = process?.standardOutput as? Pipe { pipe.fileHandleForReading.readabilityHandler = nil }
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil; try? input?.close(); input = nil; buffer.removeAll()
        let waiting = pending; pending.removeAll()
        for continuation in waiting.values { continuation.resume(throwing: QuotaError.invalidData(reason)) }
    }
}
