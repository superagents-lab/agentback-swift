import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import Agentback

private let key = "af_" + String(repeating: "a", count: 64)
private let origin = URL(string: "https://agentback.app")!

private func response(_ request: URLRequest, status: Int = 201,
                      body: String = #"{"id":"fb_test","status":"new"}"#,
                      headers: [String: String] = [:]) -> (Data, URLResponse) {
    (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                                    httpVersion: nil, headerFields: headers)!)
}

@Test func sendsNativeReportWithoutSecretsOrDiagnostics() async throws {
    let client = try Agentback(projectKey: key, origin: origin) { request in
        #expect(request.url?.absoluteString == "https://agentback.app/f/\(key)")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String])
        #expect(body == ["message": "行情没有刷新", "category": "bug", "source": "native", "version": "0.15.15"])
        return response(request)
    }
    let receipt = try await client.send(.init(message: "  行情没有刷新\n", category: .bug, version: "0.15.15"))
    #expect(receipt.id == "fb_test")
}

@Test func sendsSignedIdentityAndAgentFields() async throws {
    let signature = String(repeating: "b", count: 64)
    let client = try Agentback(projectKey: key, origin: origin) { request in
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(body["account"] as? String == "opaque-id")
        #expect(body["account_signature"] as? String == signature)
        #expect(body["request_id"] as? String == "req-1")
        #expect(body["outcome"] as? String == "worked_around")
        #expect(body["source"] as? String == "mcp")
        #expect((body["agent"] as? [String: String])?["name"] == "Example")
        return response(request)
    }
    _ = try await client.send(.init(message: "Missing field", source: .mcp, outcome: .workedAround,
                                   requestID: "req-1", agent: .init(name: "Example"),
                                   identity: .init(account: " opaque-id ", signature: signature)))
}

@Test func validatesBeforeSending() async throws {
    let client = try Agentback(projectKey: key, origin: origin) { request in
        Issue.record("Invalid report reached transport")
        return response(request)
    }
    for message in [" \n", String(repeating: "a", count: 4001), String(repeating: "😀", count: 2001)] {
        await #expect(throws: AgentbackError.invalidReport(field: "message")) {
            try await client.send(.init(message: message))
        }
    }
    await #expect(throws: AgentbackError.invalidReport(field: "version")) {
        try await client.send(.init(message: "Valid", version: String(repeating: "a", count: 65)))
    }
    await #expect(throws: AgentbackError.invalidReport(field: "account_signature")) {
        try await client.send(.init(message: "Valid", identity: .init(account: "user", signature: "bad")))
    }
}

@Test func enforcesUTF16Boundary() async throws {
    let client = try Agentback(projectKey: key, origin: origin) { response($0) }
    _ = try await client.send(.init(message: String(repeating: "😀", count: 2000)))
}

@Test func rejectsSecretsAndUnsafeOrigins() throws {
    for invalidKey in ["af_sk_" + String(repeating: "a", count: 64), "af_id_abc", "af_../bad", ""] {
        #expect(throws: AgentbackError.invalidConfiguration) { try Agentback(projectKey: invalidKey) }
    }
    for url in ["http://example.com", "https://user:pass@example.com", "https://example.com/prefix",
                "https://example.com?query=1", "https://example.com#fragment"] {
        #expect(throws: AgentbackError.invalidConfiguration) {
            try Agentback(projectKey: key, origin: URL(string: url)!)
        }
    }
    _ = try Agentback(projectKey: key, origin: URL(string: "http://127.0.0.1:3020")!)
}

@Test(arguments: [400, 401, 404, 413, 415, 429, 500, 503])
func exposesHTTPFailure(status: Int) async throws {
    let client = try Agentback(projectKey: key, origin: origin) { request in
        response(request, status: status, body: #"{"error":"Rejected"}"#, headers: ["Retry-After": "60"])
    }
    let error = AgentbackError.http(status: status, retryAfter: 60)
    await #expect(throws: error) { try await client.send(.init(message: "Valid")) }
    #expect(error.retryable == (status == 429 || status >= 500))
}

@Test(arguments: [#"{"id":"fb_test","status":"resolved"}"#, #"{"status":"new"}"#, "not json"])
func rejectsMalformedReceipt(body: String) async throws {
    let client = try Agentback(projectKey: key, origin: origin) { response($0, body: body) }
    await #expect(throws: AgentbackError.invalidResponse) { try await client.send(.init(message: "Valid")) }
}

@Test func handlesNetworkFailureAndCancellation() async throws {
    let offline = try Agentback(projectKey: key, origin: origin) { _ in throw URLError(.notConnectedToInternet) }
    await #expect(throws: AgentbackError.network) { try await offline.send(.init(message: "Valid")) }
    let cancelled = try Agentback(projectKey: key, origin: origin) { _ in throw URLError(.cancelled) }
    await #expect(throws: CancellationError.self) { try await cancelled.send(.init(message: "Valid")) }
}

@Test func doesNotAcceptOtherSuccessStatus() async throws {
    let client = try Agentback(projectKey: key, origin: origin) { response($0, status: 200) }
    await #expect(throws: AgentbackError.http(status: 200, retryAfter: nil)) {
        try await client.send(.init(message: "Valid"))
    }
}

@Test(arguments: [Agentback.Source.direct, .mcp, .cli, .web])
func preservesExplicitSourceOverride(source: Agentback.Source) async throws {
    let client = try Agentback(projectKey: key, origin: origin) { request in
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String])
        #expect(body["source"] == source.rawValue)
        return response(request)
    }
    _ = try await client.send(.init(message: "Explicit channel", source: source))
}
