/// One screen of the first run on the Apple apps: a step of AaruCore's list, or the AI sharing
/// question (PRV-002), which sits before the alerts screen, or last when there is none.
enum OnboardingScreen: Hashable {
    case step(OnboardingStep)
    case aiSharing
}

extension OnboardingModel {
    /// The steps as screens, with AI sharing among them when this account has not answered.
    var screens: [OnboardingScreen] {
        var list = steps.map(OnboardingScreen.step)
        if asksAISharing {
            list.insert(.aiSharing, at: list.firstIndex(of: .step(.notifications)) ?? list.endIndex)
        }
        return list
    }

    func screen(after current: OnboardingScreen) -> OnboardingScreen? {
        let list = screens
        guard let index = list.firstIndex(of: current) else { return nil }
        return list.indices.contains(index + 1) ? list[index + 1] : nil
    }

    func screen(before current: OnboardingScreen) -> OnboardingScreen? {
        let list = screens
        guard let index = list.firstIndex(of: current), index > 0 else { return nil }
        return list[index - 1]
    }
}
