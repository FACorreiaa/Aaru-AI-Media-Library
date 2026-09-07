import Foundation
import Testing

@testable import AaruCore

@Suite
struct RatingTests {
    @Test(arguments: [1.0, 1.5, 5.0, 7.5, 10.0])
    func acceptsValuesOnTheHalfStepGrid(_ value: Double) throws {
        #expect(try Rating(value).value == value)
    }

    @Test(arguments: [0.0, 0.5, 10.5, 11.0, -3.0])
    func rejectsValuesOffTheScale(_ value: Double) {
        #expect(throws: ValidationError.ratingOutOfRange(value)) {
            try Rating(value)
        }
    }

    @Test(arguments: [1.2, 4.75, 9.9])
    func rejectsValuesOffTheHalfStepGrid(_ value: Double) {
        #expect(throws: ValidationError.ratingNotInHalfSteps(value)) {
            try Rating(value)
        }
    }

    @Test
    func decodingRejectsAnOutOfRangeRating() {
        let data = Data("11".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Rating.self, from: data)
        }
    }

    @Test
    func ratingsCompareByValue() throws {
        #expect(try Rating(6.5) < Rating(7.0))
        #expect(try Rating(10.0).description == "10")
        #expect(try Rating(8.5).description == "8.5")
    }
}
