import AaruCore
import Foundation

/// IMP-009 and IMP-010: Pogdesign CAT (The TV Calendar). CAT has no list export, so it comes in as
/// a pasted list of show names or the user's own iCal file (or its link, read once). Only shows
/// come across: CAT's watched episodes are not in either, so every show is planned as `wishlist`.
/// Names carry no ids and rarely a year, so rows are `nameOnly` and match only when exactly one
/// show has the name.
enum CATImport {
    /// More lines than this is not a show list.
    static let maxLines = 2000
    static let maxNameLength = 200

    /// One row per distinct show, in first-seen order. `name` may end in CAT's `(2026)`. The
    /// show's first known airing is kept to break a tie between same-name shows.
    static func rows(_ shows: [(name: String, airing: ImportAiring?)]) -> [ImportRow] {
        var index: [String: Int] = [:]
        var rows: [ImportRow] = []
        for (raw, airing) in shows {
            let (title, year) = splitYear(raw)
            let key = "\(MatchKey.normalize(title)):\(year.map(String.init) ?? "-")"
            guard !title.isEmpty else { continue }
            if let seen = index[key] {
                rows[seen].airing = rows[seen].airing ?? airing
                continue
            }
            index[key] = rows.count
            rows.append(ImportRow(
                sourceKey: "cat:\(raw)", type: .show, title: title, year: year, ids: ExternalIDs(),
                status: .wishlist, lists: [], nameOnly: year == nil ? true : nil, airing: airing
            ))
        }
        return rows
    }

    /// `Brothers (2026)` → ("Brothers", 2026). CAT tells remakes apart this way.
    static func splitYear(_ name: String) -> (String, Int?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.wholeMatch(of: /(.+?)\s*\((\d{4})\)/),
              let year = Int(match.2), (1900 ... 2100).contains(year)
        else { return (trimmed, nil) }
        return (String(match.1), year)
    }

    static func unsupported(_ text: String, reason: String) -> ImportRow {
        ImportRow(
            sourceKey: "cat:\(text)", type: .show, title: text, ids: ExternalIDs(), lists: [], unsupported: reason
        )
    }
}

// MARK: Pasted list (IMP-009)

/// One show per line, as typed or copied from CAT's show pages. Bullets and numbering are dropped.
enum CATListParser {
    static func parse(_ text: String) throws -> [ImportRow] {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { clean(String($0)) }
            .filter { !$0.isEmpty }
        guard lines.count <= CATImport.maxLines else {
            throw ImportFormatError(message: "That is more than \(CATImport.maxLines) lines. Paste one show per line.")
        }
        var names: [String] = []
        var tooLong: [ImportRow] = []
        for line in lines {
            if line.count > CATImport.maxNameLength {
                tooLong.append(CATImport.unsupported(
                    String(line.prefix(80)) + "…", reason: "Too long to be a show name. Put one show on each line."
                ))
            } else {
                names.append(line)
            }
        }
        return CATImport.rows(names.map { ($0, nil) }) + tooLong
    }

    /// `- Severance`, `• Severance`, `3. Severance`, `3) Severance` → `Severance`.
    static func clean(_ line: String) -> String {
        var value = line.trimmingCharacters(in: .whitespaces)
        if let match = value.prefixMatch(of: /(?:[-*•·]|\d{1,4}[.)])\s+/) {
            value = String(value[match.range.upperBound...])
        }
        return value.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: iCal (IMP-010)

/// The user's exported CAT calendar: one event per episode. Every event's `SUMMARY` names its show
/// and episode; the events collapse to one row per show, keeping one episode and its `DTSTART` day.
/// A summary with no readable show name is listed as unmatched, once.
enum CATCalendarParser {
    static func parse(_ text: String) throws -> [ImportRow] {
        guard isCalendar(text) else {
            throw ImportFormatError(message: "That is not a calendar file. Export the iCal file from CAT.")
        }
        var shows: [(name: String, airing: ImportAiring?)] = []
        var unreadable: [String] = []
        var summary: String?
        var day: String?
        for line in unfolded(text) {
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" {
                (summary, day) = (nil, nil)
            } else if upper == "END:VEVENT", let summary {
                if let name = showName(summary) {
                    let airing = day.flatMap { day in
                        episode(summary).map { ImportAiring(season: $0.season, episode: $0.episode, day: day) }
                    }
                    shows.append((name, airing))
                } else if !unreadable.contains(summary) {
                    unreadable.append(summary)
                }
            } else if let value = value(of: "SUMMARY", in: line) {
                // The event's own comes first; a later one belongs to a nested alarm.
                summary = summary ?? value
            } else if let value = value(of: "DTSTART", in: line) {
                day = day ?? calendarDay(value)
            }
        }
        return CATImport.rows(shows) + unreadable.map {
            CATImport.unsupported($0, reason: "Couldn't read a show name from “\($0)”.")
        }
    }

    static func isCalendar(_ text: String) -> Bool {
        text.drop { $0.isWhitespace || $0 == "\u{FEFF}" }.uppercased().hasPrefix("BEGIN:VCALENDAR")
    }

