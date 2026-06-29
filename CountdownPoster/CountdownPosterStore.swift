import Foundation
import Combine

@MainActor
final class CountdownPosterStore: ObservableObject {
    @Published var isGoogleConnected = false
    @Published var settings = AppSettings()
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var analyses: [UUID: EventAnalysis] = [:]
    @Published private(set) var recommendations: [UUID: [RecommendedPlace]] = [:]
    @Published private(set) var posters: [UUID: [CountdownStage: Poster]] = [:]
    @Published private(set) var hiddenEventKeys: Set<String> = []
    @Published private(set) var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var statusMessage: String?

    private let configuration: APIConfiguration
    private let usesSimulatorDemo: Bool
    private let demoCalendarService = DemoGoogleCalendarService()
    private let ruleAnalyzer = RuleBasedEventAnalyzer()
    private let localPlaceService = LocalPlaceRecommendationService()
    private let posterFactory = PosterFactory()

    private let googleOAuthClient: GoogleOAuthClient?
    private let googleCalendarService: GoogleCalendarAPIService?
    private let openAIAnalyzer: OpenAIEventAnalyzer?
    private let openAIPosterCopyGenerator: OpenAIPosterCopyGenerator?
    private let openAIImageGenerator: OpenAIImageGenerator?
    private let googlePlacesService: GooglePlacesRecommendationService?

    convenience init() {
        self.init(configuration: APIConfigurationLoader.load())
    }

    init(configuration: APIConfiguration) {
        self.configuration = configuration
        self.usesSimulatorDemo = Self.isSimulatorDemoEnabled

        if configuration.hasGoogleOAuth {
            let oauthClient = GoogleOAuthClient(configuration: configuration)
            self.googleOAuthClient = oauthClient
            self.googleCalendarService = GoogleCalendarAPIService(oauthClient: oauthClient)
            self.isGoogleConnected = oauthClient.hasStoredCredentials
        } else {
            self.googleOAuthClient = nil
            self.googleCalendarService = nil
        }

        self.openAIAnalyzer = configuration.hasOpenAI ? OpenAIEventAnalyzer(configuration: configuration) : nil
        self.openAIPosterCopyGenerator = configuration.hasOpenAI ? OpenAIPosterCopyGenerator(configuration: configuration) : nil
        self.openAIImageGenerator = configuration.hasOpenAI ? OpenAIImageGenerator(configuration: configuration) : nil
        self.googlePlacesService = configuration.hasGooglePlaces ? GooglePlacesRecommendationService(apiKey: configuration.googlePlacesAPIKey) : nil

        if usesSimulatorDemo {
            syncCalendar()
        } else {
            restorePersistedState()
            if isGoogleConnected {
                syncCalendar()
            }
        }
    }

    var visibleEvents: [CalendarEvent] {
        events.filter { !hiddenEventKeys.contains($0.cacheKey) }
    }

    var shouldShowSignIn: Bool {
        !usesSimulatorDemo && !isGoogleConnected
    }

    var apiStatusSummary: String {
        var parts: [String] = []
        parts.append(usesSimulatorDemo ? "Simulatorデモ" : (isGoogleConnected ? "Google Calendar" : "デモ予定"))
        parts.append(usesSimulatorDemo ? "ローカル判定" : (configuration.hasOpenAI ? "OpenAI" : "ローカル判定"))
        parts.append(usesSimulatorDemo ? "デモ画像" : (configuration.hasGooglePlaces ? "Places画像" : "ローカル候補"))
        return parts.joined(separator: " / ")
    }

    var isRealAPIConfigured: Bool {
        configuration.hasGoogleOAuth || configuration.hasOpenAI || configuration.hasGooglePlaces
    }

    func signInWithGoogle() {
        Task {
            await connectGoogleAndSync()
        }
    }

    func syncCalendar() {
        Task {
            await syncCalendarNow()
        }
    }

    func analysis(for event: CalendarEvent) -> EventAnalysis {
        analyses[event.id] ?? ruleAnalyzer.analyze(event)
    }

