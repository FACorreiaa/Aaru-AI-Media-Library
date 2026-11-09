import AaruAPI
import Foundation

/// Whether the signed-in account still has its first run to do (ONB-001), as RootView routes on
/// it: checking (one `GET /v1/me`), pending (the flow) or done (the app).
enum OnboardingGate: Equatable {
    case checking, pending, done

    /// Set once the server said this account is done, so later launches open straight into the
    /// app without asking. Cleared on sign-out: the next account asks again.
    private static let doneKey = "onboarding.done"
    /// How long the launch waits for `Me` before opening the app anyway.
    private static let patience: Duration = .seconds(5)

    static var isKnownDone: Bool {
        UserDefaults.standard.bool(forKey: doneKey)
    }

    static func rememberDone() {
        UserDefaults.standard.set(true, forKey: doneKey)
    }

    static func forget() {
        UserDefaults.standard.removeObject(forKey: doneKey)
    }

    /// `Me.onboardingPending`: false when the server leaves it out (built before ONB-001), nil
    /// when the call failed or took longer than `patience`.
    static func fetchPending(_ api: Client) async -> Bool? {
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                guard case let .ok(response)? = try? await api.getMe(),
                      let account = try? response.body.json
                else { return nil }
                return account.onboardingPending ?? false
            }
            group.addTask {
                try? await Task.sleep(for: Self.patience)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
