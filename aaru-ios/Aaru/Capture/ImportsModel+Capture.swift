import AaruAPI
import OpenAPIRuntime

typealias LeftOutImportRow = Operations.LeaveOutImportRow.Output.Ok.Body.JsonPayload

extension ImportsModel {
    /// What a capture came to.
    enum CaptureOutcome {
        case started(ImportJob)
        case failed(String)
    }

    /// AG-006: one capture. The server reads it in the background and plans it like an import.
    /// `kind` reads that kind only; the Books page sends `.book` (BOOK-001).
    func capture(_ content: CaptureContent, kind: MediaKind? = nil) async -> CaptureOutcome {
        guard let api else { return .failed("Aaru could not take that capture.") }
        let body: Operations.CreateCaptureImport.Input.Body = switch content {
        case let .text(text): .json(.init(text: text))
        case let .link(url): .json(.init(url: url))
        case let .images(pictures) where pictures.count == 1: .jpeg(HTTPBody(pictures[0]))
        case let .images(pictures):
            .multipartForm(.init(pictures.map { jpeg in
                .image(.init(payload: .init(body: HTTPBody(jpeg)), filename: "capture.jpg"))
            }))
        }
        do {
            switch try await api.createCaptureImport(query: .init(kind: kind == .book ? .book : nil), body: body) {
            case let .accepted(response):
                let job = try response.body.json
                started(job)
                return .started(job)
            case let .default(_, error):
                return .failed((try? error.body.json.message) ?? "Aaru could not take that capture.")
            }
        } catch {
            return .failed("Aaru could not reach the server. Try again in a moment.")
        }
    }

    /// BOOK-001: a row of a planned capture ticked or unticked. It answers like `resolve`.
    func leaveOut(_ id: String, row index: Int, leftOut: Bool) async -> LeftOutImportRow? {
        guard let api else { return nil }
        problem = nil
        do {
            switch try await api.leaveOutImportRow(
                path: .init(id: id, index: index), body: .json(.init(leftOut: leftOut))
            ) {
            case let .ok(response):
                let answer = try response.body.json
                replace(answer.job)
                return answer
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "That row could not be changed."
            }
        } catch {
            problem = "That row was not changed. Aaru could not reach the server."
        }
        return nil
    }
}
