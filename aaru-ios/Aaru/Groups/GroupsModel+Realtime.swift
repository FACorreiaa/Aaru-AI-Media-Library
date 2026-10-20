import AaruAPI
import Foundation

extension GroupsModel {
    // MARK: Realtime (GRP-006)

    /// Applies socket events until the caller is cancelled. The open channel follows its own
    /// messages; this keeps the list, counts, details and invites current.
    func follow() async {
        guard let realtime else { return }
        for await event in realtime.events() {
            await apply(event)
        }
    }

    func apply(_ event: RealtimeEvent) async {
        switch event._type {
        case .ready:
            await catchUp()
        case .message_created, .message_updated, .message_deleted, .read:
            if let groupID = event.groupId {
                refreshCountsSoon(groupID)
            }
        case .group_updated:
            if let groupID = event.groupId {
                await groupChanged(groupID)
            }
        case .group_removed:
            if let groupID = event.groupId {
                forgetGroup(groupID)
            }
        case .invites_changed:
            await loadInvites()
        case .typing, .shelf_updated, .watch_updated, .watch_reaction:
            // The open channel's own views follow these.
            break
        }
    }

    /// Anything could have changed while the socket was down.
    private func catchUp() async {
        await load()
        for groupID in details.keys {
            await loadDetail(groupID)
        }
    }

    private func groupChanged(_ groupID: String) async {
        if groups.contains(where: { $0.id == groupID }) {
            await loadDetail(groupID)
        } else {
            // Joined from another device.
            await load()
        }
    }

    /// One count refresh per group per second, however many messages arrive.
    private func refreshCountsSoon(_ groupID: String) {
        pendingCounts[groupID]?.cancel()
        pendingCounts[groupID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await self?.loadDetail(groupID)
            self?.pendingCounts[groupID] = nil
        }
    }
}
