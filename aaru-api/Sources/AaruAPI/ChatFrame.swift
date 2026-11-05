import Foundation

/// One frame of the assistant's server-sent event stream (ASK-009).
public enum ChatFrame: Sendable {
    case status(String)
    case delta(String)
    case components(Components.Schemas.ChatComponentsFrame)
    case done(turnID: String)
    case error(code: Components.Schemas.ChatErrorFrame.CodePayload, message: String)
}

/// Turns the raw bytes of a chat turn's `text/event-stream` body into frames.
///
/// Splits on `\n` at byte level and decodes UTF-8 only from a whole line, so a character
/// split across chunks stays intact. Heartbeat comments, unknown events and malformed JSON
/// are skipped without disturbing later frames.
public struct ChatFrameParser: Sendable {
    private var buffer: [UInt8] = []
    private var event: String?
    private var data: [String] = []

    public init() {}

    public mutating func consume(_ bytes: some Sequence<UInt8>) -> [ChatFrame] {
        buffer.append(contentsOf: bytes)
        var frames: [ChatFrame] = []
        var start = 0
        while let newline = buffer[start...].firstIndex(of: 0x0A) {
            var end = newline
            if end > start, buffer[end - 1] == 0x0D {
                end -= 1
            }
            let line = String(decoding: buffer[start ..< end], as: UTF8.self)
            start = newline + 1
            if let frame = handle(line) {
                frames.append(frame)
            }
        }
        buffer.removeSubrange(0 ..< start)
        return frames
    }

    private mutating func handle(_ line: String) -> ChatFrame? {
        if line.isEmpty {
            defer { event = nil; data = [] }
            guard let event, !data.isEmpty else { return nil }
            return Self.frame(event: event, data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") {
            return nil
        }
        let name: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            name = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") {
                value = value.dropFirst()
            }
        } else {
            name = line[...]
            value = ""
        }
        switch name {
        case "event": event = String(value)
        case "data": data.append(String(value))
        default: break
        }
        return nil
    }

    private static func frame(event: String, data: String) -> ChatFrame? {
        let payload = Data(data.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            switch event {
            case "status":
                return try .status(decoder.decode(Components.Schemas.ChatTextFrame.self, from: payload).text)
            case "delta":
                return try .delta(decoder.decode(Components.Schemas.ChatTextFrame.self, from: payload).text)
            case "components":
                return try .components(decoder.decode(Components.Schemas.ChatComponentsFrame.self, from: payload))
            case "done":
                return try .done(turnID: decoder.decode(Components.Schemas.ChatDoneFrame.self, from: payload).turnId)
            case "error":
                let frame = try decoder.decode(Components.Schemas.ChatErrorFrame.self, from: payload)
                return .error(code: frame.code, message: frame.message)
            default:
                return nil
            }
        } catch {
            return nil
        }
    }
}
