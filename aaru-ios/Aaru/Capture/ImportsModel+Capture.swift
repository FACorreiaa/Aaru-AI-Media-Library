import AaruAPI
import OpenAPIRuntime

typealias LeftOutImportRow = Operations.LeaveOutImportRow.Output.Ok.Body.JsonPayload
typealias MatchedImportRows = Operations.MatchAllImportRows.Output.Ok.Body.JsonPayload

extension ImportsModel {
    /// What a capture came to.
    enum CaptureOutcome {
        case started(ImportJob)
        /// 403 `ai_sharing_required` (PRV-002): the user has not allowed AI sharing.
        case aiSharingRequired
        case failed(String)
    }

    /// AG-006: one capture. The server reads it in the background and plans it like an import.
    /// `kind` reads that kind only; the Books page sends `.book` (BOOK-001).
    func capture(_ content: CaptureContent, kind: MediaKind? = nil) async -> CaptureOutcome {
        guard let api else { return .failed(String(localized: "Aaru could not take that capture.")) }
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
                let refusal = try? error.body.json
                if refusal?.code == AISharingModel.requiredCode {
                    return .aiSharingRequired
                }
                return .failed(refusal?.message ?? String(localized: "Aaru could not take that capture."))
            }
        } catch {
            return .failed(String(localized: "Aaru could not reach the server. Try again in a moment."))
        }
    }

    /// BOOK-001: a row of a planned capture ticked or unticked. It answers like `resolve`.
    /// IMP-021: a best guess for as many unmatched rows as fit in one call.
    func matchAll(_ id: String) async -> MatchedImportRows? {
        guard let api else { return nil }
        problem = nil
        do {
            switch try await api.matchAllImportRows(path: .init(id: id)) {
            case let .ok(response):
                let answer = try response.body.json
                replace(answer.job)
                return answer
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? String(localized: "Match all did not finish.")
            }
        } catch {
            problem = String(localized: "Match all did not finish. Aaru could not reach the server.")
        }
        return nil
    }

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
                problem = (try? error.body.json.message) ?? String(localized: "That row could not be changed.")
            }
        } catch {
            problem = String(localized: "That row was not changed. Aaru could not reach the server.")
        }
        return nil
    }
}
