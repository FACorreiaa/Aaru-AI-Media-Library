import Foundation

/// Where a group alert opens (GRP-012): `aaru://group/{g}/channel/{c}` for the channel a mention
/// is in, `aaru://groups` for the Groups tab, where invites wait.
enum GroupLink: Equatable {
    case groups
    case channel(ChannelOpenRequest)

    init?(_ url: URL) {
        guard url.scheme == "aaru" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host() {
        case "groups" where parts.isEmpty:
            self = .groups
        case "group" where parts.count == 3 && parts[1] == "channel":
            self = .channel(ChannelOpenRequest(group: parts[0], channel: parts[2]))
        default:
            return nil
        }
    }
}