    func places(for event: CalendarEvent) -> [RecommendedPlace] {
        recommendations[event.id] ?? []
    }

    func currentPoster(for event: CalendarEvent) -> Poster? {
        poster(for: event, stage: CountdownStage.milestone(for: event.daysUntil()))
    }

    func poster(for event: CalendarEvent, stage: CountdownStage) -> Poster? {
        posters[event.id]?[stage]
    }

    func togglePlace(_ place: RecommendedPlace, for event: CalendarEvent) {
        guard var places = recommendations[event.id],
              let index = places.firstIndex(where: { $0.id == place.id }),
              let analysis = analyses[event.id]
        else {
            return
        }

        places[index].selectedForPoster.toggle()
        recommendations[event.id] = places
        savePersistedState()

        Task {
            posters[event.id] = await makePosters(for: event, analysis: analysis, places: places)
            savePersistedState()
        }
    }

    func regenerateBackground(for event: CalendarEvent, stage: CountdownStage) {
        Task {
            await regenerateBackgroundNow(for: event, stage: stage)
        }
    }

    func regenerateCopy(for event: CalendarEvent, stage: CountdownStage) {
        guard let analysis = analyses[event.id],
              let places = recommendations[event.id]
        else {
            return
        }

        Task {
            await regenerateCopyNow(for: event, analysis: analysis, places: places, stage: stage)
        }
    }

    func hide(_ event: CalendarEvent) {
        hiddenEventKeys.insert(event.cacheKey)
        savePersistedState()
    }

