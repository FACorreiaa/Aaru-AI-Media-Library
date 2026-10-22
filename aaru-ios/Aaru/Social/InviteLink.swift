import Foundation

/// A friend invite (SOC-002): `https://aaruapp.com/i/{code}`. The app claims that path as a
/// universal link, so tapping an invite in Messages opens here instead of the browser.
struct InviteLink: Identifiable, Equatable {
    let code: String

    var id: String {
        code
    }

    static let hosts: Set<String> = ["aaruapp.com", "www.aaruapp.com", "beta.aaruapp.com"]

    init?(_ url: URL) {
        guard url.scheme == "https", let host = url.host(), Self.hosts.contains(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "i",
              parts[1].wholeMatch(of: /[A-Za-z0-9]{1,32}/) != nil
        else { return nil }
        code = parts[1]
    }
}
