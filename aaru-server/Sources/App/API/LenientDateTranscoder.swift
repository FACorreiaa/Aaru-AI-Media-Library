import Foundation
import OpenAPIRuntime

/// ISO-8601 dates with or without fractional seconds.
///
/// The default transcoder rejects `2026-10-18T00:00:00.000Z`, which is what a browser's
/// `toISOString()` sends, and the request fails as a 400 before any handler runs. Encoding
/// is unchanged: whole seconds, as before.
struct LenientDateTranscoder: DateTranscoder {
    private let plain: any DateTranscoder = .iso8601
    private let fractional: any DateTranscoder = .iso8601WithFractionalSeconds

    func encode(_ date: Date) throws -> String {
        try plain.encode(date)
    }

    func decode(_ string: String) throws -> Date {
        if let date = try? plain.decode(string) {
            return date
        }
        return try fractional.decode(string)
    }
}
