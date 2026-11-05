import SwiftUI

/// iPhone's More tab (NAV-002, NAV-005): a list of the destinations the bar has no room for, each
/// pushed on this one stack. `AppRouter.morePath` holds it, so anything can open a destination.
/// Aaru's own list instead of iOS's generated More, whose navigation controller gave every page
/// with a stack a second bar and a second back button.
struct MoreScreen<Destination: View>: View {
    let destinations: [AppTab]
    /// Group mentions waiting, on Groups' row.
    let mentions: Int
    @ViewBuilder let destination: (AppTab) -> Destination

    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.morePath) {
            List(destinations) { item in
                Button {
                    router.tab = item
                } label: {
                    HStack {
                        Label(item.title, systemImage: item.symbol)
                            .foregroundStyle(Color(.ink))
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(.muted))
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .badge(item == .groups ? mentions : 0)
            }
            .paperPage()
            .navigationTitle("More")
            .accountButton()
            .navigationDestination(for: AppTab.self) { item in
                destination(item)
            }
        }
    }
}
