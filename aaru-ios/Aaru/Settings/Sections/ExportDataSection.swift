import AaruAPI
import Foundation
import OpenAPIRuntime
import SwiftUI
import UniformTypeIdentifiers

/// "Export your data" (GET /v1/me/export): the whole account as JSON, or the library as a CSV
/// that opens in a spreadsheet and imports back into Aaru. Saved through the system save panel.
struct ExportDataSection: View {
    let api: Client?
    /// Shows a failure in Settings' problem banner.
    var onProblem: (String) -> Void

    @State private var exporting: ExportFormat?
    @State private var file: ExportFile?
    @State private var savesFile = false

    var body: some View {
        Section {
            ForEach(ExportFormat.allCases) { format in
                Button {
                    Task { await export(format) }
                } label: {
                    HStack {
                        Label(format.label, systemImage: format.symbol)
                        if exporting == format {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(exporting != nil || api == nil)
            }
        } header: {
            Text("Export your data")
        } footer: {
            Text("JSON has everything. The CSV opens in Numbers or Excel and can be imported back into Aaru.")
        }
        .fileExporter(
            isPresented: $savesFile,
            document: file,
            contentType: file?.contentType ?? .json,
            defaultFilename: file?.baseName
        ) { result in
            if case let .failure(error) = result {
                onProblem("The export was not saved. \(error.localizedDescription)")
            }
            file = nil
        }
    }

    private func export(_ format: ExportFormat) async {
        guard let api else { return }
        exporting = format
        defer { exporting = nil }
        do {
            switch try await api.exportAccount(query: .init(format: format.payload)) {
            case let .ok(response):
                let name = Self.filename(response.headers.contentDisposition) ?? format.fallbackName
                let data: Data = switch response.body {
                case let .json(export): try Self.readableJSON(export)
                case let .csv(body): try await Data(collecting: body, upTo: 50 * 1024 * 1024)
                }
                file = ExportFile(data: data, contentType: format.contentType, filename: name)
                savesFile = true
            case let .default(_, error):
                onProblem((try? error.body.json.message) ?? "The export could not be made.")
            }
        } catch {
            onProblem("The export could not be made. Aaru could not reach the server.")
        }
    }

    /// Pretty-printed with ISO dates, so the file is readable as well as complete.
    static func readableJSON(_ export: Components.Schemas.AccountExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    /// `attachment; filename="aaru-export-2026-10-16.json"` → `aaru-export-2026-10-16.json`.
    static func filename(_ disposition: String?) -> String? {
        guard let disposition, let range = disposition.range(of: "filename=") else { return nil }
        let name = disposition[range.upperBound...]
            .split(separator: ";").first?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return name?.isEmpty == false ? name : nil
    }
}

private enum ExportFormat: String, CaseIterable, Identifiable {
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

/// The downloaded export, handed to the save panel as is.
private struct ExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]

    let data: Data
    let contentType: UTType
    let filename: String

    /// The save panel adds the extension for `contentType`, so it gets the name without one.
    var baseName: String {
        (filename as NSString).deletingPathExtension
    }

    init(data: Data, contentType: UTType, filename: String) {
        self.data = data
        self.contentType = contentType
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
        filename = configuration.file.filename ?? "aaru-export"
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
