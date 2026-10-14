#if DEBUG || BETA
    import AaruAPI
    import SwiftUI

    /// Debug and Beta only: which channel this is and whether its API answers.
    struct APIStatusLabel: View {
        let api: Client?
        @State private var status = "checking"

        var body: some View {
            Text("\(AppEnvironment.channel) · \(AppEnvironment.apiBaseURL?.host() ?? "no API") · \(status)")
                .task { status = await check() }
        }

        private func check() async -> String {
            guard let api else { return "not configured" }
            do {
                switch try await api.getHealth() {
                case .ok: return "API ok"
                case .serviceUnavailable: return "API degraded"
                case .default: return "API error"
                }
            } catch {
                return "API unreachable"
            }
        }
    }
#endif
