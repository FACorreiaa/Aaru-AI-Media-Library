import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    func getEntitlement(_: Operations.GetEntitlement.Input) async throws -> Operations.GetEntitlement.Output {
        let userID = try currentUser()
        let state = try await services.billing.state(userID: userID)
        return .ok(.init(body: .json(.init(state, userID: userID))))
    }

    func recordAppleTransaction(
        _ input: Operations.RecordAppleTransaction.Input
    ) async throws -> Operations.RecordAppleTransaction.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let userID = try currentUser()
        let state = try await services.billing.recordPurchase(body.signedTransaction, userID: userID)
        return .ok(.init(body: .json(.init(state, userID: userID))))
    }

    func receiveAppleNotification(
        _ input: Operations.ReceiveAppleNotification.Input
    ) async throws -> Operations.ReceiveAppleNotification.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        try await services.billing.notify(body.signedPayload)
        return .ok(.init())
    }
}

extension Components.Schemas.Entitlement {
    init(_ state: BillingService.State, userID: UserID) {
        self.init(
            plus: state.plus != nil,
            productId: state.plus?.productID,
            expiresAt: state.plus?.expiresAt,
            sandbox: state.plus.map { $0.environment != "Production" },
            appAccountToken: userID.description,
            capture: .init(used: state.capturesUsed, limit: state.captureLimit, resetsAt: state.capturesResetAt)
        )
    }
}
