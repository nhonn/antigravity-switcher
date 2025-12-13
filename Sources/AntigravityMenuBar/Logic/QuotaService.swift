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
    }

    private func detectLanguageServer(maxWaitSeconds: TimeInterval = 10) async throws -> ServerInfo {
        let deadline = Date().addingTimeInterval(maxWaitSeconds)

        while Date() < deadline {
            if let info = try? await detectLanguageServerOnce() {
                return info
            }
            try await Task.sleep(nanoseconds: 400_000_000) // 0.4s
        }

        throw AppError.languageServerNotFound
    }

    private func detectLanguageServerOnce() async throws -> ServerInfo {
        // 1) Find language_server PID + csrf token from command line
        // pgrep -fl => "PID full_command_line"
        let pgrep = try Shell.run("/usr/bin/pgrep", ["-fl", "language_server"], timeoutSeconds: 2)
        let lines = pgrep.stdout
            .split(separator: "\n")
            .map { String($0) }

        let candidate = lines.first { line in
            line.contains("--csrf_token") && line.contains("--extension_server_port")
        }

        guard let candidate else {
            throw AppError.languageServerNotFound
        }

        let parts = candidate.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count >= 2, let pid = Int(parts[0]) else {
            throw AppError.languageServerNotFound
        }
        let cmd = String(parts[1])

        guard let csrfToken = Regex.firstMatch(in: cmd, pattern: "--csrf_token[=\\s]+([A-Za-z0-9\\-]+)") else {
            throw AppError.languageServerNotFound
        }

        // 2) List listening ports for PID
        let lsof = try Shell.run("/usr/sbin/lsof", ["-iTCP", "-sTCP:LISTEN", "-n", "-P", "-p", String(pid)], timeoutSeconds: 2)
        let ports = Self.parseListeningPorts(from: lsof.stdout)
        if ports.isEmpty {
            throw AppError.languageServerPortNotFound
        }

        // 3) Find the port that actually speaks the Connect protocol endpoints
        for port in ports {
            if (try? await testPort(port: port, csrfToken: csrfToken)) == true {
                return ServerInfo(pid: pid, csrfToken: csrfToken, connectPort: port)
            }
        }

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

    private func testPort(port: Int, csrfToken: String) async throws -> Bool {
        let statusCode = try await requestRawStatusCode(
            port: port,
            csrfToken: csrfToken,
            path: "/exa.language_server_pb.LanguageServerService/GetUnleashData",
            body: ["wrapper_data": [:]]
        )
        return statusCode == 200
    }

    // MARK: - HTTP

    private func request<T: Decodable>(port: Int, csrfToken: String, path: String, body: [String: Any]) async throws -> T {
        let url = URL(string: "https://127.0.0.1:\(port)\(path)")!

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

    private func requestRawStatusCode(port: Int, csrfToken: String, path: String, body: [String: Any]) async throws -> Int {
        let url = URL(string: "https://127.0.0.1:\(port)\(path)")!

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
