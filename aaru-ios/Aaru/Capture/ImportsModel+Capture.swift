import AaruAPI
import OpenAPIRuntime

extension ImportsModel {
    /// What a capture came to. Past the free month's captures the server answers 402: an answer
    /// for the composer to show, not a failure.
    enum CaptureOutcome {
        case started(ImportJob)
        case quota(String)
        case failed(String)
    }

    /// AG-006: one capture. The server reads it in the background and plans it like an import.
    func capture(_ content: CaptureContent) async -> CaptureOutcome {
        guard let api else { return .failed("Aaru could not take that capture.") }
        let body: Operations.CreateCaptureImport.Input.Body = switch content {
        case let .text(text): .json(.init(text: text))
        case let .link(url): .json(.init(url: url))
        case let .image(data): .jpeg(HTTPBody(data))
        }
        do {
            switch try await api.createCaptureImport(body: body) {
            case let .accepted(response):
                let job = try response.body.json
                started(job)
                return .started(job)
            case let .default(status, error):
                let message = try? error.body.json.message
                return status == 402
                    ? .quota(message ?? "This month's captures are used.")
                    : .failed(message ?? "Aaru could not take that capture.")
            }
        } catch {
            return .failed("Aaru could not reach the server. Try again in a moment.")
        }
    }
}
