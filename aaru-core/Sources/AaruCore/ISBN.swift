/// ISBN normalization. Aaru stores every ISBN as ISBN-13 digits, so an ISBN-10 and
/// its ISBN-13 form are the same key.
public enum ISBN {
    /// The ISBN-13 for `raw`, or nil when it is not a valid ISBN-10 or ISBN-13.
    ///
    /// Tolerates hyphens, spaces, and Goodreads' `="…"` wrapping.
    public static func normalize(_ raw: String) -> String? {
        let cleaned = raw.uppercased().filter { $0.isNumber || $0 == "X" }
        switch cleaned.count {
        case 10:
            guard isValidISBN10(cleaned) else { return nil }
            let core = "978" + cleaned.prefix(9)
            return core + String(checkDigit13(core))
        case 13:
            guard !cleaned.contains("X"), checkDigit13(String(cleaned.prefix(12))) == cleaned.last?.wholeNumberValue
            else { return nil }
            return cleaned
        default:
            return nil
        }
    }

    private static func isValidISBN10(_ digits: String) -> Bool {
        var sum = 0
        for (index, character) in digits.enumerated() {
            let value: Int
            if character == "X", index == 9 {
                value = 10
            } else if let digit = character.wholeNumberValue {
                value = digit
            } else {
                return false
            }
            sum += value * (10 - index)
        }
        return sum % 11 == 0
    }

    private static func checkDigit13(_ twelve: String) -> Int {
        let sum = twelve.enumerated().reduce(0) { total, pair in
            total + (pair.element.wholeNumberValue ?? 0) * (pair.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return (10 - sum % 10) % 10
    }
}
