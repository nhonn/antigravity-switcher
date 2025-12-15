import Foundation

struct QuotaSnapshot {
    struct PromptCredits {
        let available: Double
        let monthly: Double

        var remainingPercentage: Double {
            guard monthly > 0 else { return 0 }
            return (available / monthly) * 100
        }
    }

    struct ModelQuota {
        let label: String
        let modelId: String
        let remainingFraction: Double?
        let resetTime: Date?

        var remainingPercentage: Double? {
            guard let remainingFraction else { return nil }
            return remainingFraction * 100
        }

        var isExhausted: Bool {
            remainingFraction == 0
        }
    }

    let fetchedAt: Date
    let userName: String?
    let userEmail: String?
    let planName: String?
    let teamsTier: String?
    let promptCredits: PromptCredits?
    let models: [ModelQuota]
}

final class QuotaService {
    static let shared = QuotaService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config, delegate: LocalhostInsecureURLSessionDelegate(), delegateQueue: nil)
    }

    func fetchQuota() async throws -> QuotaSnapshot {
        let server = try await detectLanguageServer()
        let response: ServerUserStatusResponse = try await request(
            scheme: server.scheme,
            port: server.connectPort,
            csrfToken: server.csrfToken,
            path: "/exa.language_server_pb.LanguageServerService/GetUserStatus",
            body: [
                "metadata": [
                    "ideName": "antigravity",
                    "extensionName": "antigravity",
                    "locale": "en"
                ]
            ]
        )

        return mapResponse(response)
    }

    // MARK: - Process detection

    private struct ServerInfo {
        let pid: Int
        let csrfToken: String
        let connectPort: Int
        let scheme: String
    }

    private func detectLanguageServer(maxWaitSeconds: TimeInterval = 15) async throws -> ServerInfo {
        let deadline = Date().addingTimeInterval(maxWaitSeconds)

        var lastError: Error?

        while Date() < deadline {
            do {
                return try await detectLanguageServerOnce()
            } catch {
                lastError = error
            }
            try await Task.sleep(nanoseconds: 400_000_000) // 0.4s
        }

        if let appError = lastError as? AppError {
            throw appError
        }
        if let lastError {
            throw AppError.commandFailed(message: lastError.localizedDescription)
        }
        throw AppError.languageServerNotFound
    }

    private func detectLanguageServerOnce() async throws -> ServerInfo {
        // 1) Find candidate processes by scanning the full process list.
        // Rationale: relying on a fixed process name (e.g. "language_server") is brittle across versions.
        // We instead look for processes that expose the required CSRF token flag and then probe ports.
        let psLines = try loadProcessLines(timeoutSeconds: 6)

        struct Candidate {
            let pid: Int
            let cmd: String
            let score: Int
            let elapsedSeconds: Int
        }

        var candidates: [Candidate] = []
        candidates.reserveCapacity(8)

        for row in psLines {
            let pid = row.pid
            let cmd = row.cmd
            let etimes = row.elapsedSeconds

            // Must have CSRF token so we can authenticate requests.
            guard cmd.contains("--csrf_token") else { continue }

            var score = 0
            let lower = cmd.lowercased()
            if lower.contains("language_server") { score += 10 }
            if lower.contains("exa.") { score += 6 }
            if lower.contains("antigravity") { score += 5 }
            if lower.contains("codeium") { score += 3 }

            candidates.append(.init(pid: pid, cmd: cmd, score: score, elapsedSeconds: etimes))
        }

        candidates.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.elapsedSeconds < $1.elapsedSeconds
        }
        if candidates.isEmpty {
            throw AppError.languageServerNotFound
        }

        // 2) For each candidate PID, extract CSRF token and probe listening ports.
        for candidate in candidates {
            guard let csrfToken = Regex.firstMatch(
                in: candidate.cmd,
                pattern: "--csrf_token(?:=|\\s+)([A-Za-z0-9\\-]+)"
            ) else {
                continue
            }

            // NOTE: lsof selection terms are OR'd by default; we must add -a to AND them,
            // otherwise we'll collect listening ports from unrelated processes.
            let lsof = try Shell.run(
                "/usr/sbin/lsof",
                ["-a", "-p", String(candidate.pid), "-iTCP", "-sTCP:LISTEN", "-n", "-P"],
                timeoutSeconds: 2
            )
            let ports = Self.parseListeningPorts(from: lsof.stdout)
            if ports.isEmpty {
                continue
            }

            // 3) Find the port that actually speaks the Connect protocol endpoints.
            for port in ports {
                if let scheme = (try? await detectScheme(port: port, csrfToken: csrfToken)) {
                    return ServerInfo(pid: candidate.pid, csrfToken: csrfToken, connectPort: port, scheme: scheme)
                }
            }
        }

        // We found CSRF-token processes, but none served the expected endpoints.
        throw AppError.languageServerPortNotFound
    }

    private struct ProcessLine {
        let pid: Int
        let elapsedSeconds: Int
        let cmd: String
    }

    private func loadProcessLines(timeoutSeconds: TimeInterval) throws -> [ProcessLine] {
        // Prefer an elapsed-seconds column when available, but macOS BSD ps doesn't support "etimes".
        // It does support "etime" (elapsed time formatted), which we can parse.
        do {
            let ps = try Shell.run("/bin/ps", ["-ax", "-o", "pid=,etimes=,command="], timeoutSeconds: timeoutSeconds)
            return parsePsEtimesOutput(ps.stdout)
        } catch let ShellError.nonZeroExit(_, _, stderr) {
            if stderr.lowercased().contains("keyword not found") {
                let ps = try Shell.run("/bin/ps", ["-ax", "-o", "pid=,etime=,command="], timeoutSeconds: timeoutSeconds)
                return parsePsEtimeOutput(ps.stdout)
            }
            throw AppError.commandFailed(message: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func parsePsEtimesOutput(_ stdout: String) -> [ProcessLine] {
        // Format: "PID ETIMES COMMAND"
        stdout
            .split(separator: "\n")
            .compactMap { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return nil }
                let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard parts.count == 3, let pid = Int(parts[0]), let etimes = Int(parts[1]) else { return nil }
                return ProcessLine(pid: pid, elapsedSeconds: etimes, cmd: String(parts[2]))
            }
    }

    private func parsePsEtimeOutput(_ stdout: String) -> [ProcessLine] {
        // Format: "PID ETIME COMMAND", where ETIME is [[dd-]hh:]mm:ss
        stdout
            .split(separator: "\n")
            .compactMap { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return nil }
                let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard parts.count == 3, let pid = Int(parts[0]) else { return nil }
                let etime = String(parts[1])
                guard let seconds = parseEtimeToSeconds(etime) else { return nil }
                return ProcessLine(pid: pid, elapsedSeconds: seconds, cmd: String(parts[2]))
            }
    }

    private func parseEtimeToSeconds(_ etime: String) -> Int? {
        // [[dd-]hh:]mm:ss
        let pieces = etime.split(separator: "-")
        var days = 0
        var timePart = etime
        if pieces.count == 2 {
            days = Int(pieces[0]) ?? 0
            timePart = String(pieces[1])
        }

        let fields = timePart.split(separator: ":").map(String.init)
        guard fields.count == 2 || fields.count == 3 else { return nil }

        var hours = 0
        var minutes = 0
        var seconds = 0

        if fields.count == 2 {
            minutes = Int(fields[0]) ?? 0
            seconds = Int(fields[1]) ?? 0
        } else {
            hours = Int(fields[0]) ?? 0
            minutes = Int(fields[1]) ?? 0
            seconds = Int(fields[2]) ?? 0
        }

        return days * 86_400 + hours * 3_600 + minutes * 60 + seconds
    }

    private static func parseListeningPorts(from lsofOutput: String) -> [Int] {
        var result: Set<Int> = []

        for line in lsofOutput.split(separator: "\n") {
            let s = String(line)
            // Typical: "... TCP 127.0.0.1:61349 (LISTEN)"
            if let portStr = Regex.firstMatch(in: s, pattern: "TCP\\s+[^:]+:(\\d+)\\s+\\(LISTEN\\)") {
                if let port = Int(portStr) {
                    result.insert(port)
                }
            } else if let portStr = Regex.firstMatch(in: s, pattern: "TCP\\s+\\*:(\\d+)\\s+\\(LISTEN\\)") {
                if let port = Int(portStr) {
                    result.insert(port)
                }
            }
        }

        return result.sorted()
    }

    private func detectScheme(port: Int, csrfToken: String) async throws -> String? {
        // Some versions expose the Connect endpoints over HTTPS, others over plain HTTP.
        // Probe HTTPS first (preferred), then fall back to HTTP.
        let path = "/exa.language_server_pb.LanguageServerService/GetUnleashData"
        let body: [String: Any] = ["wrapper_data": [:]]

        if (try? await requestRawStatusCode(scheme: "https", port: port, csrfToken: csrfToken, path: path, body: body)) == 200 {
            return "https"
        }
        if (try? await requestRawStatusCode(scheme: "http", port: port, csrfToken: csrfToken, path: path, body: body)) == 200 {
            return "http"
        }
        return nil
    }

    // MARK: - HTTP

    private func request<T: Decodable>(scheme: String, port: Int, csrfToken: String, path: String, body: [String: Any]) async throws -> T {
        let url = URL(string: "\(scheme)://127.0.0.1:\(port)\(path)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.quotaFetchFailed(message: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw AppError.quotaFetchFailed(message: "HTTP \(http.statusCode): \(raw)")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw AppError.quotaFetchFailed(message: "Invalid JSON response: \(raw)")
        }
    }

    private func requestRawStatusCode(scheme: String, port: Int, csrfToken: String, path: String, body: [String: Any]) async throws -> Int {
        let url = URL(string: "\(scheme)://127.0.0.1:\(port)\(path)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.quotaFetchFailed(message: "No HTTP response")
        }
        return http.statusCode
    }

    // MARK: - Mapping

    private func mapResponse(_ response: ServerUserStatusResponse) -> QuotaSnapshot {
        let user = response.userStatus

        var promptCredits: QuotaSnapshot.PromptCredits?
        if let planInfo = user.planStatus?.planInfo,
           let monthly = planInfo.monthlyPromptCredits,
           let available = user.planStatus?.availablePromptCredits {
            promptCredits = .init(available: available, monthly: monthly)
        }

        let formatter = ISO8601DateFormatter()
        let models: [QuotaSnapshot.ModelQuota] = (user.cascadeModelConfigData?.clientModelConfigs ?? []).compactMap { m in
            guard let label = m.label else { return nil }
            let modelId = m.modelOrAlias?.model ?? "unknown"
            let remaining = m.quotaInfo?.remainingFraction
            let resetDate = m.quotaInfo?.resetTime.flatMap { formatter.date(from: $0) }
            return .init(label: label, modelId: modelId, remainingFraction: remaining, resetTime: resetDate)
        }

        return QuotaSnapshot(
            fetchedAt: Date(),
            userName: user.name,
            userEmail: user.email,
            planName: user.planStatus?.planInfo?.planName,
            teamsTier: user.planStatus?.planInfo?.teamsTier,
            promptCredits: promptCredits,
            models: models
        )
    }
}

// MARK: - Response models

private struct ServerUserStatusResponse: Decodable {
    let userStatus: UserStatus

    struct UserStatus: Decodable {
        let name: String?
        let email: String?
        let planStatus: PlanStatus?
        let cascadeModelConfigData: CascadeModelConfigData?
    }

    struct PlanStatus: Decodable {
        let planInfo: PlanInfo?
        let availablePromptCredits: Double?
        let availableFlowCredits: Double?
    }

    struct PlanInfo: Decodable {
        let teamsTier: String?
        let planName: String?
        let monthlyPromptCredits: Double?
        let monthlyFlowCredits: Double?
    }

    struct CascadeModelConfigData: Decodable {
        let clientModelConfigs: [ClientModelConfig]?
    }

    struct ClientModelConfig: Decodable {
        let label: String?
        let modelOrAlias: ModelOrAlias?
        let quotaInfo: QuotaInfo?
    }

    struct ModelOrAlias: Decodable {
        let model: String?
    }

    struct QuotaInfo: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
    }
}

// MARK: - Regex helper

private enum Regex {
    static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let r = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[r])
    }
}
