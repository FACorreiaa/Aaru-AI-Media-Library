import AaruCore
import Foundation

// MUS-004 · listening history files. Each parser keeps only what a listen stores and counts what
// it leaves out by rule; nothing else in the file is read into a row.

/// Plays read from a file or one page of a provider: the listens, and how many plays were left out.
struct ListenHistoryPage: Sendable, Equatable {
    var listens: [NewListen] = []
    var ignored = 0
}

/// Picks the parser for a JSON upload when the person did not say which service it came from.
enum ListenFileDetector {
    static func detect(_ data: Data) throws -> ImportSource {
        // Only ASCII keys are looked for: Latin-1 reads any cut through a character.
        let prefix = data.prefix(64 * 1024)
        let head = String(bytes: prefix, encoding: .utf8) ?? String(bytes: prefix, encoding: .isoLatin1) ?? ""
        let start = head.drop { $0.isWhitespace || $0 == "\u{FEFF}" }
        if start.hasPrefix("PK\u{03}\u{04}") {
            throw ImportFormatError(
                message: "This is a .zip file. Unzip it and add each Streaming_History_Audio file, one at a time."
            )
        }
        if head.contains("\"ms_played\""), head.contains("\"ts\"") {
            return .spotifyJSON
        }
        if head.contains("\"msPlayed\""), head.contains("\"endTime\"") {
            throw ImportFormatError(
                message: "This is Spotify's account data, which has only the last year without track ids. "
                    + "Ask Spotify for your Extended streaming history instead, then add its "
                    + "Streaming_History_Audio files."
            )
        }
        if head.contains("\"header\""), head.contains("\"time\""), head.contains("\"titleUrl\"") {
            return .youTubeTakeout
        }
        throw ImportFormatError(
            message: "Aaru reads Spotify's Extended streaming history and Google Takeout's YouTube "
                + "watch-history.json. For other sites, export a CSV."
        )
    }

    /// The JSON file's plays, read by the source's parser.
    static func parse(_ data: Data, source: ImportSource, now: Date) throws -> ListenHistoryPage {
        switch source {
        case .spotifyJSON: try SpotifyHistoryParser.parse(data, now: now)
        case .youTubeTakeout: try YouTubeTakeoutParser.parse(data, now: now)
        default: throw ImportFormatError(message: "That is not a listening history file.")
        }
    }

    /// A play time a live listen would accept: after Audioscrobbler began, not in the future.
    static func plausible(_ date: Date, now: Date) -> Bool {
        date >= ListenSubmission.earliest && date <= now.addingTimeInterval(ListenSubmission.futureSlack)
    }

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
}

/// One `Streaming_History_Audio_*.json` from Spotify's extended streaming history. `ts` is when a
/// play ended, so the listen starts `ms_played` before it: the moment a scrobbler would have sent.
/// Podcast episodes, audiobooks and plays under 30 s are left out. The file's IP address, country
/// and device are never read.
enum SpotifyHistoryParser {
    static let shortestPlayMs = 30000

    static func parse(_ data: Data, now: Date) throws -> ListenHistoryPage {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let plays = try? decoder.decode([SpotifyPlay].self, from: data) else {
            throw ImportFormatError(message: "That file is not a Spotify streaming history.")
        }
        var page = ListenHistoryPage()
        for play in plays {
            if let listen = listen(play, now: now) {
                page.listens.append(listen)
            } else {
                page.ignored += 1
            }
        }
        return page
    }

    private static func listen(_ play: SpotifyPlay, now: Date) -> NewListen? {
        guard play.episodeName == nil, play.audiobookTitle == nil, play.audiobookChapterTitle == nil,
              let played = play.msPlayed, played >= shortestPlayMs,
              let ended = ListenFileDetector.date(play.endedAt),
              let artist = ListenSubmission.text(play.artistName),
              let track = ListenSubmission.text(play.trackName)
        else { return nil }
        let started = ended.addingTimeInterval(-Double(played) / 1000)
        guard ListenFileDetector.plausible(started, now: now) else { return nil }
        let trackID = play.spotifyTrackUri.flatMap { uri in
            uri.hasPrefix("spotify:track:") ? String(uri.dropFirst("spotify:track:".count)) : nil
        }
        // Spotify gives the time heard, not the track's length: that is what Insights adds up.
        return NewListen(
            listenedAt: started, artist: artist, track: track,
            album: ListenSubmission.text(play.albumName), durationMs: played,
            spotifyID: ListenSubmission.text(trackID), musicService: "Spotify"
        )
    }
}

/// The fields Aaru reads from one Spotify play, each leniently: one odd value leaves that play
/// out, never the file. Keys arrive camel-cased from the decoder.
private struct SpotifyPlay: Decodable {
    var endedAt: String?
    var msPlayed: Int?
    var trackName: String?
    var artistName: String?
    var albumName: String?
    var spotifyTrackUri: String?
    var episodeName: String?
    var audiobookTitle: String?
    var audiobookChapterTitle: String?

