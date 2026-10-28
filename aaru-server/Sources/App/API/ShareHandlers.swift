import aaruAPI
import AaruCore
import Foundation
import OpenAPIRuntime

extension APIImplementation {
    /// SHR-002 share links.
    func createShare(_ input: Operations.CreateShare.Input) async throws -> Operations.CreateShare.Output {
        guard case let .json(body) = input.body else { throw AppError.badRequest() }
        let request: ShareRequest
        switch body.target.kind {
        case .title:
            guard let ref = body.target.ref else { throw ShareService.invalid("Say which title to share.") }
            request = .title(MediaRef(ref))
        case .sportEvent:
            guard let id = body.target.id else { throw ShareService.invalid("Say which event to share.") }
            request = .sportEvent(id)
        case .concert:
            guard let id = body.target.id else { throw ShareService.invalid("Say which concert to share.") }
            request = .concert(id)
        }
        let share = try await services.shares.create(currentUser(), request, note: body.note)
        return .ok(.init(body: .json(.init(code: share.code, url: services.shares.url(share).absoluteString))))
    }

    func getSharePreview(_ input: Operations.GetSharePreview.Input) async throws -> Operations.GetSharePreview.Output {
        let context = try currentContext()
        let preview = try await services.shares.preview(
            code: input.path.code, viewer: context.userID, clientAddress: context.clientAddressForRateLimit
        )
        return .ok(.init(body: .json(.init(
            kind: .init(preview.share.target),
            unavailable: preview.unavailable,
            title: preview.title.map { .init($0) },
            sportEvent: preview.sportEvent.map { .init($0) },
            concert: preview.concert.map { .init($0) },
            from: preview.from.map { .init(user: .init($0.sender), note: $0.note) },
            libraryItemId: preview.viewerItem?.id.description,
            status: preview.viewerItem.map { .init($0.status) }
        ))))
    }
}

extension Components.Schemas.ShareKind {
    init(_ target: ShareTarget) {
        switch target {
        case .title: self = .title
        case .sportEvent: self = .sportEvent
        case .concert: self = .concert
        }
    }
}
