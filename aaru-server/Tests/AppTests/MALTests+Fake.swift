import Foundation
@testable import aaru

extension MALTests {
    /// Canned MAL: token, user, list and list-status routes. Records every request.
    final class FakeMAL: @unchecked Sendable {
        // @unchecked: test-only; `lock` guards `patchStatus`, `list` and `listStatus`.
        private let lock = NSLock()
        private var patchStatus = 200
        /// The user's anime list as MAL answers it, newest change first (SCR-010).
        private var list: [[String: Any]] = []
        private var listStatus = 200
        let transport: StubTransport

        init() {
            let box = FakeMALBox()
            transport = StubTransport { box.mal?.answer($0) ?? OutboundResponse(status: 500, body: Data()) }
            box.mal = self
        }

        func failPatches(_ status: Int) {
            lock.withLock { patchStatus = status }
        }

        func setList(_ entries: [[String: Any]]) {
            lock.withLock { list = entries }
        }

        func failList(_ status: Int) {
            lock.withLock { listStatus = status }
        }

        func answer(_ request: OutboundRequest) -> OutboundResponse {
            switch request.url.path {
            case "/v2/users/@me/animelist":
                return lock.withLock { listPage(request) }
            case "/v1/oauth2/token":
                let body = #"{"token_type":"Bearer","expires_in":2678400,"access_token":"at-1","refresh_token":"rt-1"}"#
                return OutboundResponse(status: 200, body: Data(body.utf8))
            case "/v2/users/@me":
                return OutboundResponse(status: 200, body: Data(#"{"id":1,"name":"ana"}"#.utf8))
            default:
                guard request.method == "PATCH", request.url.path.hasSuffix("/my_list_status") else {
                    return OutboundResponse(status: 404, body: Data())
                }
                return OutboundResponse(status: lock.withLock { patchStatus }, body: Data("{}".utf8))
            }
        }

        /// One page by `offset` and `limit`, with `paging.next` while entries remain.
        private func listPage(_ request: OutboundRequest) -> OutboundResponse {
            guard listStatus == 200 else { return OutboundResponse(status: listStatus, body: Data()) }
            let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> Int {
                query.first { $0.name == name }?.value.flatMap { Int($0) } ?? 0
            }
            let (offset, limit) = (value("offset"), max(value("limit"), 1))
            var body: [String: Any] = ["data": Array(list.dropFirst(offset).prefix(limit)), "paging": [:]]
            if offset + limit < list.count {
                body["paging"] = ["next": "https://api.myanimelist.net/v2/users/@me/animelist?offset=\(offset + limit)"]
            }
            return OutboundResponse(status: 200, body: (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
        }

        /// Every list write, oldest first: the MAL id and its form fields.
        var patches: [(malID: String, fields: [String: String])] {
            transport.requests.filter { $0.method == "PATCH" }.map { request in
                let parts = request.url.pathComponents
                return (parts[parts.count - 2], MALTests.form(request.body))
            }
        }
    }
}

/// Breaks the cycle between the fake and its transport's handler.
private final class FakeMALBox: @unchecked Sendable {
    // @unchecked: test-only; set once before any request.
    weak var mal: MALTests.FakeMAL?
}
