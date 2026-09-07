import Foundation

/// Marker for the entity an `AaruID` points at.
///
/// Phantom scopes keep a `TitleID` from being passed where a `UserID` is expected,
/// while every identifier still encodes as a plain UUID string on the wire.
public protocol IDScope: Sendable {}

/// A UUID identifier scoped to one kind of entity.
public struct AaruID<Scope: IDScope>: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    /// Parses a UUID string. Returns `nil` when the string is not a UUID.
    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.rawValue = uuid
    }

    public var description: String { rawValue.uuidString }
}

extension AaruID: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum TitleScope: IDScope {}
public enum LibraryItemScope: IDScope {}
public enum UserScope: IDScope {}
public enum ListScope: IDScope {}
public enum ImportJobScope: IDScope {}

public typealias TitleID = AaruID<TitleScope>
public typealias LibraryItemID = AaruID<LibraryItemScope>
public typealias UserID = AaruID<UserScope>
public typealias ListID = AaruID<ListScope>
public typealias ImportJobID = AaruID<ImportJobScope>
