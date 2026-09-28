// StubURLProtocol.swift
//
// A `URLProtocol` that answers every request with a scripted reply and
// records what was sent (add-vault-connection design D13). Injected through
// `URLSessionConfiguration.protocolClasses`, so `GitHubContentsClient` runs
// its real request building, session, delegate and classification -- only
// the network is replaced. No test in this package ever reaches
// api.github.com or holds a real token: this repository is public.
//
// Tests run serially (XCTest's default for `swift test`), so one global,
// lock-protected script is enough; every test calls `reset` in `setUp`.

import Foundation

final class StubURLProtocol: URLProtocol {
    struct Reply {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body = Data()
        /// Fail with this error instead of answering.
        var error: URLError?
        /// Answer with a 302 to this URL instead.
        var redirectTo: URL?

        static func status(_ status: Int, headers: [String: String] = [:], body: Data = Data()) -> Reply {
            Reply(status: status, headers: headers, body: body)
        }

        static func failure(_ code: URLError.Code) -> Reply {
            Reply(error: URLError(code))
        }

        static func redirect(to url: URL) -> Reply {
            Reply(redirectTo: url)
        }
    }

    struct Recorded {
        let url: URL?
        let method: String
        let headers: [String: String]
        let body: Data

        func header(_ name: String) -> String? {
            headers.first { $0.key.lowercased() == name.lowercased() }?.value
        }
    }

    private final class Script: @unchecked Sendable {
        let lock = NSLock()
        var handler: (URLRequest) -> Reply = { _ in Reply.status(500) }
        var recorded: [Recorded] = []
    }

    private static let script = Script()

    /// Clears the recorded requests and sets how requests are answered.
    static func reset(_ handler: @escaping (URLRequest) -> Reply = { _ in Reply.status(500) }) {
        script.lock.lock()
        script.handler = handler
        script.recorded = []
        script.lock.unlock()
    }

    /// Answers requests in order with `replies`; the last one repeats.
    static func reset(replies: [Reply]) {
        let queue = ReplyQueue(replies)
        reset { _ in queue.next() }
    }

    static var requests: [Recorded] {
        script.lock.lock()
        defer { script.lock.unlock() }
        return script.recorded
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.read(request.httpBodyStream)
        Self.script.lock.lock()
        Self.script.recorded.append(Recorded(url: request.url, method: request.httpMethod ?? "GET", headers: request.allHTTPHeaderFields ?? [:], body: body))
        let handler = Self.script.handler
        Self.script.lock.unlock()

        let reply = handler(request)
        guard let url = request.url else { return }
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        if let target = reply.redirectTo {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty {
            client?.urlProtocol(self, didLoad: reply.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// Hands out scripted replies in order; the last one repeats.
private final class ReplyQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [StubURLProtocol.Reply]

    init(_ replies: [StubURLProtocol.Reply]) {
        self.replies = replies
    }

    func next() -> StubURLProtocol.Reply {
        lock.lock()
        defer { lock.unlock() }
        guard !replies.isEmpty else { return .status(500) }
        return replies.count > 1 ? replies.removeFirst() : replies[0]
    }
}