    enum CodingKeys: String, CodingKey {
        case endedAt = "ts"
        case msPlayed, spotifyTrackUri, episodeName, audiobookTitle, audiobookChapterTitle
        // Spotify's own names, `master_metadata_…`.
        case trackName = "masterMetadataTrackName"
        case artistName = "masterMetadataAlbumArtistName"
        case albumName = "masterMetadataAlbumAlbumName"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String? {
            (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        endedAt = string(.endedAt)
        msPlayed = (try? container.decodeIfPresent(Int.self, forKey: .msPlayed)) ?? nil
        trackName = string(.trackName)
        artistName = string(.artistName)
        albumName = string(.albumName)
        spotifyTrackUri = string(.spotifyTrackUri)
        episodeName = string(.episodeName)
        audiobookTitle = string(.audiobookTitle)
        audiobookChapterTitle = string(.audiobookChapterTitle)
    }
}

/// Google Takeout's `watch-history.json` (decisions 2026-10-27): music only, nothing guessed. A
/// YouTube Music entry is music; a YouTube entry is music only from an auto-generated
/// "… - Topic" channel, whose name is the artist's and whose videos are named for the track.
/// Ads and every other video are left out. No length is known, so the 30 s window applies.
enum YouTubeTakeoutParser {
    static let topicSuffix = " - Topic"
    /// The English verb in front of every title. Other languages' is found from the file itself.
    static let knownVerbs = ["Watched "]
    /// Distinct titles needed before the words they all start with count as the verb.
    static let titlesForVerb = 10

    static func parse(_ data: Data, now: Date) throws -> ListenHistoryPage {
        guard let entries = try? JSONDecoder().decode([TakeoutEntry].self, from: data) else {
            throw ImportFormatError(message: "That file is not a YouTube watch history.")
        }
        var page = ListenHistoryPage()
        var music: [Candidate] = []
        for entry in entries {
            if let artist = artist(entry), let playedAt = ListenFileDetector.date(entry.time),
               ListenFileDetector.plausible(playedAt, now: now), entry.titleUrl?.hasPrefix("https://") == true
            {
                music.append(Candidate(entry: entry, artist: artist, playedAt: playedAt))
            } else {
                page.ignored += 1
            }
        }
        // Every title in the file shares the verb, music or not: the more kinds of title, the surer.
        let verb = fileVerb(entries.compactMap(\.title))
        for candidate in music {
            guard let track = track(candidate.entry.title, verb: verb) else {
                page.ignored += 1
                continue
            }
            page.listens.append(NewListen(
                listenedAt: candidate.playedAt, artist: candidate.artist, track: track,
                originURL: candidate.entry.titleUrl, musicService: candidate.entry.header
            ))
        }
        return page
    }

    /// An entry that is music, before its title is read.
    private struct Candidate {
        var entry: TakeoutEntry
        var artist: String
        var playedAt: Date
    }

    /// The artist when the entry is music, else nil.
    private static func artist(_ entry: TakeoutEntry) -> String? {
        guard entry.details?.contains(where: { $0.name == "From Google Ads" }) != true,
              let channel = entry.subtitles?.first?.name
        else { return nil }
        switch entry.header {
        case "YouTube Music":
            var name = channel.hasSuffix(topicSuffix) ? String(channel.dropLast(topicSuffix.count)) : channel
            if name.hasSuffix("VEVO"), name.count > 4 {
                name = String(name.dropLast(4))
            }
            return ListenSubmission.text(name)
        case "YouTube":
            guard channel.hasSuffix(topicSuffix) else { return nil }
            return ListenSubmission.text(String(channel.dropLast(topicSuffix.count)))
        default:
            return nil
        }
    }

    /// The words every title starts with, when the file is in a language Aaru has no verb for:
    /// what enough distinct titles share, cut back to a whole word. Titles that all begin with the
    /// same word would lose it too; a whole watch history, videos included, practically never does.
    static func fileVerb(_ titles: [String]) -> String? {
        let unknown = Set(titles.filter { title in !knownVerbs.contains { title.hasPrefix($0) } })
        guard unknown.count >= titlesForVerb, var prefix = unknown.first else { return nil }
        for title in unknown {
            prefix = String(prefix.commonPrefix(with: title))
        }
        guard let space = prefix.lastIndex(of: " ") else { return nil }
        return String(prefix[...space])
    }

    /// The track: the title without its verb. A removed video's title is only its link.
    static func track(_ title: String?, verb: String?) -> String? {
        guard let title,
              let prefix = (knownVerbs + [verb].compactMap(\.self)).first(where: { title.hasPrefix($0) })
        else { return nil }
        let name = String(title.dropFirst(prefix.count))
        guard !name.hasPrefix("https://"), !name.hasPrefix("http://") else { return nil }
        return ListenSubmission.text(name)
    }
}

/// One entry of Takeout's watch history, the fields Aaru reads, each leniently.
private struct TakeoutEntry: Decodable {
    struct Named: Decodable {
        var name: String?
    }

    var header: String?
    var title: String?
    var titleUrl: String?
    var subtitles: [Named]?
    var details: [Named]?
    var time: String?

    enum CodingKeys: String, CodingKey {
        case header, title, titleUrl, subtitles, details, time
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String? {
            (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        header = string(.header)
        title = string(.title)
        titleUrl = string(.titleUrl)
        time = string(.time)
        subtitles = (try? container.decodeIfPresent([Named].self, forKey: .subtitles)) ?? nil
        details = (try? container.decodeIfPresent([Named].self, forKey: .details)) ?? nil
    }
}
