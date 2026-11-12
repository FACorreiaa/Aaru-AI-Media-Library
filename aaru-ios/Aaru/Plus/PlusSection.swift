import StoreKit
import SwiftUI

/// Settings → Account: Plus, or the way to it (BIL-004). While the App Store has no product to
/// sell there is nothing to offer, so a free account sees no section at all (BIL-005).
struct PlusSection: View {
    let plus: PlusModel
    @State private var showsPaywall = false
    #if os(iOS)
        @State private var managing = false
    #endif

    var body: some View {
        if plus.isPlus || !plus.products.isEmpty {
            Section("Aaru Plus") {
                if plus.isPlus {
                    LabeledContent("Aaru Plus", value: String(localized: "Active"))
                    #if os(iOS)
                        Button("Manage subscription") { managing = true }
                    #endif
                } else {
                    LabeledContent("Aaru Plus", value: String(localized: "Not subscribed"))
                    Button("Get Aaru Plus") { showsPaywall = true }
                }
            }
            .sheet(isPresented: $showsPaywall) { PlusPaywall(plus: plus) }
            #if os(iOS)
                .manageSubscriptionsSheet(isPresented: $managing)
            #endif
        }
    }
}
