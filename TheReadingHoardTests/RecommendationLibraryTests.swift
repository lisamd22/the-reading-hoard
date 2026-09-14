import XCTest
@testable import TheReadingHoard

final class RecommendationLibraryTests: XCTestCase {

    private func book(_ title: String,
                      _ author: String? = nil,
                      appleTrackID: Int? = nil,
                      isbn13: String? = nil,
                      status: BookRecommendation.ReadingStatus = .toBeRead,
                      sources: [ImportSource] = []) -> BookRecommendation {
        BookRecommendation(title: title,
                           author: author,
                           recommendationSummary: "summary",
                           sources: sources,
                           appleTrackID: appleTrackID,
                           isbn13: isbn13,
                           status: status)
    }

    private func source(_ platform: ImportPlatform, _ id: String) -> ImportSource {
        ImportSource(platform: platform, itemID: id)
    }

    // MARK: - The eight documented dedup breaks

    func testAmpersandAndSpelledAndAreTheSameBook() {
        // "Butcher & Blackbird" is a real BookTok title that broke the old key.
        let a = book("Butcher & Blackbird", "Brynne Weaver")
        let b = book("Butcher and Blackbird", "Brynne Weaver")
        XCTAssertEqual(RecommendationLibrary.relation(a, b), .same)
    }

    func testSubtitleSuffixIsIgnored() {
        let a = book("Fourth Wing", "Rebecca Yarros")
        let b = book("Fourth Wing (The Empyrean, 1)", "Rebecca Yarros")
        XCTAssertEqual(RecommendationLibrary.relation(a, b), .same)
    }

    func testSeriesPrefixWithColonIsIgnored() {
        let a = book("Zodiac Academy: The Awakening", "Caroline Peckham")
        let b = book("Zodiac Academy", "Caroline Peckham")
        XCTAssertEqual(RecommendationLibrary.relation(a, b), .same)
    }

    func testLeadingArticleIsIgnored() {
        let a = book("The Hurricane Wars", "Thea Guanzon")
        let b = book("Hurricane Wars", "Thea Guanzon")
        XCTAssertEqual(RecommendationLibrary.relation(a, b), .same)
    }

    func testInvertedAuthorNameStillMatches() {
        let a = book("Iron Flame", "Rebecca Yarros")
        let b = book("Iron Flame", "Yarros, Rebecca")
        XCTAssertEqual(RecommendationLibrary.relation(a, b), .same)
    }

    func testMissingAuthorDoesNotBlockAMatch() {
        // A title card routinely names a book and no author.
        let a = book("Quicksilver", "Callie Hart")
        let b = book("Quicksilver", nil)
        XCTAssertEqual(RecommendationLibrary.relation(a, b), .same)
    }

    func testDiacriticsAndCaseAreIgnored() {
        let a = book("Café Amor", "José Ruiz")
        let b = book("cafe amor", "jose ruiz")
        XCTAssertEqual(RecommendationLibrary.relation(a, b), .same)
    }

    func testTurkishLocaleDoesNotBreakTitlesContainingI() {
        // Under a Turkish locale, "I".lowercased() is a dotless i and every title
        // containing an I stops matching itself. TitleNormalizer pins en_US_POSIX.
        XCTAssertEqual(TitleNormalizer.key("IRON FLAME"), TitleNormalizer.key("Iron Flame"))
        XCTAssertEqual(TitleNormalizer.key("INTO THE LIGHT"), "intothelight")
    }

    // MARK: - Distinctness

    func testDifferentAuthorsMeanDifferentBooksDespiteIdenticalTitle() {
        // "Haunting Adeline" genuinely exists twice by different authors.
        let a = book("Haunting Adeline", "H. D. Carlton")
        let b = book("Haunting Adeline", "Ashley G. Wilson")
        XCTAssertEqual(RecommendationLibrary.relation(a, b), .distinct)
    }

    func testDifferentAppleTrackIDsAreDistinctEvenWithSameTitle() {
        let a = book("Iron Flame", "Rebecca Yarros", appleTrackID: 1)
        let b = book("Iron Flame", "Rebecca Yarros", appleTrackID: 2)
        XCTAssertEqual(RecommendationLibrary.relation(a, b), .distinct)
    }

    func testMatchingAppleTrackIDWinsOverDifferingTitles() {
        let a = book("Iron Flame", "Rebecca Yarros", appleTrackID: 42)
        let b = book("Iron Flame - Version francaise", "Rebecca Yarros", appleTrackID: 42)
        XCTAssertEqual(RecommendationLibrary.relation(a, b), .same)
    }

    func testUnrelatedBooksAreDistinct() {
        XCTAssertEqual(RecommendationLibrary.relation(book("Book One"), book("Book Two")), .distinct)
    }

    // MARK: - Merging behaviour

