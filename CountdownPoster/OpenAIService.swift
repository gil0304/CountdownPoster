import Foundation

struct OpenAIEventAnalyzer {
    private let configuration: APIConfiguration

    init(configuration: APIConfiguration) {
        self.configuration = configuration
    }

    func analyze(_ event: CalendarEvent) async throws -> EventAnalysis {
        guard configuration.hasOpenAI else {
            throw APIError(message: "OpenAIAPIKey がありません。")
        }

        let schema = eventAnalysisSchema()
        let userContent = """
        予定名: \(event.title)
        説明: \(event.detail)
        場所: \(event.locationText ?? "未設定")
        開始: \(event.startAt.formatted(.iso8601))
        終了: \(event.endAt.formatted(.iso8601))
        次の予定までの空き時間分: \(event.freeTimeAfterEventMinutes().map(String.init) ?? "不明")
        """

        let body: [String: Any] = [
            "model": configuration.openAITextModel,
            "input": [
                [
                    "role": "system",
                    "content": """
                    あなたは日本語カレンダー予定を分類し、カウントダウンポスター用の企画情報を返すアシスタントです。
                    eventTypeは travel / meal / work_or_school / event / unknown のどれか。
                    recommendationModeは location_based / area_based / tokyo_default / after_event_reward のどれか。
                    recommendationKeywordsは重複しない6件を返してください。
                    場所が明示されている場合はそれを優先し、予定名から地域が推定できる場合は地域名を返してください。
                    背景プロンプトは英語で、文字なしのポスター背景として生成しやすい内容にしてください。
                    """
                ],
                [
                    "role": "user",
                    "content": userContent
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "countdown_poster_event_analysis",
                    "schema": schema,
                    "strict": true
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPValidator.validate(data: data, response: response)

        let text = try OpenAIResponseTextExtractor.extractText(from: data)
        let dto = try JSONDecoder().decode(OpenAIEventAnalysisDTO.self, from: Data(text.utf8))
        return dto.eventAnalysis(fallbackFreeMinutes: event.freeTimeAfterEventMinutes())
    }

    private func eventAnalysisSchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "eventType": [
                    "type": "string",
                    "enum": ["travel", "meal", "work_or_school", "event", "unknown"]
                ],
                "confidence": [
                    "type": "number",
                    "minimum": 0,
                    "maximum": 1
                ],
                "detectedArea": [
                    "type": ["string", "null"]
                ],
                "hasSpecificLocation": [
                    "type": "boolean"
                ],
                "recommendationMode": [
                    "type": "string",
                    "enum": ["location_based", "area_based", "tokyo_default", "after_event_reward"]
                ],
                "recommendationKeywords": [
                    "type": "array",
                    "items": ["type": "string"],
                    "minItems": 6,
                    "maxItems": 6
                ],
                "posterTone": [
                    "type": "string"
                ],
                "backgroundPrompt": [
                    "type": "string"
                ],
                "freeTimeAfterEventMinutes": [
                    "type": ["integer", "null"]
                ]
            ],
            "required": [
                "eventType",
                "confidence",
                "detectedArea",
                "hasSpecificLocation",
                "recommendationMode",
                "recommendationKeywords",
                "posterTone",
                "backgroundPrompt",
                "freeTimeAfterEventMinutes"
            ]
        ]
    }
}

struct GeneratedPosterCopy {
    var mainCopy: String
    var subCopy: String
    var textDesign: PosterTextDesign
}

struct OpenAIPosterCopyGenerator {
    private let configuration: APIConfiguration

    init(configuration: APIConfiguration) {
        self.configuration = configuration
    }

