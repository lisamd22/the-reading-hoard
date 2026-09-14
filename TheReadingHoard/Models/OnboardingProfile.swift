import Foundation

struct OnboardingProfile: Equatable {
    enum Genre: String, CaseIterable, Identifiable {
        case fantasy = "Fantasy"
        case romance = "Romance"
        case mystery = "Mystery"
        case scienceFiction = "Science fiction"
        case historical = "Historical"
        case literary = "Literary"
        case horror = "Horror"
        case nonfiction = "Nonfiction"

        var id: String { rawValue }
    }

    enum Trope: String, CaseIterable, Identifiable {
        case foundFamily = "Found family"
        case enemiesToLovers = "Enemies to lovers"
        case cozy = "Cozy"
        case darkAcademia = "Dark academia"
        case dragons = "Dragons"
        case slowBurn = "Slow burn"

        var id: String { rawValue }
    }

    enum ReadingFormat: String, CaseIterable, Identifiable {
        case print = "Print"
        case ebook = "E-book"
        case audio = "Audiobook"

        var id: String { rawValue }
    }

    var genres: Set<Genre>
    var tropes: Set<Trope>
    var formats: Set<ReadingFormat>

    static let empty = OnboardingProfile(genres: [], tropes: [], formats: [])
}
