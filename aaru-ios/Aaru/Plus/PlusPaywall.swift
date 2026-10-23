import StoreKit
import SwiftUI

/// BIL-004 · the paywall: what Plus is, its prices from the App Store, Restore Purchases, and the
/// terms and privacy links App Review asks for. Opened by the composer past the free month's
/// captures, and from Settings → Account.
struct PlusPaywall: View {
    let plus: PlusModel
    /// Why it opened (the server's quota line), shown under the title.
    var reason: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Aaru Plus")
                            .font(.aaruDisplay(.largeTitle, weight: .semibold))
                            .foregroundStyle(Color(.ink))
                        if let reason {
                            Text(reason).foregroundStyle(Color(.muted))
                        }
                    }
                    feature(
                        "text.viewfinder", "Captures without a monthly limit",
                        "Paste a list, send a link or a screenshot, and approve what Aaru found. Up to 30 a day."
                    )
                    feature(
                        "heart", "Keeps Aaru independent",
                        "Plus is how Aaru is paid for. Your library stays private and stays yours."
                    )
                    offers
                    footer
                }
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background { FieldBackground() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await plus.load() }
        }
    }

    @ViewBuilder private var offers: some View {
        if plus.isPlus {
            Label(activeLine, systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color(.accent))
        } else if plus.products.isEmpty {
            Text("Plus is not on sale in this build yet.")
                .foregroundStyle(Color(.muted))
        } else {
            VStack(spacing: 10) {
                ForEach(plus.products, id: \.id) { product in
                    Button {
                        Task {
                            if await plus.buy(product) {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Text(product.displayName)
                            Spacer()
                            Text(product.priceLine).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(plus.busy)
                }
            }
        }
        Button("Restore Purchases") { Task { await plus.restore() } }
            .disabled(plus.busy)
        if let problem = plus.problem {
            Text(problem).font(.footnote).foregroundStyle(Color(.danger))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                "Plus renews automatically at the price shown until you cancel, at least a day before the "
                    + "period ends, in your Apple Account's subscriptions. Payment is charged to your Apple Account."
            )
            HStack(spacing: 16) {
                if let terms = PlusModel.termsURL {
                    Link("Terms of Use", destination: terms)
                }
                if let privacy = PlusModel.privacyURL {
                    Link("Privacy Policy", destination: privacy)
                }
            }
        }
        .font(.footnote)
        .foregroundStyle(Color(.muted))
    }

    private var activeLine: String {
        guard let expires = plus.entitlement?.expiresAt else { return "Plus is active" }
        return "Plus is active · renews \(expires.formatted(date: .abbreviated, time: .omitted))"
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color(.accent))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Color(.ink))
                Text(detail).font(.subheadline).foregroundStyle(Color(.muted))
            }
        }
    }
}
