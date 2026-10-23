import StoreKit
import SwiftUI

/// Settings → Account: Plus, or the free month's captures and the way to Plus (BIL-004).
struct PlusSection: View {
    let plus: PlusModel
    @State private var showsPaywall = false
    #if os(iOS)
        @State private var managing = false
    #endif

    var body: some View {
        Section {
            if plus.isPlus {
                LabeledContent("Aaru Plus", value: "Active")
                #if os(iOS)
                    Button("Manage subscription") { managing = true }
                #endif
            } else {
                LabeledContent("Aaru Plus", value: "Not subscribed")
                if let capture = plus.entitlement?.capture, let limit = capture.limit {
                    LabeledContent("Captures this month", value: "\(capture.used) of \(limit)")
                }
                Button("Get Aaru Plus") { showsPaywall = true }
            }
        } header: {
            Text("Aaru Plus")
        } footer: {
            Text(plus.isPlus ? "Captures without a monthly limit." : "Plus lifts the monthly limit on captures.")
        }
        .task { await plus.refresh() }
        .sheet(isPresented: $showsPaywall) { PlusPaywall(plus: plus) }
        #if os(iOS)
            .manageSubscriptionsSheet(isPresented: $managing)
        #endif
    }
}
