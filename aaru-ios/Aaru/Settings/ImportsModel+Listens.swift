import AaruAPI
import Foundation
import OpenAPIRuntime

/// MUS-004: listening history. Files and accounts go to the listening log, never the library,
/// and an applied import undoes by itself rather than from History.
extension ImportsModel {
    /// A listening history file's limit (`ImportService.maxListenUploadBytes`).
    static let maxListenUploadBytes = 24 * 1024 * 1024

    /// An export's body: listening history as its bytes, XML, else CSV. `auto` is sniffed by the
    /// server; the type only says which body this is.
    static func body(_ data: Data, source: ImportFileSource) -> Operations.CreateCSVImport.Input.Body {
        if source.isListening {
            return .binary(HTTPBody(data))
        }
        return source == .mal || data.first == UInt8(ascii: "<") ? .xml(HTTPBody(data)) : .csv(HTTPBody(data))
    }

    /// A Spotify or YouTube history file, checked here first: a .zip goes in one file at a time.
    func uploadListening(_ data: Data, filename: String, source: ImportFileSource) async -> ImportJob? {
        guard data.count <= Self.maxListenUploadBytes else {
            problem = "That file is larger than 24 MB. Spotify splits its history into smaller files; "
                + "add them one at a time."
            return nil
        }
        guard !data.starts(with: [0x50, 0x4B]) else {
            problem = "This is a .zip file. Unzip it and add the .json files inside, one at a time."
            return nil
        }
        return await upload(data, filename: filename, source: source)
    }

    /// A Last.fm or ListenBrainz account's listens. The server reads them in the background; the
    /// job's `filename` is the username.
    func importListens(from source: HistorySource, username: String) async -> ImportJob? {
        guard let api else { return nil }
        problem = nil
        let body = Components.Schemas.ListenAccount(username: username)
        let fallback = "That \(source.title) import could not be started."
        do {
            let job: ImportJob
            if source == .lastFM {
                switch try await api.createLastFMImport(body: .json(body)) {
                case let .accepted(response): job = try response.body.json
                case let .default(_, error):
                    problem = (try? error.body.json.message) ?? fallback
                    return nil
                }
            } else {
                switch try await api.createListenBrainzImport(body: .json(body)) {
                case let .accepted(response): job = try response.body.json
                case let .default(_, error):
                    problem = (try? error.body.json.message) ?? fallback
                    return nil
                }
            }
            started(job)
            return job
        } catch {
            problem = "The import did not start. Aaru could not reach the server."
        }
        return nil
    }

    /// Undoes an applied listening import: its listens go, and so does the import.
    func undoListens(_ id: String) async -> Bool {
        guard let api else { return false }
        problem = nil
        do {
            switch try await api.undoListenImport(path: .init(id: id)) {
            case .noContent:
                // The import is gone on the server too.
                await load()
                return true
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "The import was not undone."
            }
        } catch {
            problem = "The import was not undone. Aaru could not reach the server."
        }
        return false
    }
}
