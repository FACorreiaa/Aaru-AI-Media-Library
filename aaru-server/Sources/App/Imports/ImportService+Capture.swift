import AaruCore
import Foundation
import Logging
import ServiceLifecycle

/// AG-006 · capture as an import source. A link is read on the request (by its URL alone); text and
/// images are read by the worker through the model, then planned like any other import.
extension ImportService {
    enum CaptureRequest: Equatable {
        case text(String)
        case link(String)
        case image(Data, mediaType: String)

        var kind: String {
            switch self {
            case .text: "text"
            case .link: "url"
            case .image: "image"
            }
        }
    }

    /// Captures a free account may start in one calendar month (UTC).
    static let freeCapturesPerMonth = 3
    static let maxCaptureText = 20000
    /// What the model reads. Clients send JPEG; the others are what the Messages API also takes.
    static let captureImageTypes: Set = ["image/jpeg", "image/png", "image/gif", "image/webp"]
    /// An input the worker never got to is deleted after this long.
    static let captureInputLifetime: TimeInterval = 60 * 60

    func createCapture(userID: UserID, _ request: CaptureRequest) async throws -> ImportJob {
        let jobID = ImportJobID()
        let (rows, input) = try captureContent(request)
        if input != nil, model == nil {
            throw AppError(
                status: .serviceUnavailable, code: "capture_unavailable",
                message: "Aaru cannot read captures right now. A link to the title still works."
            )
        }
        try await checkCaptureQuota(userID)
        if let input {
            try await stores.capture.saveInput(
                CaptureInput(jobID: jobID, userID: userID, content: input, createdAt: now())
            )
        }
        let job = ImportJob(
            id: jobID, userID: userID, source: .capture, createdAt: now(), updatedAt: now(), rowsTotal: rows.count
        )
        try await stores.importJobs.insert(job, rows: rows)
        ProductEvents.capture(.captureSubmitted, userID: userID, ["kind": request.kind])
        return job
    }

    /// A link's row, read from the URL now; or the text or image the worker gives the model.
    private func captureContent(_ request: CaptureRequest) throws -> ([ImportRow], CaptureInput.Content?) {
        switch request {
        case let .link(raw):
            guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw Self.unsupportedLink
            }
            switch CaptureLink.parse(url) {
            case let .title(row): return ([row], nil)
            case let .useCSV(site): throw Self.useCSV(site)
            case .unsupported: throw Self.unsupportedLink
            }
        case let .text(text):
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw AppError(
                    status: .unprocessableContent, code: "validation_failed", message: "There is nothing to read.",
                    details: ["text": "Empty."]
                )
            }
            guard text.count <= Self.maxCaptureText else {
                throw AppError(
                    status: .contentTooLarge, code: "capture_too_large",
                    message: "That is more text than a capture reads. Paste a shorter list, or use an import."
                )
            }
            return ([], .text(text))
        case let .image(data, mediaType):
            guard Self.captureImageTypes.contains(mediaType) else {
                throw AppError(
                    status: .unsupportedMediaType, code: "capture_image_type",
                    message: "Send the image as a JPEG, PNG, GIF or WebP."
                )
            }
            return ([], .image(data, mediaType: mediaType))
        }
    }

    /// Free accounts get `freeCapturesPerMonth`; past it, a 402 the apps answer with Plus.
    private func checkCaptureQuota(_ userID: UserID) async throws {
        let month = Self.monthStart(now())
        let used = try await stores.capture.captures(userID: userID, since: month.start)
        guard used >= Self.freeCapturesPerMonth else { return }
        ProductEvents.capture(.paywallShown, userID: userID, ["reason": "capture_quota"])
        var style = Date.FormatStyle.dateTime.day().month(.wide)
        style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        throw AppError(
            status: .init(code: 402, reasonPhrase: "Payment Required"), code: "capture_quota",
            message: "You have used this month's \(Self.freeCapturesPerMonth) captures. "
                + "More come on \(month.next.formatted(style)), or Aaru Plus lifts the limit."
        )
    }

    /// The UTC month `date` falls in, and the start of the next.
    static func monthStart(_ date: Date) -> (start: Date, next: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        return (start, calendar.date(byAdding: .month, value: 1, to: start) ?? date)
    }

    private static func useCSV(_ site: String) -> AppError {
        AppError(
            status: .unprocessableContent, code: "capture_use_csv",
            message: "Aaru does not read \(site) pages. Export your \(site) list as a CSV and import it instead: "
                + "it brings everything at once."
        )
    }

    private static var unsupportedLink: AppError {
        AppError(
            status: .unprocessableContent, code: "capture_unsupported_url",
            message: "Aaru reads links to a title on TMDB, AniList or Open Library. For anything else, send a "
                + "screenshot or paste the names."
        )
    }

    // MARK: The worker's step

    /// The titles in a text or image capture. Nil when the job failed here for good. The input is
    /// deleted once read, whatever the model found.
    func fetchCapture(_ job: inout ImportJob) async throws -> [ImportRow]? {
        guard let input = try await stores.capture.input(jobID: job.id) else {
            try await fail(&job, "This capture expired before Aaru read it. Send it again.")
            return nil
        }
        guard let model else {
            try await stores.capture.deleteInput(jobID: job.id)
            try await fail(&job, "Aaru cannot read captures right now. Send it again later.")
            return nil
        }
        let extractor = CaptureExtractor(model: model, stores: stores, now: now)
        let outcome = try await extractor.titles(in: input.content, userID: job.userID)
        try await stores.capture.deleteInput(jobID: job.id)
        switch outcome {
        case .refused:
            try await fail(&job, "Aaru could not read that capture.")
            return nil
        case let .titles(rows) where rows.isEmpty:
            try await fail(&job, "Aaru found no film, show, anime or book in that capture.")
            return nil
        case let .titles(rows):
            return rows
        }
    }

    /// "7 ready · 2 need a pick", once a capture's plan is ready.
    static func capturePlanned(_ job: ImportJob) -> PushMessage {
        let ready = job.stats.created + job.stats.updated + job.stats.skipped
        let body = [
            ready > 0 ? "\(ready) ready" : nil,
            job.stats.unmatched == 1 ? "1 needs a pick" : nil,
            job.stats.unmatched > 1 ? "\(job.stats.unmatched) need a pick" : nil,
        ].compactMap(\.self).joined(separator: " · ")
        return PushMessage(
            title: "Your capture is ready to review",
            body: body.isEmpty ? "Open it to see what Aaru found." : body,
            payload: ["importId": job.id.description]
        )
    }
}

/// Deletes capture inputs the worker never read (a job deleted first, a crash), an hour on.
struct CaptureSweeper: Service {
    let stores: Stores
    let logger: Logger
    var every: Duration = .seconds(5 * 60)
    var now: @Sendable () -> Date = { Date() }

    func run() async throws {
        try await cancelWhenGracefulShutdown {
            while !Task.isCancelled {
                do {
                    let cutoff = now().addingTimeInterval(-ImportService.captureInputLifetime)
                    _ = try await stores.capture.sweep(before: cutoff)
                } catch {
                    logger.error("Capture sweep failed", metadata: ["error": "\(error)"])
                }
                try? await Task.sleep(for: every)
            }
        }
    }
}
