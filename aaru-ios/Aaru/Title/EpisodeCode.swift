import AaruAPI

/// One way to write an episode on Apple (UX-045): "S1 · E8" everywhere, "S01E05" only in the
/// week grid's cells (DESIGN.md §14).
enum EpisodeCode {
    /// "S1 · E8".
    static func short(season: Int, number: Int) -> String {
        "S\(season) · E\(number)"
    }

    /// "S1 · E8", spelled for group surfaces (`season`, `episode`).
    static func text(season: Int, episode: Int) -> String {
        short(season: season, number: episode)
    }

    /// "S01E05", the week cell's dense code.
    static func padded(season: Int, number: Int) -> String {
        "S" + twoDigits(season) + "E" + twoDigits(number)
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 && value >= 0 ? "0\(value)" : String(value)
    }
}

/// The catalog's show status in words (UX-047), shared by the title room and list rows.
enum ShowStatusLabel {
    static func label(_ raw: String) -> String {
        switch raw {
        case "upcoming": "Upcoming"
        case "returning": "Returning series"
        case "ended": "Ended"
        case "canceled": "Canceled"
        default: raw.capitalized
        }
    }
}

extension Components.Schemas.TitleDetail.StatusPayload {
    var label: String {
        ShowStatusLabel.label(rawValue)
    }
}

extension Components.Schemas.ListItem.ShowStatusPayload {
    var label: String {
        ShowStatusLabel.label(rawValue)
    }
}
