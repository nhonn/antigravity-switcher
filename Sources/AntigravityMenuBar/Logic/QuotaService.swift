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
        let ps = try Shell.run("/bin/ps", ["-ax", "-o", "pid=,command="], timeoutSeconds: 6)
        let lines = ps.stdout
            .split(separator: "\n")
            .map { String($0) }

        struct Candidate {
            let pid: Int
            let cmd: String
            let score: Int
        }

        var candidates: [Candidate] = []
        candidates.reserveCapacity(8)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int(parts[0]) else { continue }
            let cmd = String(parts[1])

            // Must have CSRF token so we can authenticate requests.
            guard cmd.contains("--csrf_token") else { continue }

            var score = 0
            let lower = cmd.lowercased()
            if lower.contains("language_server") { score += 10 }
            if lower.contains("exa.") { score += 6 }
            if lower.contains("antigravity") { score += 5 }
            if lower.contains("codeium") { score += 3 }

            candidates.append(.init(pid: pid, cmd: cmd, score: score))
        }

        candidates.sort { $0.score > $1.score }
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
