import Foundation
import CoreGraphics

enum EventType: String, CaseIterable, Codable, Identifiable {
    case travel
    case meal
    case workOrSchool
    case liveEvent
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .travel:
            "旅行"
        case .meal:
            "ご飯・カフェ"
        case .workOrSchool:
            "仕事・学校"
        case .liveEvent:
            "イベント"
        case .unknown:
            "判定不能"
        }
    }

    var symbolName: String {
        switch self {
        case .travel:
            "map"
        case .meal:
            "fork.knife"
        case .workOrSchool:
            "briefcase"
        case .liveEvent:
            "ticket"
        case .unknown:
            "sparkles"
        }
    }
}

enum RecommendationMode: String, Codable {
    case locationBased
    case areaBased
    case tokyoDefault
    case afterEventReward

    var label: String {
        switch self {
        case .locationBased:
            "場所周辺"
        case .areaBased:
            "地域推定"
        case .tokyoDefault:
            "東京デフォルト"
        case .afterEventReward:
            "おすすめスポット"
        }
    }
}

enum CountdownStage: Int, CaseIterable, Codable, Identifiable, Hashable {
    case sevenDays = 7
    case fiveDays = 5
    case threeDays = 3
    case twoDays = 2
    case oneDay = 1
    case today = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sevenDays:
            "あと7日"
        case .fiveDays:
            "あと5日"
        case .threeDays:
            "あと3日"
        case .twoDays:
            "あと2日"
        case .oneDay:
            "明日"
        case .today:
            "本日開催"
        }
    }

    var compactTitle: String {
        switch self {
        case .sevenDays:
            "あと7日"
        case .fiveDays:
            "あと5日"
        case .threeDays:
            "あと3日"
        case .twoDays:
            "あと2日"
        case .oneDay:
            "明日"
        case .today:
            "今日"
        }
    }

    static func milestone(for daysUntilEvent: Int) -> CountdownStage {
        if daysUntilEvent <= 0 {
            return .today
        }
        if daysUntilEvent <= 1 {
            return .oneDay
        }
        if daysUntilEvent <= 2 {
            return .twoDays
        }
        if daysUntilEvent <= 3 {
            return .threeDays
        }
        if daysUntilEvent <= 5 {
            return .fiveDays
        }
        return .sevenDays
    }
}

enum SNSAspectRatio: String, CaseIterable, Codable, Identifiable {
    case story
    case square
    case wallpaper
    case inApp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .story:
            "9:16"
        case .square:
            "1:1"
        case .wallpaper:
            "19.5:9"
        case .inApp:
            "3:4"
        }
    }

    var ratio: CGFloat {
        switch self {
        case .story:
            9.0 / 16.0
        case .square:
            1
        case .wallpaper:
            9.0 / 19.5
        case .inApp:
            3.0 / 4.0
        }
    }
}

enum PosterLayoutVariant: String, CaseIterable, Codable {
    case bottomLeft
    case topLeft
    case centerStack
    case splitBands
    case bottomCenter
    case topRight
}

enum PosterFontMood: String, CaseIterable, Codable {
    case boldPop
    case softEditorial
    case compactLabel
}

struct PosterTextDesign: Equatable, Codable {
    var countdownText: String
    var placeText: String
    var mainCopy: String
    var subCopy: String
    var layoutVariant: PosterLayoutVariant
    var fontMood: PosterFontMood
}

struct AppSettings: Equatable, Codable {
    var calendarName = "Google Calendar"
    var lookAheadDays = 30
    var targetEventCount = 8
    var useTokyoDefaultRecommendations = true
    var useAIBackground = true
    var snsAspectRatio: SNSAspectRatio = .story
    var notificationsEnabled = true
}

struct CalendarEvent: Identifiable, Hashable, Codable {
    let id: UUID
    var googleEventID: String?
    var title: String
    var detail: String
    var startAt: Date
    var endAt: Date
    var locationText: String?
    var nextEventStartAt: Date?