    private func connectGoogleAndSync() async {
        guard let googleOAuthClient else {
            statusMessage = "Secrets.plist に GoogleOAuthClientID と GoogleOAuthRedirectScheme を設定してください。"
            return
        }

        do {
            _ = try await googleOAuthClient.signIn()
            isGoogleConnected = true
            statusMessage = "Googleカレンダーに接続しました。"
            await syncCalendarNow()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func syncCalendarNow() async {
        guard !isSyncing else {
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let fetchedEvents = try await fetchEvents()
            let cachedAnalyses = analysesByEventKey()
            let cachedRecommendations = recommendationsByEventKey()
            let cachedPosters = postersByEventKey()

            var nextAnalyses: [UUID: EventAnalysis] = [:]
            var nextRecommendations: [UUID: [RecommendedPlace]] = [:]
            var nextPosters: [UUID: [CountdownStage: Poster]] = [:]

            for event in fetchedEvents {
                let key = event.cacheKey
                let analysis: EventAnalysis
                if let cachedAnalysis = cachedAnalyses[key] {
                    analysis = cachedAnalysis
                } else {
                    analysis = await analyze(event)
                }

                let places: [RecommendedPlace]
                if let cachedPlaces = cachedRecommendations[key],
                   uniquePlaces(cachedPlaces).count >= CountdownStage.allCases.count {
                    places = cachedPlaces
                } else {
                    places = await recommendedPlaces(for: event, analysis: analysis)
                }

                let cachedStagePosters = cachedPosters[key]
                nextAnalyses[event.id] = analysis
                nextRecommendations[event.id] = places
                nextPosters[event.id] = await makePosters(
                    for: event,
                    analysis: analysis,
                    places: places,
                    cachedPosters: cachedStagePosters
                )
            }

            events = fetchedEvents
            analyses = nextAnalyses
            recommendations = nextRecommendations
            posters = nextPosters
            lastSyncDate = Date()
            statusMessage = "同期しました: \(apiStatusSummary)"
            savePersistedState()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func fetchEvents() async throws -> [CalendarEvent] {
        if usesSimulatorDemo {
            return try await demoCalendarService.fetchUpcomingEvents(
                daysAhead: settings.lookAheadDays,
                limit: settings.targetEventCount
            )
        }

        if isGoogleConnected, let googleCalendarService {
            do {
                return try await googleCalendarService.fetchUpcomingEvents(
                    daysAhead: settings.lookAheadDays,
                    limit: settings.targetEventCount
                )
            } catch {
                isGoogleConnected = false
                throw error
            }
        }

        throw APIError(message: "Googleカレンダーにサインインしてください。")
    }

    private func analyze(_ event: CalendarEvent) async -> EventAnalysis {
        if usesSimulatorDemo {
            return ruleAnalyzer.analyze(event)
        }

        guard let openAIAnalyzer else {
            return ruleAnalyzer.analyze(event)
        }

        do {
            return try await openAIAnalyzer.analyze(event)
        } catch {
            statusMessage = "OpenAI判定に失敗したためローカル判定に戻しました: \(error.localizedDescription)"
            return ruleAnalyzer.analyze(event)
        }
    }

    private func recommendedPlaces(for event: CalendarEvent, analysis: EventAnalysis) async -> [RecommendedPlace] {
        if analysis.recommendationMode == .tokyoDefault,
           !settings.useTokyoDefaultRecommendations {
            return []
        }

        let localPlaces = localPlaceService.recommendations(for: event, analysis: analysis)

        if usesSimulatorDemo {
            return Array(uniquePlaces(localPlaces).prefix(CountdownStage.allCases.count))
        }

        if let googlePlacesService {
            do {
                let places = try await googlePlacesService.recommendations(for: event, analysis: analysis)
                let merged = uniquePlaces(places + localPlaces)
                if !merged.isEmpty {
                    return Array(merged.prefix(CountdownStage.allCases.count))
                }
            } catch {
                statusMessage = "Places取得に失敗したためローカル候補に戻しました: \(error.localizedDescription)"
            }
        }

        return Array(uniquePlaces(localPlaces).prefix(CountdownStage.allCases.count))
    }

    private func regenerateBackgroundNow(for event: CalendarEvent, stage: CountdownStage) async {
        guard settings.useAIBackground else {
            statusMessage = "AI背景生成がオフです。"
            return
        }

        guard let analysis = analyses[event.id],
              let places = recommendations[event.id]
        else {
            return
        }

        var poster = posterFactory.makePoster(
            for: event,
            analysis: analysis,
            recommendations: places,
            stage: stage,
            styleSeed: Int.random(in: 0...9999)
        )
        poster = await applyAICopyIfAvailable(to: poster)

        if let openAIImageGenerator {
            do {
                statusMessage = "AI背景を生成中..."
                poster.backgroundImageURL = try await openAIImageGenerator.generateBackgroundImage(for: poster)
                statusMessage = "AI背景を生成しました。"
            } catch {
                poster.backgroundPrompt = "\(analysis.backgroundPrompt), variant \(poster.styleSeed), no text"
                statusMessage = "AI背景生成に失敗したためテンプレート背景を更新しました: \(error.localizedDescription)"
            }
        } else {
            poster.backgroundPrompt = "\(analysis.backgroundPrompt), variant \(poster.styleSeed), no text"
            statusMessage = "OpenAIAPIKey がないためテンプレート背景を更新しました。"
        }

        posters[event.id]?[stage] = poster
        savePersistedState()
    }

    private func regenerateCopyNow(
        for event: CalendarEvent,
        analysis: EventAnalysis,
        places: [RecommendedPlace],
        stage: CountdownStage
    ) async {
        let selected = places.filter(\.selectedForPoster)
        var poster = posterFactory.makePoster(
            for: event,
            analysis: analysis,
            recommendations: selected.isEmpty ? places : selected,
            stage: stage,
            styleSeed: posters[event.id]?[stage]?.styleSeed ?? Int.random(in: 0...9999)
        )
        poster.createdAt = Date()
        poster.backgroundImageURL = posters[event.id]?[stage]?.backgroundImageURL
        poster = await applyAICopyIfAvailable(to: poster)
        posters[event.id]?[stage] = poster
        savePersistedState()
    }

    private func makePosters(
        for event: CalendarEvent,
        analysis: EventAnalysis,
        places: [RecommendedPlace],
        cachedPosters: [CountdownStage: Poster]? = nil
    ) async -> [CountdownStage: Poster] {
        let existingPosters = posters[event.id]
        let generated = posterFactory.makePosters(for: event, analysis: analysis, recommendations: places)
        var prepared: [CountdownStage: Poster] = [:]

        for stage in CountdownStage.allCases {
            guard var poster = generated[stage] else {
                continue
            }

            if var cached = cachedPosters?[poster.countdownStage],
               shouldReuseCachedPoster(cached) {
                cached.event = event
                cached.analysis = analysis
                prepared[stage] = cached
                continue
            }

            if let cached = cachedPosters?[poster.countdownStage],
               let cachedBackground = cached.backgroundImageURL {
                poster.backgroundImageURL = cachedBackground
            }

            if poster.backgroundImageURL == nil {
                poster.backgroundImageURL = existingPosters?[poster.countdownStage]?.backgroundImageURL
            }

            if !settings.useAIBackground {
                poster.styleSeed = 0
                poster.backgroundPrompt = "Template background only, no generated image"
            }

            poster = await applyAICopyIfAvailable(to: poster)
            poster = await generateBackgroundIfNeeded(for: poster)
            prepared[stage] = poster
        }

        return prepared
    }

    private func shouldReuseCachedPoster(_ poster: Poster) -> Bool {
        let staleTerms = ["終わ", "予定後", "ごほうび", "余韻", "終了後"]
        let combinedCopy = "\(poster.mainCopy)\n\(poster.subCopy)"
        if !poster.templateType.hasPrefix("venue-v5") {
            return false
        }
        if poster.textDesign == nil {
            return false
        }
        if openAIPosterCopyGenerator != nil, poster.copyGeneratedByAI != true {
            return false
        }
        return poster.recommendedPlaces.count == 1 && !staleTerms.contains { combinedCopy.contains($0) }
    }

    private func applyAICopyIfAvailable(to poster: Poster) async -> Poster {
        if usesSimulatorDemo {
            return poster
        }

        guard let openAIPosterCopyGenerator else {
            return poster
        }

        do {
            let generatedCopy = try await openAIPosterCopyGenerator.generateCopy(for: poster)
            var updated = poster
            updated.mainCopy = sanitizedCopy(generatedCopy.mainCopy, fallback: poster.mainCopy, poster: poster)
            updated.subCopy = sanitizedCopy(generatedCopy.subCopy, fallback: poster.subCopy, poster: poster)
            updated.textDesign = sanitizedTextDesign(generatedCopy.textDesign, fallback: poster)
            updated.copyGeneratedByAI = true
            return updated
        } catch {
            statusMessage = "AI文章生成に失敗したためローカル文にしました: \(error.localizedDescription)"
            return poster
        }
    }

    private func generateBackgroundIfNeeded(for poster: Poster) async -> Poster {
        if usesSimulatorDemo {
            return poster
        }

        guard settings.useAIBackground,
              poster.backgroundImageURL == nil,
              let openAIImageGenerator
        else {
            return poster
        }

        do {
            var updated = poster
            updated.backgroundImageURL = try await openAIImageGenerator.generateBackgroundImage(for: poster)
            return updated
        } catch {
            statusMessage = "AI背景生成に失敗したため写真/テンプレート背景に戻しました: \(error.localizedDescription)"
            return poster
        }
    }

    private func sanitizedCopy(_ copy: String, fallback: String, poster: Poster) -> String {
        var sanitized = copy.trimmingCharacters(in: .whitespacesAndNewlines)
        var forbiddenTerms = [
            poster.event.title,
            poster.event.locationText
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isBlank }

        if let detectedArea = poster.analysis.detectedArea?.nonBlank,
           detectedArea != "東京",
           detectedArea.count > 2 {
            forbiddenTerms.append(detectedArea)
        }

        for term in forbiddenTerms {
            sanitized = sanitized.replacingOccurrences(of: term, with: "")
        }

        sanitized = sanitized
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        return sanitized.isBlank ? fallback : sanitized
    }

    private func sanitizedTextDesign(_ design: PosterTextDesign, fallback poster: Poster) -> PosterTextDesign {
        let fallbackDesign = poster.textDesign ?? PosterTextDesign(
            countdownText: poster.countdownStage.compactTitle,
            placeText: poster.recommendedPlaces.first?.placeName ?? "おすすめスポット",
            mainCopy: poster.mainCopy,
            subCopy: poster.subCopy,
            layoutVariant: fallbackLayoutVariant(for: poster.countdownStage),
            fontMood: .boldPop
        )

        return PosterTextDesign(
            countdownText: sanitizedCountdown(design.countdownText, fallback: fallbackDesign.countdownText, stage: poster.countdownStage),
            placeText: sanitizedCopy(design.placeText, fallback: fallbackDesign.placeText, poster: poster),
            mainCopy: sanitizedCopy(design.mainCopy, fallback: fallbackDesign.mainCopy, poster: poster),
            subCopy: sanitizedCopy(design.subCopy, fallback: fallbackDesign.subCopy, poster: poster),
            layoutVariant: design.layoutVariant,
            fontMood: design.fontMood
        )
    }

    private func sanitizedCountdown(_ text: String, fallback: String, stage: CountdownStage) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isBlank else {
            return fallback
        }

        if stage == .today {
            return trimmed.contains("今日") ? trimmed : "今日"
        }

        return trimmed.contains(String(stage.rawValue)) ? trimmed : fallback
    }

    private func fallbackLayoutVariant(for stage: CountdownStage) -> PosterLayoutVariant {
        switch stage {
        case .sevenDays:
            return .bottomLeft
        case .fiveDays:
            return .topLeft
        case .threeDays:
            return .splitBands
        case .twoDays:
            return .topRight
        case .oneDay:
            return .centerStack
        case .today:
            return .bottomCenter
        }
    }

    private func uniquePlaces(_ places: [RecommendedPlace]) -> [RecommendedPlace] {
        var seen = Set<String>()
        var unique: [RecommendedPlace] = []

        for place in places {
            let key = (place.externalID ?? place.placeName)
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isBlank, !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            unique.append(place)
        }

        return unique
    }

    private func restorePersistedState() {
        guard let state = LocalPosterCache.load() else {
            return
        }

        events = state.events
        lastSyncDate = state.lastSyncDate
        hiddenEventKeys = Set(state.hiddenEventKeys)

        var restoredAnalyses: [UUID: EventAnalysis] = [:]
        var restoredRecommendations: [UUID: [RecommendedPlace]] = [:]
        var restoredPosters: [UUID: [CountdownStage: Poster]] = [:]

        for event in state.events {
            let key = event.cacheKey
            restoredAnalyses[event.id] = state.analyses[key]
            restoredRecommendations[event.id] = state.recommendations[key]
            if let cachedPosters = state.posters[key] {
                restoredPosters[event.id] = Dictionary(
                    uniqueKeysWithValues: cachedPosters.map { ($0.countdownStage, $0) }
                )
            }
        }

        analyses = restoredAnalyses.compactMapValues { $0 }
        recommendations = restoredRecommendations.compactMapValues { $0 }
        posters = restoredPosters
    }

    private func savePersistedState() {
        LocalPosterCache.save(
            PersistedPosterState(
                events: events,
                analyses: analysesByEventKey(),
                recommendations: recommendationsByEventKey(),
                posters: postersByEventKey().mapValues { stageMap in
                    CountdownStage.allCases.compactMap { stageMap[$0] }
                },
                hiddenEventKeys: Array(hiddenEventKeys),
                lastSyncDate: lastSyncDate
            )
        )
    }

    private func analysesByEventKey() -> [String: EventAnalysis] {
        Dictionary(uniqueKeysWithValues: events.compactMap { event in
            guard let analysis = analyses[event.id] else {
                return nil
            }
            return (event.cacheKey, analysis)
        })
    }

    private func recommendationsByEventKey() -> [String: [RecommendedPlace]] {
        Dictionary(uniqueKeysWithValues: events.map { event in
            (event.cacheKey, recommendations[event.id] ?? [])
        })
    }

    private func postersByEventKey() -> [String: [CountdownStage: Poster]] {
        Dictionary(uniqueKeysWithValues: events.map { event in
            (event.cacheKey, posters[event.id] ?? [:])
        })
    }

    private static var isSimulatorDemoEnabled: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
