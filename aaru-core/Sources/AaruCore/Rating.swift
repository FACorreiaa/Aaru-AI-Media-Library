/// A user rating on Aaru's single, fixed scale: 1–10 in 0.5 steps.
///
/// One scale, kept stable. Do not introduce a second one — clients that display
/// stars divide by two.
public struct Rating: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// The only accepted range.
    public static let scale: ClosedRange<Double> = 1.0...10.0
    /// The only accepted increment.
    public static let step: Double = 0.5

    public let value: Double

    /// Creates a rating, rejecting values off the scale or off the half-step grid.
    public init(_ value: Double) throws {
        guard Rating.scale.contains(value) else {
            throw ValidationError.ratingOutOfRange(value)
        }
        // Compare in half-step units to keep binary floating point out of the test.
        let steps = (value / Rating.step).rounded()
        guard abs(steps * Rating.step - value) < 0.0001 else {
            throw ValidationError.ratingNotInHalfSteps(value)
        }
        self.value = steps * Rating.step
    }

    public static func < (lhs: Rating, rhs: Rating) -> Bool { lhs.value < rhs.value }

    public var description: String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

extension Rating: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Double.self)
        do {
            try self.init(value)
        } catch let error as ValidationError {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: error.description
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