    init(
        id: UUID = UUID(),
        googleEventID: String? = nil,
        title: String,
        detail: String = "",
        startAt: Date,
        endAt: Date,
        locationText: String? = nil,
        nextEventStartAt: Date? = nil
    ) {
        self.id = id
        self.googleEventID = googleEventID
        self.title = title
        self.detail = detail
        self.startAt = startAt
        self.endAt = endAt
        self.locationText = locationText
        self.nextEventStartAt = nextEventStartAt
    }

    func daysUntil(from now: Date = Date(), calendar: Calendar = .current) -> Int {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfEvent = calendar.startOfDay(for: startAt)
        return max(0, calendar.dateComponents([.day], from: startOfToday, to: startOfEvent).day ?? 0)
    }

    func freeTimeAfterEventMinutes() -> Int? {
        guard let nextEventStartAt else {
            return nil
        }
        return max(0, Int(nextEventStartAt.timeIntervalSince(endAt) / 60))
    }

    var cacheKey: String {
        googleEventID ?? id.uuidString
    }
}

struct EventAnalysis: Equatable, Codable {
    var eventType: EventType
    var confidence: Double
    var detectedArea: String?
    var hasSpecificLocation: Bool
    var recommendationMode: RecommendationMode
    var recommendationKeywords: [String]
    var posterTone: String
    var backgroundPrompt: String
    var freeTimeAfterEventMinutes: Int?

    var displayArea: String {
        detectedArea ?? "東京"
    }
}

struct RecommendedPlace: Identifiable, Hashable, Codable {
    let id: UUID
    var externalID: String?
    var placeName: String
    var area: String
    var category: String
    var address: String
    var rating: Double?
    var mapsURL: URL
    var imageURL: URL?
    var imageAttribution: String?
    var aiReason: String
    var selectedForPoster: Bool

    init(
        id: UUID = UUID(),
        externalID: String? = nil,
        placeName: String,
        area: String,
        category: String,
        address: String,
        rating: Double? = nil,
        mapsURL: URL,
        imageURL: URL? = nil,
        imageAttribution: String? = nil,
        aiReason: String,
        selectedForPoster: Bool = true
    ) {
        self.id = id
        self.externalID = externalID
        self.placeName = placeName
        self.area = area
        self.category = category
        self.address = address
        self.rating = rating
        self.mapsURL = mapsURL
        self.imageURL = imageURL
        self.imageAttribution = imageAttribution
        self.aiReason = aiReason
        self.selectedForPoster = selectedForPoster
    }
}

struct Poster: Identifiable, Codable {
    let id: UUID
    var event: CalendarEvent
    var analysis: EventAnalysis
    var countdownStage: CountdownStage
    var mainCopy: String
    var subCopy: String
    var templateType: String
    var backgroundPrompt: String
    var backgroundImageURL: URL?
    var recommendedPlaces: [RecommendedPlace]
    var createdAt: Date
    var styleSeed: Int
    var copyGeneratedByAI: Bool?
    var textDesign: PosterTextDesign?

    init(
        id: UUID = UUID(),
        event: CalendarEvent,
        analysis: EventAnalysis,
        countdownStage: CountdownStage,
        mainCopy: String,
        subCopy: String,
        templateType: String,
        backgroundPrompt: String,
        backgroundImageURL: URL? = nil,
        recommendedPlaces: [RecommendedPlace],
        createdAt: Date = Date(),
        styleSeed: Int = 0,
        copyGeneratedByAI: Bool? = nil,
        textDesign: PosterTextDesign? = nil
    ) {
        self.id = id
        self.event = event
        self.analysis = analysis
        self.countdownStage = countdownStage
        self.mainCopy = mainCopy
        self.subCopy = subCopy
        self.templateType = templateType
        self.backgroundPrompt = backgroundPrompt
        self.backgroundImageURL = backgroundImageURL
        self.recommendedPlaces = recommendedPlaces
        self.createdAt = createdAt
        self.styleSeed = styleSeed
        self.copyGeneratedByAI = copyGeneratedByAI
        self.textDesign = textDesign
    }
}
