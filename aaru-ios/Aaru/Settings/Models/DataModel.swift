import AaruAPI
import Foundation
import Observation
import OpenAPIRuntime
import UniformTypeIdentifiers

/// Settings → Your data → Export (GET /v1/me/export): the whole account as JSON, or the library
/// as a CSV that opens in a spreadsheet and imports back into Aaru.
@MainActor
@Observable
final class DataModel {
    /// The format being made, so its row shows progress.
    private(set) var exporting: ExportFormat?
    var problem: String?

    @ObservationIgnored private let api: Client?

    init(api: Client?) {
        self.api = api
    }

    var isAvailable: Bool {
        api != nil
    }

    /// The downloaded file, ready for the save panel, or nil with `problem` set.
    func export(_ format: ExportFormat) async -> ExportFile? {
        guard let api else { return nil }
        exporting = format
        problem = nil
        defer { exporting = nil }
        do {
            switch try await api.exportAccount(query: .init(format: format.payload)) {
            case let .ok(response):
                let name = Self.filename(response.headers.contentDisposition) ?? format.fallbackName
                let data: Data = switch response.body {
                case let .json(export): try Self.readableJSON(export)
                case let .csv(body): try await Data(collecting: body, upTo: 50 * 1024 * 1024)
                }
                return ExportFile(data: data, contentType: format.contentType, filename: name)
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "The export could not be made."
            }
        } catch {
            problem = "The export could not be made. Aaru could not reach the server."
        }
        return nil
    }

    /// Pretty-printed with ISO dates, so the file is readable as well as complete.
    nonisolated static func readableJSON(_ export: Components.Schemas.AccountExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    /// `attachment; filename="aaru-export-2026-10-16.json"` → `aaru-export-2026-10-16.json`.
    nonisolated static func filename(_ disposition: String?) -> String? {
        guard let disposition, let range = disposition.range(of: "filename=") else { return nil }
        let name = disposition[range.upperBound...]
            .split(separator: ";").first?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return name?.isEmpty == false ? name : nil
    }

    func reset() {
        problem = nil
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case json, csv

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .json: "Everything (JSON)"
        case .csv: "Library spreadsheet (CSV)"
        }
    }

    var symbol: String {
        switch self {
        case .json: "doc.text"
        case .csv: "tablecells"
        }
    }

    var payload: Operations.ExportAccount.Input.Query.FormatPayload {
        switch self {
        case .json: .json
        case .csv: .csv
        }
    }

    var contentType: UTType {
        switch self {
        case .json: .json
        case .csv: .commaSeparatedText
        }
    }

    var fallbackName: String {
        switch self {
        case .json: "aaru-export.json"
        case .csv: "aaru-library.csv"
        }
    }
}
