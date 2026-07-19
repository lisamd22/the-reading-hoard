import XCTest
@testable import TheReadingHoard

final class RecommendationLibraryTests: XCTestCase {
    func testMergingIgnoresCaseAndPunctuationForDuplicates() {
        let existing = BookRecommendation(
            title: "A Wizard's Guide to Defensive Baking",
            author: "T. Kingfisher",
            recommendationSummary: "Existing"
        )
        let duplicate = BookRecommendation(
            title: "a wizards guide to defensive baking",
            author: "t kingfisher",
            recommendationSummary: "Duplicate"
        )

        let result = RecommendationLibrary.merging(current: [existing], new: [duplicate])

        XCTAssertEqual(result, [existing])
    }

    func testMergingAppendsDifferentBooks() {
        let first = BookRecommendation(title: "Book One", author: "Author", recommendationSummary: "First")
        let second = BookRecommendation(title: "Book Two", author: "Author", recommendationSummary: "Second")

        let result = RecommendationLibrary.merging(current: [first], new: [second])

        XCTAssertEqual(result, [first, second])
    }
}
