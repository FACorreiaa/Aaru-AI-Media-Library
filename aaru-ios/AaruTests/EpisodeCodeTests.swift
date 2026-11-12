import Testing
@testable import Aaru

/// How an episode is written (UX-045): "S1 · E8" everywhere, "S01E05" in the week grid.
struct EpisodeCodeTests {
    @Test func theShortCodeNamesSeasonAndEpisode() {
        #expect(EpisodeCode.short(season: 1, number: 8) == "S1 · E8")
        #expect(EpisodeCode.text(season: 12, episode: 3) == "S12 · E3")
    }

    /// A long-running show passes episode 1,000; a code is an identifier, so its digits are
    /// never grouped the way a count's are.
    @Test func aCodeNeverGroupsItsDigits() {
        #expect(EpisodeCode.short(season: 1, number: 1100) == "S1 · E1100")
        #expect(EpisodeCode.padded(season: 2024, number: 1100) == "S2024E1100")
    }

    @Test func thePaddedCodeHasTwoDigitsAtLeast() {
        #expect(EpisodeCode.padded(season: 1, number: 5) == "S01E05")
        #expect(EpisodeCode.padded(season: 10, number: 12) == "S10E12")
        // Specials are season 0.
        #expect(EpisodeCode.padded(season: 0, number: 0) == "S00E00")
    }

    @Test func aShowStatusReadsInWords() {
        #expect(ShowStatusLabel.label("returning") == "Returning series")
        #expect(ShowStatusLabel.label("ended") == "Ended")
        // A status the app does not know yet still reads as a word.
        #expect(ShowStatusLabel.label("hiatus") == "Hiatus")
    }
}