    func generateCopy(for poster: Poster) async throws -> GeneratedPosterCopy {
        guard configuration.hasOpenAI else {
            throw APIError(message: "OpenAIAPIKey がありません。")
        }

        guard let place = poster.recommendedPlaces.first else {
            throw APIError(message: "ポスターにおすすめスポットがありません。")
        }

        let forbiddenLocation = poster.event.locationText ?? poster.analysis.detectedArea ?? ""
        let userContent = """
        カウントダウン: \(poster.countdownStage.title)
        予定名（出力しない）: \(poster.event.title)
        実際の予定場所（出力禁止）: \(forbiddenLocation)
        おすすめ場所名: \(place.placeName)
        おすすめカテゴリ: \(place.category)
        おすすめ理由: \(place.aiReason)
        予定タイプ: \(poster.analysis.eventType.label)
        """

        let body: [String: Any] = [
            "model": configuration.openAITextModel,
            "input": [
                [
                    "role": "system",
                    "content": """
                    あなたはスマホ用の日本語カウントダウンポスターのコピーライターです。
                    出力はポスターに直接載る短い日本語だけです。
                    主役はおすすめ場所の画像です。文字は小さめに添え、場所名とカウントダウンだけが静かに伝わる設計にしてください。
                    予定名、実際の予定場所、住所、日時、駅名、説明的な長文は書かないでください。
                    countdownTextはカウントダウンの意味を保ち、短く読みやすくしてください。
                    placeTextはおすすめ場所名をポスター用に改行したものです。必要なら1回だけ改行できます。
                    mainCopyは8〜18文字程度で、場所に行きたくなる一文。
                    subCopyは12〜28文字程度で、おすすめ場所の魅力を自然に補足する一文。
                    layoutVariantは背景写真の余白を想像して、画像を邪魔しない位置を選んでください。
                    fontMoodは控えめで写真に馴染む文字のムードです。
                    絵文字、ハッシュタグ、引用符、句読点の連打は禁止です。
                    """
                ],
                [
                    "role": "user",
                    "content": userContent
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "countdown_poster_copy",
                    "schema": posterCopySchema(),
                    "strict": true
                ]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPValidator.validate(data: data, response: response)

        let text = try OpenAIResponseTextExtractor.extractText(from: data)
        let dto = try JSONDecoder().decode(OpenAIPosterCopyDTO.self, from: Data(text.utf8))
        let textDesign = PosterTextDesign(
            countdownText: dto.countdownText,
            placeText: dto.placeText,
            mainCopy: dto.mainCopy,
            subCopy: dto.subCopy,
            layoutVariant: PosterLayoutVariant(rawValue: dto.layoutVariant) ?? .bottomLeft,
            fontMood: PosterFontMood(rawValue: dto.fontMood) ?? .boldPop
        )
        return GeneratedPosterCopy(mainCopy: dto.mainCopy, subCopy: dto.subCopy, textDesign: textDesign)
    }

    private func posterCopySchema() -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "mainCopy": [
                    "type": "string",
                    "maxLength": 40
                ],
                "subCopy": [
                    "type": "string",
                    "maxLength": 70
                ],
                "countdownText": [
                    "type": "string",
                    "maxLength": 12
                ],
                "placeText": [
                    "type": "string",
                    "maxLength": 40
                ],
                "layoutVariant": [
                    "type": "string",
                    "enum": ["bottomLeft", "topLeft", "centerStack", "splitBands", "bottomCenter", "topRight"]
                ],
                "fontMood": [
                    "type": "string",
                    "enum": ["boldPop", "softEditorial", "compactLabel"]
                ]
            ],
            "required": ["mainCopy", "subCopy", "countdownText", "placeText", "layoutVariant", "fontMood"]
        ]
    }
}

struct OpenAIImageGenerator {
    private let configuration: APIConfiguration

    init(configuration: APIConfiguration) {
        self.configuration = configuration
    }

