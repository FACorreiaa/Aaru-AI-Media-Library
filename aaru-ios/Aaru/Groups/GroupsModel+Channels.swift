import AaruAPI
import Foundation
import Observation

// Channels, mute and adding from an agent's card: GroupsModel's writes that are not about the
// group itself.

extension GroupsModel {
    // MARK: Channels

    /// A title channel takes its title's name when `name` is empty.
    func createChannel(
        in groupID: String, kind: ChannelKind = .text, name: String, topic: String,
        title: Components.Schemas.MediaRef? = nil
    ) async -> GroupChannel? {
        guard let api else { return nil }
        var created: GroupChannel?
        let name = name.trimmingCharacters(in: .whitespaces)
        await run("The channel was not created.") {
            switch try await api.createChannel(
                path: .init(groupId: groupID),
                body: .json(.init(
                    kind: kind, name: name.isEmpty ? nil : name, topic: topic.isEmpty ? nil : topic, title: title
                ))
            ) {
            case let .ok(response):
                created = try response.body.json
                await loadDetail(groupID)
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
        return created
    }

    /// An empty topic clears it.
    func updateChannel(_ channel: GroupChannel, in groupID: String, name: String, topic: String) async -> Bool {
        guard let api else { return false }
        return await run("The channel was not saved.") {
            switch try await api.updateChannel(
                path: .init(groupId: groupID, channelId: channel.id),
                body: .json(.init(name: name, topic: topic))
            ) {
            case .ok: await loadDetail(groupID)
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
    }

    func deleteChannel(_ channel: GroupChannel, in groupID: String) async -> Bool {
        guard let api else { return false }
        return await run("The channel was not deleted.") {
            switch try await api.deleteChannel(path: .init(groupId: groupID, channelId: channel.id)) {
            case .noContent: await loadDetail(groupID)
            case let .default(_, error): throw Failure(try? error.body.json)
            }
        }
    }
}

extension GroupSummary {
    /// One or two letters for the rail.
    var monogram: String {
        let words = name.split(whereSeparator: \.isWhitespace)
        if words.count >= 2, let first = words[0].first, let second = words[1].first {
            return "\(first)\(second)".uppercased()
        }
        return String(name.first ?? "?").uppercased()
    }
}

extension Components.Schemas.GroupRole {
    var manages: Bool {
        self != .member
    }
}

extension GroupsModel {
    /// A title Aaru pointed to in a group, added to this user's own library as Plan to …: the
    /// same journaled add as a tap anywhere else. Nil when it was added; else why not.
    func addToMyLibrary(_ title: TitleSummary) async -> String? {
        guard let api else { return "This build has no server configured." }
        do {
            switch try await api.addLibraryItem(body: .json(.init(mediaRef: title.mediaRef, status: .wishlist))) {
            case .ok: return nil
            case let .default(_, error): return (try? error.body.json.message) ?? "Not added."
            }
        } catch {
            return "Aaru could not reach the server."
        }
    }
}
