import SwiftUI
import UniformTypeIdentifiers

/// Your data → Export (GET /v1/me/export): the whole account as JSON, or the library as a CSV
/// that opens in a spreadsheet and imports back into Aaru. Saved through the system save panel.
struct ExportDataSection: View {
    let model: DataModel

    @State private var file: ExportFile?

    var body: some View {
        Section {
            ForEach(ExportFormat.allCases) { format in
                Button {
                    Task { file = await model.export(format) }
                } label: {
                    HStack {
                        Label(format.label, systemImage: format.symbol)
                        if model.exporting == format {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(model.exporting != nil || !model.isAvailable)
            }
        } header: {
            Text("Export")
        } footer: {
            Text("JSON has everything. The CSV opens in Numbers or Excel and can be imported back into Aaru.")
        }
        .fileExporter(
            isPresented: $file.isPresent,
            document: file,
            contentType: file?.contentType ?? .json,
            defaultFilename: file?.baseName
        ) { result in
            if case let .failure(error) = result {
                model.problem = "The export was not saved. \(error.localizedDescription)"
            }
            file = nil
        }
    }
}

/// The downloaded export, handed to the save panel as is.
struct ExportFile: FileDocument {
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