    func generateBackgroundImage(for poster: Poster) async throws -> URL {
        guard configuration.hasOpenAI else {
            throw APIError(message: "OpenAIAPIKey がありません。")
        }

        let prompt = """
        \(poster.backgroundPrompt).
        Create a rich vertical 9:16 background for a Japanese venue countdown poster.
        Make the recommended shop or place feel aspirational and real, with cinematic light and tasteful editorial composition.
        Absolutely no readable text, no letters, no numbers, no logo-like marks.
        Leave clean negative space for app-rendered Japanese typography.
        """

        let body: [String: Any] = [
            "model": configuration.openAIImageModel,
            "prompt": prompt,
            "size": "1024x1536",
            "quality": "medium",
            "output_format": "jpeg",
            "n": 1
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPValidator.validate(data: data, response: response)

        let decoded = try JSONDecoder().decode(OpenAIImageResponse.self, from: data)
        guard let base64 = decoded.data.first?.b64JSON,
              let imageData = Data(base64Encoded: base64)
        else {
            throw APIError(message: "OpenAI画像レスポンスに画像データがありません。")
        }

        return try ImageFileCache.save(data: imageData, prefix: "openai-background", fileExtension: decoded.outputFormat ?? "jpeg")
    }
}

private struct OpenAIPosterCopyDTO: Decodable {
    let mainCopy: String
    let subCopy: String
    let countdownText: String
    let placeText: String
    let layoutVariant: String
    let fontMood: String
}

private struct OpenAIEventAnalysisDTO: Decodable {
    let eventType: String
    let confidence: Double
    let detectedArea: String?
    let hasSpecificLocation: Bool
    let recommendationMode: String
    let recommendationKeywords: [String]
    let posterTone: String
    let backgroundPrompt: String
    let freeTimeAfterEventMinutes: Int?

    func eventAnalysis(fallbackFreeMinutes: Int?) -> EventAnalysis {
        EventAnalysis(
            eventType: mapEventType(eventType),
            confidence: confidence,
            detectedArea: detectedArea?.nonBlank,
            hasSpecificLocation: hasSpecificLocation,
            recommendationMode: mapRecommendationMode(recommendationMode),
            recommendationKeywords: recommendationKeywords,
            posterTone: posterTone,
            backgroundPrompt: backgroundPrompt,
            freeTimeAfterEventMinutes: freeTimeAfterEventMinutes ?? fallbackFreeMinutes
        )
    }

    private func mapEventType(_ value: String) -> EventType {
        switch value {
        case "travel":
            return .travel
        case "meal":
            return .meal
        case "work_or_school":
            return .workOrSchool
        case "event":
            return .liveEvent
        default:
            return .unknown
        }
    }

    private func mapRecommendationMode(_ value: String) -> RecommendationMode {
        switch value {
        case "location_based":
            return .locationBased
        case "area_based":
            return .areaBased
        case "after_event_reward":
            return .afterEventReward
        default:
            return .tokyoDefault
        }
    }
}

private struct OpenAIImageResponse: Decodable {
    let data: [OpenAIImageData]
    let outputFormat: String?

    enum CodingKeys: String, CodingKey {
        case data
        case outputFormat = "output_format"
    }
}

private struct OpenAIImageData: Decodable {
    let b64JSON: String?

    enum CodingKeys: String, CodingKey {
        case b64JSON = "b64_json"
    }
}

private enum OpenAIResponseTextExtractor {
    static func extractText(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data)
        if let text = findText(in: object), !text.isBlank {
            return text
        }
        throw APIError(message: "OpenAI Responses APIからJSONテキストを取り出せませんでした。")
    }

    private static func findText(in object: Any) -> String? {
        if let dictionary = object as? [String: Any] {
            if let text = dictionary["text"] as? String,
               text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                return text
            }
            if let outputText = dictionary["output_text"] as? String,
               outputText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                return outputText
            }
            for value in dictionary.values {
                if let found = findText(in: value) {
                    return found
                }
            }
        }

        if let array = object as? [Any] {
            for value in array {
                if let found = findText(in: value) {
                    return found
                }
            }
        }

        return nil
    }
}
