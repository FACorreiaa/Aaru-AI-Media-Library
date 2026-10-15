import Foundation

/// A parsed CSV file: a header row and records keyed by header. RFC 4180 quoting (commas,
/// newlines and doubled quotes inside quotes), CRLF or LF, and a leading BOM are handled.
struct CSVTable {
    let headers: [String]
    let records: [[String: String]]

    init(_ text: String) {
        var reader = Reader()
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" {
            scalars.removeFirst()
        }
        var index = 0
        while index < scalars.count {
            let next = index + 1 < scalars.count ? scalars[index + 1] : nil
            index += reader.consume(scalars[index], next: next)
        }
        let rows = reader.finish()
        let headers = (rows.first ?? []).map { $0.trimmingCharacters(in: .whitespaces) }
        self.headers = headers
        records = rows.dropFirst()
            .filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
            .map { values in
                var record: [String: String] = [:]
                for (column, header) in headers.enumerated() where column < values.count {
                    record[header] = values[column].trimmingCharacters(in: .whitespaces)
                }
                return record
            }
    }

    /// The scanner: one scalar at a time, returning how many scalars it used.
    private struct Reader {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false

        mutating func consume(_ scalar: Unicode.Scalar, next: Unicode.Scalar?) -> Int {
            if quoted {
                return consumeQuoted(scalar, next: next)
            }
            switch scalar {
            case "\"" where field.isEmpty: quoted = true
            case ",": endField()
            case "\r": break
            case "\n": endRow()
            default: field.unicodeScalars.append(scalar)
            }
            return 1
        }

        private mutating func consumeQuoted(_ scalar: Unicode.Scalar, next: Unicode.Scalar?) -> Int {
            guard scalar == "\"" else {
                field.unicodeScalars.append(scalar)
                return 1
            }
            if next == "\"" {
                field.unicodeScalars.append("\"")
                return 2
            }
            quoted = false
            return 1
        }

        private mutating func endField() {
            row.append(field)
            field = ""
        }

        private mutating func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        mutating func finish() -> [[String]] {
            if !field.isEmpty || !row.isEmpty {
                endRow()
            }
            return rows
        }
    }
}
