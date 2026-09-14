import XCTest
@testable import TheReadingHoard

final class MockRecommendationImporterTests: XCTestCase {
    func testSupportsInstagramReelURLs() {
        XCTAssertTrue(MockRecommendationImporter.isSupported(URL(string: "https://www.instagram.com/reel/ABC123/")!))
        XCTAssertTrue(MockRecommendationImporter.isSupported(URL(string: "https://instagram.com/reels/ABC123/")!))
    }

    func testRejectsOtherInstagramPagesAndHosts() {
        XCTAssertFalse(MockRecommendationImporter.isSupported(URL(string: "https://www.instagram.com/p/ABC123/")!))
        XCTAssertFalse(MockRecommendationImporter.isSupported(URL(string: "https://example.com/reel/ABC123/")!))
    }
}
