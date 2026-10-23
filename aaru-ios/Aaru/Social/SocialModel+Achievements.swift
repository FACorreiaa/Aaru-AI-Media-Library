import AaruAPI
import Foundation

/// GAM-005's two switches, apart from `SocialModel.swift` to keep it under the file limit. Each
/// flips at once and back if the server says no; the PUT names only the field it changes (and
/// the required library switch), so an older build never resets the other.
extension SocialModel {
    func setShowAchievements(_ show: Bool) async {
        let previous = showAchievements
        showAchievements = show
        if await !saveSettings(.init(shareLibraryWithFriends: shareLibrary, showAchievementsToFriends: show)) {
            showAchievements = previous
        }
    }

    /// Joining or leaving the weekly friends board. True when saved.
    @discardableResult
    func setLeaderboardOptIn(_ join: Bool) async -> Bool {
        let previous = leaderboardOptIn
        leaderboardOptIn = join
        let saved = await saveSettings(.init(shareLibraryWithFriends: shareLibrary, leaderboardOptIn: join))
        if !saved {
            leaderboardOptIn = previous
        }
        return saved
    }

    private func saveSettings(_ settings: Components.Schemas.SocialSettings) async -> Bool {
        guard let api else { return false }
        problem = nil
        do {
            switch try await api.updateSocialSettings(body: .json(settings)) {
            case .ok:
                return true
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Your setting was not saved."
            }
        } catch {
            problem = "Your setting was not saved. Aaru could not reach the server."
        }
        return false
    }
}
