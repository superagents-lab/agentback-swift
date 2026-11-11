import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Submission-only client for native apps. Ship a public project key, never a server secret.
public struct Agentback: Sendable {
    public enum Category: String, Codable, Sendable, CaseIterable {
        case bug, featureRequest = "feature_request", docs, other
    }

    public enum Source: String, Codable, Sendable {
        case direct, mcp, cli, web
    }

    public enum Outcome: String, Codable, Sendable {
        case blocked, workedAround = "worked_around", friction
    }

    public struct Identity: Sendable {
        public let account: String
        public let signature: String

        /// Signature must come from your backend; never embed the identity secret in an app.
        public init(account: String, signature: String) {
            self.account = account
            self.signature = signature
        }
    }

    public struct Reporter: Codable, Sendable {
        public var name: String?
        public var model: String?

        public init(name: String? = nil, model: String? = nil) {
            self.name = name
            self.model = model
        }
    }

    public struct Report: Sendable {
        public var message: String
        public var category: Category
        public var source: Source
        public var version: String?
        public var outcome: Outcome?
        public var intent: String?
        public var expected: String?
        public var actual: String?
        public var suggestion: String?
        public var tool: String?
        public var requestID: String?
        public var agent: Reporter?
        public var identity: Identity?

        public init(message: String, category: Category = .other, source: Source = .direct,
                    version: String? = nil, outcome: Outcome? = nil, intent: String? = nil,
                    expected: String? = nil, actual: String? = nil, suggestion: String? = nil,
                    tool: String? = nil, requestID: String? = nil, agent: Reporter? = nil,
                    identity: Identity? = nil) {
            self.message = message
            self.category = category
            self.source = source
            self.version = version
            self.outcome = outcome
            self.intent = intent
            self.expected = expected
            self.actual = actual
            self.suggestion = suggestion
            self.tool = tool
            self.requestID = requestID
            self.agent = agent
            self.identity = identity
        }
    }

    public struct Receipt: Decodable, Sendable {
        public let id: String
        public let status: String
    }

    private let endpoint: URL
    private let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// HTTPS is required except for loopback development servers. Uses an ephemeral session
    /// by default so feedback never shares the application's cookies or disk cache.
    public init(projectKey: String, origin: URL = URL(string: "https://agentback.app")!,
                session: URLSession = URLSession(configuration: .ephemeral)) throws {
        try self.init(projectKey: projectKey, origin: origin, transport: { request in
            try await session.data(for: request)
        })
    }

    init(projectKey: String, origin: URL,
         transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) throws {
        guard projectKey.range(of: "^af_[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw AgentbackError.invalidConfiguration
        }
        guard let components = URLComponents(url: origin, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              components.scheme == "https" ||
                (components.scheme == "http" && ["localhost", "127.0.0.1", "[::1]"].contains(host)) else {
            throw AgentbackError.invalidConfiguration
        }
        self.endpoint = origin.appendingPathComponent("f").appendingPathComponent(projectKey)
        self.transport = transport
    }

    /// Does not queue or retry automatically: a lost response may already have been stored.
    /// A successful submission is acknowledged only after a valid HTTP 201 receipt.
    public func send(_ report: Report) async throws -> Receipt {
        try Task.checkCancellation()
        let payload = try Payload(report)
        let body = try JSONEncoder().encode(payload)
        guard body.count <= 65_536 else { throw AgentbackError.invalidReport(field: "body") }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                throw CancellationError()
            }
            throw AgentbackError.network
        }
        guard let http = response as? HTTPURLResponse else { throw AgentbackError.invalidResponse }
        guard http.statusCode == 201 else {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw AgentbackError.http(status: http.statusCode, retryAfter: retryAfter)
        }
        guard let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
              receipt.id.hasPrefix("fb_"), receipt.id.count > 3, receipt.status == "new" else {
            throw AgentbackError.invalidResponse
        }
        return receipt
    }
}

public enum AgentbackError: Error, Sendable, Equatable {
    case invalidConfiguration
    case invalidReport(field: String)
    case network
    case invalidResponse
    case http(status: Int, retryAfter: TimeInterval?)

    /// A retry may succeed, but the caller decides when to retry to avoid duplicate reports.
    public var retryable: Bool {
        switch self {
        case .network: true
        case .http(let status, _): status == 429 || (500...599).contains(status)
        default: false
        }
    }
}

private struct Payload: Encodable {
    let message: String
    let category: Agentback.Category
    let source: Agentback.Source
    let version: String?
    let outcome: Agentback.Outcome?
    let intent: String?
    let expected: String?
    let actual: String?
    let suggestion: String?
    let tool: String?
    let request_id: String?
    let agent: Agentback.Reporter?
    let account: String?
    let account_signature: String?

    init(_ report: Agentback.Report) throws {
        func text(_ value: String?, _ field: String, _ limit: Int) throws -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            // Server limits are JavaScript string lengths, i.e. UTF-16 code units.
            guard trimmed.utf16.count <= limit else { throw AgentbackError.invalidReport(field: field) }
            return trimmed
        }
        message = try text(report.message, "message", 4000)!
        guard !message.isEmpty else { throw AgentbackError.invalidReport(field: "message") }
        category = report.category
        source = report.source
        version = try text(report.version, "version", 64)
        outcome = report.outcome
        intent = try text(report.intent, "intent", 2000)
        expected = try text(report.expected, "expected", 2000)
        actual = try text(report.actual, "actual", 4000)
        suggestion = try text(report.suggestion, "suggestion", 2000)
        tool = try text(report.tool, "tool", 128)
        request_id = try text(report.requestID, "request_id", 256)
        if let reporter = report.agent {
            agent = try .init(name: text(reporter.name, "agent.name", 128),
                              model: text(reporter.model, "agent.model", 128))
        } else { agent = nil }
        account = try text(report.identity?.account, "account", 256)
        account_signature = report.identity?.signature
        if let identity = report.identity {
            guard account != "",
                  identity.signature.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
                throw AgentbackError.invalidReport(field: "account_signature")
            }
        }
    }
}
