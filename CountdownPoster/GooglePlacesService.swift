import Foundation

struct GooglePlacesRecommendationService {
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func recommendations(for event: CalendarEvent, analysis: EventAnalysis) async throws -> [RecommendedPlace] {
        guard !apiKey.isBlank else {
            throw APIError(message: "GooglePlacesAPIKey がありません。")
        }

        let area = analysis.displayArea
        let keywords = Array(analysis.recommendationKeywords.prefix(6))
        var places: [RecommendedPlace] = []
        var seenIDs = Set<String>()

        for keyword in keywords {
            if let place = try await searchPlace(area: area, keyword: keyword, event: event, analysis: analysis),
               !seenIDs.contains(place.externalID ?? place.placeName) {
                seenIDs.insert(place.externalID ?? place.placeName)
                places.append(place)
            }
        }

        return places
    }

    private func searchPlace(
        area: String,
        keyword: String,
        event: CalendarEvent,
        analysis: EventAnalysis
    ) async throws -> RecommendedPlace? {
        let query = "\(area) \(keyword)"
        let body: [String: Any] = [
            "textQuery": query,
            "languageCode": "ja",
            "maxResultCount": 1
        ]

        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "places.id,places.name,places.displayName,places.formattedAddress,places.rating,places.googleMapsUri,places.photos,places.primaryTypeDisplayName,places.types",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPValidator.validate(data: data, response: response)

        let decoded = try JSONDecoder().decode(GooglePlacesTextSearchResponse.self, from: data)
        guard let place = decoded.places.first else {
            return nil
        }

        var imageURL: URL?
        if let photo = place.photos?.first {
            imageURL = try? await fetchPhoto(photo)
        }

        let category = place.primaryTypeDisplayName?.text.nonBlank ?? keyword
        let mapsURL = place.googleMapsUri ?? mapsSearchURL(place.displayName.text, area: area)
        return RecommendedPlace(
            externalID: place.id,
            placeName: place.displayName.text,
            area: area,
            category: category,
            address: place.formattedAddress ?? "\(area)周辺",
            rating: place.rating,
            mapsURL: mapsURL,
            imageURL: imageURL,
            imageAttribution: place.photos?.first?.attributionText,
            aiReason: reason(for: place.displayName.text, area: area, category: category, event: event, analysis: analysis)
        )
    }

    private func fetchPhoto(_ photo: GooglePlacePhoto) async throws -> URL {
        let path = photo.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? photo.name
        let urlString = "https://places.googleapis.com/v1/\(path)/media?key=\(apiKey.urlQueryEncoded)&maxWidthPx=900"
        guard let url = URL(string: urlString) else {
            throw APIError(message: "Place Photo URLを作れませんでした。")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        try HTTPValidator.validate(data: data, response: response)
        return try ImageFileCache.save(data: data, prefix: "place-photo", fileExtension: "jpg")
    }

    private func mapsSearchURL(_ name: String, area: String) -> URL {
        let query = "\(name) \(area)".urlQueryEncoded
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(query)")!
    }

    private func reason(
        for placeName: String,
        area: String,
        category: String,
        event: CalendarEvent,
        analysis: EventAnalysis
    ) -> String {
        switch analysis.eventType {
        case .travel:
            return "\(event.title)に、\(area)らしい景色や寄り道を足せる\(category)候補です。"
        case .meal:
            return "食事の日に使いやすく、予定を少し長く楽しめる\(category)候補です。"
        case .workOrSchool:
            return "気分を切り替えやすい、\(area)周辺の\(category)候補です。"
        case .liveEvent:
            return "イベントの日の楽しみを増やしやすい、\(placeName)周辺の候補です。"
        case .unknown:
            return "予定の中身がまだ薄い日でも、行き先の輪郭を作れる\(category)候補です。"
        }
    }
}

private struct GooglePlacesTextSearchResponse: Decodable {
    let places: [GooglePlace]
}

private struct GooglePlace: Decodable {
    let id: String
    let name: String?
    let displayName: GoogleLocalizedText
    let formattedAddress: String?
    let rating: Double?
    let googleMapsUri: URL?
    let photos: [GooglePlacePhoto]?
    let primaryTypeDisplayName: GoogleLocalizedText?
    let types: [String]?
}

private struct GoogleLocalizedText: Decodable {
    let text: String
    let languageCode: String?
}

private struct GooglePlacePhoto: Decodable {
    let name: String
    let authorAttributions: [GoogleAuthorAttribution]?

    var attributionText: String? {
        guard let authorAttributions, !authorAttributions.isEmpty else {
            return nil
        }
        return authorAttributions
            .compactMap(\.displayName)
            .filter { !$0.isBlank }
            .joined(separator: ", ")
            .nonBlank
    }
}

private struct GoogleAuthorAttribution: Decodable {
    let displayName: String?
    let uri: URL?
    let photoUri: URL?
}

private extension String {
    var urlQueryEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
