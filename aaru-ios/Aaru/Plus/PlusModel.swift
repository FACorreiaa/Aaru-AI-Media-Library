import AaruAPI
import Foundation
import Observation
import StoreKit

typealias Entitlement = Components.Schemas.Entitlement

/// BIL-004 · Aaru Plus on the App Store (StoreKit 2). The server keeps the entitlement: each
/// transaction this device sees (a purchase, a restore, a renewal while the app runs) goes to
/// `/v1/billing/apple/transactions`, and what Plus unlocks is read back from `/v1/me/entitlement`,
/// which the web reads too.
@MainActor
@Observable
final class PlusModel {
    /// The subscription group "Aaru Plus" in App Store Connect.
    static let productIDs = ["aaru_plus_monthly", "aaru_plus_yearly"]
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    static let privacyURL = URL(string: "https://aaruapp.com/privacy")

    private(set) var entitlement: Entitlement?
    /// Cheapest first. Empty until the App Store answers, or when the products are not set up.
    private(set) var products: [Product] = []
    private(set) var busy = false
    var problem: String?

    @ObservationIgnored private let api: Client?
    @ObservationIgnored private var listening = false

    init(api: Client?) {
        self.api = api
    }

    var isPlus: Bool {
        entitlement?.plus == true
    }

    /// Signing out: the next account reads its own.
    func reset() {
        entitlement = nil
        problem = nil
    }

    func load() async {
        await refresh()
        if products.isEmpty {
            products = await (try? Product.products(for: Self.productIDs))?.sorted { $0.price < $1.price } ?? []
        }
    }

    func refresh() async {
        guard let api, case let .ok(response) = try? await api.getEntitlement(),
              let fresh = try? response.body.json
        else { return }
        entitlement = fresh
    }

    /// True when Plus is active afterwards. The purchase carries this account's token, so the
    /// server can tie Apple's later notifications to it.
    func buy(_ product: Product) async -> Bool {
        busy = true
        problem = nil
        defer { busy = false }
        if entitlement == nil {
            await refresh()
        }
        guard let token = entitlement.flatMap({ UUID(uuidString: $0.appAccountToken) }) else {
            problem = "Aaru could not reach the server. Try again in a moment."
            return false
        }
        do {
            switch try await product.purchase(options: [.appAccountToken(token)]) {
            case let .success(result):
                await settle(result)
            case .pending:
                problem = "The purchase is waiting for approval. Plus starts when it goes through."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            problem = "The App Store could not complete the purchase."
        }
        return isPlus
    }

    func restore() async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
        } catch {
            problem = "The App Store could not be reached."
            return
        }
        for await result in Transaction.currentEntitlements {
            await settle(result)
        }
        await refresh()
        if !isPlus, problem == nil {
            problem = "No Aaru Plus purchase was found for this Apple Account."
        }
    }

    /// Transactions that arrive while the app runs: renewals, Ask to Buy, a purchase on another
    /// device. Started once, when the signed-in app appears.
    func listen() async {
        guard !listening else { return }
        listening = true
        for await result in Transaction.updates {
            await settle(result)
        }
    }

    /// Sends a verified transaction to the server, then finishes it. A transaction the server
    /// refuses (another account's) is finished too, so it is not offered again at every launch;
    /// one that never reached the server is kept for the next try.
    private func settle(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result, let api else { return }
        do {
            switch try await api
                .recordAppleTransaction(body: .json(.init(signedTransaction: result.jwsRepresentation)))
            {
            case let .ok(response):
                entitlement = try response.body.json
            case let .default(_, error):
                problem = (try? error.body.json.message) ?? "Aaru could not confirm the purchase."
            }
            await transaction.finish()
        } catch {
            problem = "Aaru could not reach the server. The purchase is kept; Aaru tries again next time."
        }
    }
}

extension Product {
    /// "€3.99 a month", "€29.99 a year".
    var priceLine: String {
        guard let period = subscription?.subscriptionPeriod else { return displayPrice }
        let unit = switch period.unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "period"
        }
        return period.value == 1 ? "\(displayPrice) a \(unit)" : "\(displayPrice) every \(period.value) \(unit)s"
    }
}