    func testMergingAccumulatesSourcesInsteadOfDiscardingDuplicates() {
        // The old merge dropped the incoming duplicate entirely, throwing away the
        // "recommended in 3 reels" signal the product is built on.
        let existing = book("Fourth Wing", "Rebecca Yarros", sources: [source(.tiktok, "1")])
        let again = book("fourth wing", "rebecca yarros", sources: [source(.instagram, "2")])

        let result = RecommendationLibrary.merging(current: [existing], incoming: [again])

        XCTAssertEqual(result.library.count, 1)
        XCTAssertEqual(result.library[0].sources.count, 2)
        XCTAssertEqual(result.merged.count, 1)
    }

    func testMergingFillsInAMissingAuthor() {
        let existing = book("Quicksilver", nil)
        let incoming = book("Quicksilver", "Callie Hart")
        let result = RecommendationLibrary.merging(current: [existing], incoming: [incoming])
        XCTAssertEqual(result.library[0].author, "Callie Hart")
    }

    func testMergingNeverDowngradesReadingStatus() {
        let existing = book("Iron Flame", "Rebecca Yarros", status: .finished)
        let incoming = book("Iron Flame", "Rebecca Yarros", status: .toBeRead)
        let result = RecommendationLibrary.merging(current: [existing], incoming: [incoming])
        XCTAssertEqual(result.library[0].status, .finished)
    }

    func testMergingAppendsDifferentBooks() {
        let first = book("Book One", "Author")
        let second = book("Book Two", "Author")
        let result = RecommendationLibrary.merging(current: [first], incoming: [second])
        XCTAssertEqual(result.library.count, 2)
        XCTAssertTrue(result.merged.isEmpty)
    }

    func testNearIdenticalTitlesWithNoAuthorAreSurfacedForReviewNotSilentlyMerged() {
        let a = book("The Serpent and the Wings of Night", nil)
        let b = book("The Serpent and the Wings of Nigth", nil)   // OCR-style typo
        let result = RecommendationLibrary.merging(current: [a], incoming: [b])
        XCTAssertEqual(result.needsUserDecision.count, 1)
        XCTAssertEqual(result.library.count, 1, "ambiguous matches must not be appended blindly")
    }

    // MARK: - Edit-distance guard

    func testMeasuredOCRTypoStillMatches() {
        // Measured against the live iTunes API: "Quicksiiver" alone returns the
        // correct book at rank 1, so we must treat it as the same title.
        let a = book("Quicksilver", "Callie Hart")
        let b = book("Quicksiiver", "Callie Hart")
        XCTAssertEqual(RecommendationLibrary.relation(a, b), .same)
    }

    func testShortTitlesSharingAPrefixStayDistinct() {
        // Jaro-Winkler's prefix bonus scores "bookone"/"booktwo" at 0.886 — over the
        // ambiguity threshold — despite three edits. The edit budget catches it.
        XCTAssertEqual(RecommendationLibrary.relation(book("Book One"), book("Book Two")), .distinct)
        XCTAssertEqual(RecommendationLibrary.relation(book("Powerless"), book("Reckless")), .distinct)
        XCTAssertEqual(
            RecommendationLibrary.relation(book("Iron Flame", "R Yarros"), book("Iron Widow", "X Zhao")),
            .distinct
        )
    }

    func testEditBudgetScalesWithLength() {
        XCTAssertEqual(RecommendationLibrary.editBudget(forLength: 5), 1)
        XCTAssertEqual(RecommendationLibrary.editBudget(forLength: 28), 5)
    }

    // MARK: - Platform detection

    func testPlatformDetectionCoversMeasuredHosts() {
        XCTAssertEqual(ImportPlatform.detect(host: "vm.tiktok.com"), .tiktok)
        XCTAssertEqual(ImportPlatform.detect(host: "youtu.be"), .youtube)
        XCTAssertEqual(ImportPlatform.detect(host: "pin.it"), .pinterest)
        // pin.it resolves through a locale host — measured 2026-09-01.
        XCTAssertEqual(ImportPlatform.detect(host: "de.pinterest.com"), .pinterest)
        XCTAssertEqual(ImportPlatform.detect(host: "example.com"), .unknown)
    }

    // MARK: - Contract guards

    func testReadingStatusRawValuesAreUnchanged() {
        // BookCard renders status.rawValue.uppercased(); changing these yields
        // "TOBEREAD" and silently rewrites the on-disk encoding.
        XCTAssertEqual(BookRecommendation.ReadingStatus.toBeRead.rawValue, "To be read")
        XCTAssertEqual(BookRecommendation.ReadingStatus.reading.rawValue, "Reading")
        XCTAssertEqual(BookRecommendation.ReadingStatus.finished.rawValue, "Finished")
    }

    func testAuthorSurnameExtraction() {
        XCTAssertEqual(TitleNormalizer.authorSurname("Rebecca Yarros"), "yarros")
        XCTAssertEqual(TitleNormalizer.authorSurname("Yarros, Rebecca"), "yarros")
        XCTAssertEqual(TitleNormalizer.authorSurname("Sarah J. Maas"), "maas")
        XCTAssertNil(TitleNormalizer.authorSurname(nil))
        XCTAssertNil(TitleNormalizer.authorSurname("   "))
    }
}