    /// RFC 5545 §3.1: a line starting with a space or tab continues the previous one.
    static func unfolded(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : raw[...]
            if let first = line.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += line.dropFirst()
            } else {
                lines.append(String(line))
            }
        }
        return lines
    }

    /// The unescaped value of `name` (parameters allowed: `SUMMARY;LANGUAGE=en:…`), or nil when the
    /// line is another property.
    static func value(of name: String, in line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let property = line[..<colon].split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
        guard property.uppercased() == name else { return nil }
        return unescaped(String(line[line.index(after: colon)...])).trimmingCharacters(in: .whitespaces)
    }

    /// RFC 5545 §3.3.11 TEXT escapes.
    static func unescaped(_ value: String) -> String {
        var result = ""
        var escaping = false
        for character in value {
            if escaping {
                result.append(character == "n" || character == "N" ? " " : character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// Where a summary's first `S02E03` or `2x03` starts, and its numbers.
    private struct EpisodePart {
        let start: String.Index
        let season: Int
        let episode: Int

        init?(_ summary: String) {
            guard let match = summary.firstMatch(of: /\b[Ss](\d{1,3})\s*[Ee](\d{1,4})\b|\b(\d{1,3})x(\d{1,4})\b/),
                  let season = (match.1 ?? match.3).flatMap({ Int($0) }),
                  let episode = (match.2 ?? match.4).flatMap({ Int($0) })
            else { return nil }
            (start, self.season, self.episode) = (match.range.lowerBound, season, episode)
        }
    }

    /// `Severance: S02E03 - Who Is Alive?`, `Severance - 2x03`, `Severance S02E03` → `Severance`.
    static func showName(_ summary: String) -> String? {
        guard let part = EpisodePart(summary) else { return nil }
        let name = summary[..<part.start].trimmingCharacters(in: CharacterSet(charactersIn: " \t:-–|"))
        return name.isEmpty ? nil : name
    }

    /// `S02E03` or `2x03` in a summary.
    static func episode(_ summary: String) -> (season: Int, episode: Int)? {
        EpisodePart(summary).map { ($0.season, $0.episode) }
    }

    /// `20261026T000000`, `20261026T000000Z` or `20261026` → `2026-10-26`. The time is dropped:
    /// it is CAT's local broadcast time, matched against date-only catalog air dates with a day's slack.
    static func calendarDay(_ value: String) -> String? {
        guard let match = value.prefixMatch(of: /(\d{4})(\d{2})(\d{2})/) else { return nil }
        return "\(match.1)-\(match.2)-\(match.3)"
    }
}

// MARK: The iCal link (IMP-010)

/// Reads the user's own CAT calendar from the link CAT gives them, once per import. This is the
/// only request Aaru makes to pogdesign.co.uk: no other page is read. The link holds the user's
/// CAT key, so it is never stored or logged; it lives in one request's local variables.
struct CATCalendarFeed: Sendable {
    let client: ProviderClient

    static let hosts: Set<String> = ["www.pogdesign.co.uk", "pogdesign.co.uk"]

    /// The calendar link, checked and pointed at `generate_ics` (CAT's `download_ics` answers as an
    /// attachment). Anything that is not a CAT calendar link is refused before a request is made.
    static func calendarURL(_ raw: String) throws -> URL {
        let message = "Paste the iCal link from CAT: it starts with https://www.pogdesign.co.uk/cat/."
        guard let components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), hosts.contains(host),
              components.port == nil, components.user == nil, components.password == nil,
              let match = components.path.wholeMatch(of: /\/cat\/(?:download|generate)_ics\/([A-Za-z0-9_-]{1,128})\/?/),
              let url = URL(string: "https://www.pogdesign.co.uk/cat/generate_ics/\(match.1)")
        else {
            throw AppError(
                status: .unprocessableContent, code: "validation_failed", message: message, details: ["url": message]
            )
        }
        return url
    }

    func calendar(at url: URL) async throws -> String {
        let notACalendar = AppError(
            status: .unprocessableContent, code: "validation_failed",
            message: "That link didn't return a CAT calendar. Copy the iCal link from CAT again.",
            details: ["url": "Not a CAT calendar."]
        )
        let body: Data
        do {
            body = try await client.data(OutboundRequest(url: url, headers: [("Accept", "text/calendar")]))
        } catch let error as ProviderError where error.kind == .notFound || error.kind == .unauthorized {
            throw notACalendar
        }
        guard body.count <= ImportService.maxUploadBytes else {
            throw AppError(
                status: .contentTooLarge, code: "file_too_large", message: "That calendar is larger than 5 MB."
            )
        }
        guard let text = String(bytes: body, encoding: .utf8), CATCalendarParser.isCalendar(text) else {
            throw notACalendar
        }
        return text
    }
}

// MARK: Requests

extension ImportService {
    /// A pasted CAT show list, or the CAT calendar file's text: a calendar is told apart by its first line.
    func createCATImport(userID: UserID, text: String) async throws -> ImportJob {
        let source: ImportSource = CATCalendarParser.isCalendar(text) ? .catICS : .catList
        return try await createCSVImport(userID: userID, source: source, filename: nil, text: text)
    }

    /// Reads the calendar from the user's CAT link now (one bounded request, like reading an
    /// upload) and queues the matching. The link is not kept.
    func createCATFeedImport(userID: UserID, link: String) async throws -> ImportJob {
        let url = try CATCalendarFeed.calendarURL(link)
        guard let catFeed else {
            throw AppError(
                status: .serviceUnavailable, code: "cat_unavailable",
                message: "Importing from a CAT link is not available right now. Upload the iCal file instead."
            )
        }
        let text = try await catFeed.calendar(at: url)
        return try await createCSVImport(userID: userID, source: .catICS, filename: nil, text: text)
    }
}
