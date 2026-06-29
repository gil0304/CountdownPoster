import Foundation

protocol CalendarEventProviding {
    func fetchUpcomingEvents(daysAhead: Int, limit: Int) async throws -> [CalendarEvent]
}

struct DemoGoogleCalendarService: CalendarEventProviding {
    func fetchUpcomingEvents(daysAhead: Int, limit: Int) async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let now = Date()

        func date(days: Int, hour: Int, minute: Int = 0) -> Date {
            let targetDay = calendar.date(byAdding: .day, value: days, to: now) ?? now
            var components = calendar.dateComponents([.year, .month, .day], from: targetDay)
            components.hour = hour
            components.minute = minute
            return calendar.date(from: components) ?? targetDay
        }

        let events = [
            CalendarEvent(
                googleEventID: "demo-chiba-trip",
                title: "千葉旅行",
                detail: "海の近くでゆっくりする日",
                startAt: date(days: 5, hour: 9),
                endAt: date(days: 5, hour: 20)
            ),
            CalendarEvent(
                googleEventID: "demo-shibuya-meal",
                title: "りょうたとご飯",
                detail: "軽く飲んでからデザートも見たい",
                startAt: date(days: 7, hour: 19),
                endAt: date(days: 7, hour: 21),
                locationText: "渋谷"
            ),
            CalendarEvent(
                googleEventID: "demo-shinjuku-meeting",
                title: "会議",
                detail: "資料確認と方針決め",
                startAt: date(days: 2, hour: 14),
                endAt: date(days: 2, hour: 16),
                locationText: "新宿",
                nextEventStartAt: date(days: 2, hour: 20)
            ),
            CalendarEvent(
                googleEventID: "demo-gallery",
                title: "展示を見る",
                detail: "気になっていた展示",
                startAt: date(days: 1, hour: 15),
                endAt: date(days: 1, hour: 17),
                locationText: "六本木"
            ),
            CalendarEvent(
                googleEventID: "demo-unknown",
                title: "予定",
                startAt: date(days: 3, hour: 13),
                endAt: date(days: 3, hour: 15)
            ),
            CalendarEvent(
                googleEventID: "demo-today",
                title: "横浜デート",
                detail: "夜景を見たい日",
                startAt: date(days: 0, hour: 18),
                endAt: date(days: 0, hour: 22)
            ),
            CalendarEvent(
                googleEventID: "demo-kyoto",
                title: "京都旅行",
                detail: "写真をたくさん撮る",
                startAt: date(days: 14, hour: 8),
                endAt: date(days: 14, hour: 21)
            )
        ]

        return events
            .filter { $0.startAt <= (calendar.date(byAdding: .day, value: daysAhead, to: now) ?? now) }
            .sorted { $0.startAt < $1.startAt }
            .prefix(limit)
            .map { $0 }
    }
}

struct GoogleCalendarAPIService: CalendarEventProviding {
    private let oauthClient: GoogleOAuthClient

    init(oauthClient: GoogleOAuthClient) {
        self.oauthClient = oauthClient
    }

    func fetchUpcomingEvents(daysAhead: Int, limit: Int) async throws -> [CalendarEvent] {
        let accessToken = try await oauthClient.accessToken()
        let now = Date()
        let timeMax = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now

        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: RFC3339DateFormatter.string(from: now)),
            URLQueryItem(name: "timeMax", value: RFC3339DateFormatter.string(from: timeMax)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: String(limit))
        ]

        guard let url = components.url else {
            throw APIError(message: "Google Calendar URLを作れませんでした。")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPValidator.validate(data: data, response: response)

        let decoded = try JSONDecoder().decode(GoogleCalendarEventsResponse.self, from: data)
        var events = decoded.items.compactMap { $0.calendarEvent() }
            .sorted { $0.startAt < $1.startAt }

        for index in events.indices {
            let nextIndex = events.index(after: index)
            if events.indices.contains(nextIndex) {
                events[index].nextEventStartAt = events[nextIndex].startAt
            }
        }

        return events
    }
}

struct RuleBasedEventAnalyzer {
    private let knownAreas = [
        "千葉", "京都", "大阪", "箱根", "熱海", "鎌倉", "新宿", "渋谷", "横浜", "表参道",
        "神保町", "清澄白河", "代官山", "下北沢", "東京", "六本木", "上野", "吉祥寺",
        "浅草", "銀座", "中目黒", "恵比寿", "原宿", "池袋"
    ]

    func analyze(_ event: CalendarEvent) -> EventAnalysis {
        let eventType = detectEventType(title: event.title, detail: event.detail)
        let locationArea = event.locationText.flatMap { findArea(in: $0) ?? cleanedLocation($0) }
        let titleArea = findArea(in: event.title)
        let detectedArea = locationArea ?? titleArea
        let hasSpecificLocation = locationArea != nil
        let freeMinutes = event.freeTimeAfterEventMinutes()

        var mode: RecommendationMode
        if eventType == .workOrSchool, let freeMinutes, freeMinutes >= 60 {
            mode = .afterEventReward
        } else if hasSpecificLocation {
            mode = .locationBased
        } else if titleArea != nil {
            mode = .areaBased
        } else {
            mode = .tokyoDefault
        }

        let keywords = recommendationKeywords(for: eventType, mode: mode)
        let confidence = confidenceScore(eventType: eventType, area: detectedArea, hasLocation: hasSpecificLocation)
        let tone = posterTone(for: eventType)
        let areaPhrase = detectedArea ?? "Tokyo"
        let prompt = "A cinematic editorial background inspired by \(tone) around \(areaPhrase), realistic atmosphere, subtle depth, no readable text"

        return EventAnalysis(
            eventType: eventType,
            confidence: confidence,
            detectedArea: detectedArea,
            hasSpecificLocation: hasSpecificLocation,
            recommendationMode: mode,
            recommendationKeywords: keywords,
            posterTone: tone,
            backgroundPrompt: prompt,
            freeTimeAfterEventMinutes: freeMinutes
        )
    }

    private func detectEventType(title: String, detail: String) -> EventType {
        let text = "\(title) \(detail)".lowercased()
        if containsAny(["旅行", "日帰り", "温泉", "観光", "さんぽ", "散歩"], in: text) {
            return .travel
        }
        if containsAny(["ご飯", "ごはん", "ランチ", "ディナー", "飲み", "飲み会", "カフェ", "デート", "買い物", "lunch", "dinner"], in: text) {
            return .meal
        }
        if containsAny(["会議", "mtg", "ミーティング", "授業", "バイト", "出勤", "面接", "研修", "作業", "スクール", "仕事"], in: text) {
            return .workOrSchool
        }
        if containsAny(["ライブ", "展示", "美術館", "映画", "舞台", "フェス", "発表", "イベント"], in: text) {
            return .liveEvent
        }
        return .unknown
    }

    private func containsAny(_ keywords: [String], in text: String) -> Bool {
        keywords.contains { text.contains($0.lowercased()) }
    }

    private func findArea(in text: String) -> String? {
        knownAreas.first { text.contains($0) }
    }

    private func cleanedLocation(_ location: String) -> String? {
        let cleaned = location
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "駅", with: "")
        return cleaned.isEmpty ? nil : cleaned
    }

    private func confidenceScore(eventType: EventType, area: String?, hasLocation: Bool) -> Double {
        var score = eventType == .unknown ? 0.34 : 0.72
        if area != nil {
            score += 0.12
        }
        if hasLocation {
            score += 0.1
        }
        return min(score, 0.96)
    }

    private func recommendationKeywords(for eventType: EventType, mode: RecommendationMode) -> [String] {
        if mode == .afterEventReward {
            return ["カフェ", "本屋", "軽食", "静かな喫茶店", "公園", "ベーカリー"]
        }

        switch eventType {
        case .travel:
            return ["観光地", "カフェ", "写真スポット", "ご飯", "公園", "雑貨店"]
        case .meal:
            return ["夜カフェ", "二軒目", "デザート", "散歩", "バー", "ベーカリー"]
        case .workOrSchool:
            return ["カフェ", "本屋", "軽食", "休憩場所", "ベーカリー", "公園"]
        case .liveEvent:
            return ["カフェ", "写真スポット", "散歩", "軽食", "書店", "ギャラリー"]
        case .unknown:
            return ["東京のカフェ", "散歩", "本屋", "季節スポット", "ベーカリー", "公園"]
        }
    }

    private func posterTone(for eventType: EventType) -> String {
        switch eventType {
        case .travel:
            return "exciting travel"
        case .meal:
            return "warm cafe night"
        case .workOrSchool:
            return "calm city reward"
        case .liveEvent:
            return "vivid event ticket"
        case .unknown:
            return "playful Tokyo city"
        }
    }
}

struct LocalPlaceRecommendationService {
    func recommendations(for event: CalendarEvent, analysis: EventAnalysis) -> [RecommendedPlace] {
        let area = analysis.displayArea

        switch analysis.eventType {
        case .travel:
            return travelPlaces(area: area)
        case .meal:
            return mealPlaces(area: area)
        case .workOrSchool:
            return rewardPlaces(area: area, freeMinutes: analysis.freeTimeAfterEventMinutes)
        case .liveEvent:
            return eventPlaces(area: area)
        case .unknown:
            return tokyoDefaultPlaces(title: event.title)
        }
    }

    private func travelPlaces(area: String) -> [RecommendedPlace] {
        switch area {
        case "千葉":
            return [
                place("稲毛海浜公園", area, "海辺", "海を見ながら予定の温度を上げられる、千葉らしい候補です。"),
                place("千葉ポートタワー", area, "夜景", "高い場所から街と海を見られて、写真にも残しやすい寄り道です。"),
                place("椿森コムナ", area, "カフェ", "外の空気を感じながら休める、旅の合間に置きたいカフェ候補です。"),
                place("千葉市美術館", area, "美術館", "落ち着いた時間を足せる、街中の文化スポットです。"),
                place("千葉公園", area, "公園", "広い空と緑で、当日の気分を整えやすい場所です。"),
                place("ペリエ千葉", area, "ショップ", "短い時間でも見て回りやすい、駅近の候補です。")
            ]
        case "京都":
            return [
                place("鴨川デルタ", area, "散歩", "少し歩くだけで京都らしい余白が足せます。"),
                place("喫茶ソワレ", area, "カフェ", "色のあるデザートで、旅行ポスターに入れたくなる寄り道です。"),
                place("八坂庚申堂", area, "写真スポット", "短い滞在でも記憶に残りやすい、写真映えする候補です。"),
                place("京都府立植物園", area, "庭園", "静かに歩けて、写真にも残しやすい場所です。"),
                place("恵文社一乗寺店", area, "本屋", "本と雑貨を見ながら気分を作れる候補です。"),
                place("さらさ西陣", area, "カフェ", "建物の雰囲気まで楽しめるカフェ候補です。")
            ]
        case "横浜":
            return [
                place("横浜赤レンガ倉庫", area, "散歩", "海沿いの空気と建物の雰囲気があり、予定をイベント化しやすい場所です。"),
                place("大さん橋", area, "夜景", "夜の予定なら、少し歩くだけで特別感を足せます。"),
                place("象の鼻テラス", area, "休憩", "海沿いの景色と休憩場所をまとめて置ける候補です。"),
                place("MARINE & WALK YOKOHAMA", area, "ショップ", "海辺を歩きながら店を見られる候補です。"),
                place("山下公園", area, "公園", "水辺の景色で当日の雰囲気を作れます。"),
                place("馬車道十番館", area, "喫茶店", "クラシックな空気で特別感を足せる喫茶店です。")
            ]
        case "鎌倉":
            return [
                place("由比ガ浜", area, "海", "海まで歩けると、予定そのものが小さな旅になります。"),
                place("報国寺", area, "観光", "静かな場所をひとつ入れるだけで、予定の密度が上がります。"),
                place("カフェ ヴィヴモン ディモンシュ", area, "カフェ", "街歩きの途中に入れやすい、鎌倉らしいカフェ候補です。"),
                place("小町通り", area, "街歩き", "食べ歩きや小さな買い物を足しやすい場所です。"),
                place("鎌倉文学館", area, "文化スポット", "静かな時間を予定に足せる候補です。"),
                place("長谷寺", area, "観光", "季節の景色が入りやすい、写真にも強い場所です。")
            ]
        default:
            return [
                place("\(area)の写真スポット", area, "写真スポット", "予定名から見えたエリアに、写真を撮るきっかけを足します。"),
                place("\(area)のカフェ", area, "カフェ", "移動の合間に休める場所をひとつ置くと、予定が少し楽しみになります。"),
                place("\(area)の観光スポット", area, "観光", "短く寄れる候補を持っておくと、当日の自由度が上がります。"),
                place("\(area)の本屋", area, "本屋", "少し落ち着ける場所として入れやすい候補です。"),
                place("\(area)のベーカリー", area, "ベーカリー", "軽く立ち寄るだけでも楽しみを作れる候補です。"),
                place("\(area)の公園", area, "公園", "外の空気を足せる、当日の余白になる場所です。")
            ]
        }
    }

    private func mealPlaces(area: String) -> [RecommendedPlace] {
        switch area {
        case "渋谷":
            return [
                place("渋谷ストリーム", area, "二軒目", "食事の日に少し歩きながら寄れる、夜の流れを作りやすい候補です。"),
                place("茶亭 羽當", area, "カフェ", "会話の続きに使いやすい、落ち着いたカフェ候補です。"),
                place("MIYASHITA PARK", area, "散歩", "外を歩きたい日に、短い寄り道として扱いやすい場所です。"),
                place("渋谷PARCO", area, "ショップ", "食事の日に少し見て回れる候補です。"),
                place("TRUNK HOTEL CAT STREET", area, "ラウンジ", "落ち着いた空気で夜の予定に合わせやすい場所です。"),
                place("神南カフェ", area, "カフェ", "話しやすい雰囲気を足せるカフェ候補です。")
            ]
        default:
            return [
                place("\(area)の夜カフェ", area, "夜カフェ", "食事の日に会話の場所をもうひとつ作れる候補です。"),
                place("\(area)のデザート", area, "デザート", "会話の続きに甘い予定を足せます。"),
                place("\(area)の散歩スポット", area, "散歩", "軽く歩ける選択肢があると、当日がやわらかくなります。"),
                place("\(area)のバー", area, "バー", "夜の雰囲気をもう少し足せる候補です。"),
                place("\(area)のベーカリー", area, "ベーカリー", "軽い手土産や朝の楽しみにしやすい候補です。"),
                place("\(area)の本屋", area, "本屋", "会話のきっかけを作れる寄り道です。")
            ]
        }
    }

    private func rewardPlaces(area: String, freeMinutes: Int?) -> [RecommendedPlace] {
        let minutesText = freeMinutes.map { "\($0 / 60)時間くらい" } ?? "少し"
        switch area {
        case "新宿":
            return [
                place("ブルックリンパーラー新宿", area, "カフェ", "\(minutesText)過ごしやすく、食事も会話も置ける候補です。"),
                place("紀伊國屋書店 新宿本店", area, "本屋", "頭を切り替えたい日に、短く寄りやすい場所です。"),
                place("新宿御苑", area, "散歩", "外の空気を挟むだけで、仕事や学校の日が少し軽くなります。"),
                place("BERG", area, "軽食", "短い時間でも入りやすい、駅近の候補です。"),
                place("NEWoMan新宿", area, "ショップ", "少し見て回るだけでも予定に明るさを足せます。"),
                place("猿田彦珈琲 新宿", area, "コーヒー", "気分を整える一杯を置きやすい場所です。")
            ]
        default:
            return [
                place("\(area)の作業カフェ", area, "カフェ", "休憩や軽い作業に移りやすい候補です。"),
                place("\(area)の本屋", area, "本屋", "気分転換の寄り道として、短い空き時間にも入れやすい場所です。"),
                place("\(area)の軽めのご飯", area, "軽食", "無理なく入れやすい軽い食事の選択肢です。"),
                place("\(area)の静かな喫茶店", area, "喫茶店", "落ち着いて気持ちを整えやすい候補です。"),
                place("\(area)のベーカリー", area, "ベーカリー", "短く寄れる楽しみとして扱いやすい場所です。"),
                place("\(area)の公園", area, "公園", "外の空気で予定の日を軽くできます。")
            ]
        }
    }

    private func eventPlaces(area: String) -> [RecommendedPlace] {
        switch area {
        case "六本木":
            return [
                place("六本木ヒルズ周辺カフェ", area, "開始前カフェ", "開始前に少し早く着いても、気持ちを整えやすい候補です。"),
                place("東京ミッドタウン", area, "散歩", "展示や映画の日に、街の空気も一緒に楽しめる場所です。"),
                place("国立新美術館周辺", area, "写真スポット", "予定の記憶を写真に残しやすい候補です。"),
                place("文喫 六本木", area, "本屋", "本を眺める時間を入れやすい候補です。"),
                place("ブルーボトルコーヒー 六本木カフェ", area, "コーヒー", "短く寄れる一杯を置きやすい場所です。"),
                place("けやき坂", area, "街歩き", "夜の景色までポスター映えしやすい場所です。")
            ]
        default:
            return [
                place("\(area)の開始前カフェ", area, "開始前カフェ", "開演前の余白を作れて、当日の楽しみが増えます。"),
                place("\(area)の軽食スポット", area, "軽食", "イベントの日に話しやすい場所を置いておけます。"),
                place("\(area)の写真スポット", area, "写真スポット", "当日の一枚を作りやすい候補です。"),
                place("\(area)の本屋", area, "本屋", "予定のテンションを静かに整えられる場所です。"),
                place("\(area)のギャラリー", area, "ギャラリー", "予定の雰囲気に文化的な寄り道を足せます。"),
                place("\(area)の公園", area, "公園", "外の空気を入れられる候補です。")
            ]
        }
    }

    private func tokyoDefaultPlaces(title: String) -> [RecommendedPlace] {
        if title.contains("作業") {
            return [
                place("渋谷の作業カフェ", "東京", "作業カフェ", "少し気分を変えて作業できる、予定名が薄い日にも使いやすい候補です。"),
                place("表参道の静かなカフェ", "東京", "カフェ", "落ち着いて過ごせる場所を置いておくと、予定が整いやすくなります。"),
                place("神保町の本屋近く", "東京", "本屋", "作業の日に頭を切り替えやすい寄り道です。"),
                place("代々木公園", "東京", "公園", "外の空気で気分を軽くしやすい場所です。"),
                place("蔵前のコーヒースタンド", "東京", "コーヒー", "短く寄るだけでも気分を作れます。"),
                place("中目黒のベーカリー", "東京", "ベーカリー", "小さな楽しみを予定に足せる候補です。")
            ]
        }

        return [
            place("下北沢 BONUS TRACK", "東京", "カフェ", "行き先が未定でも、店を見ながら歩ける楽しさを足せます。"),
            place("代官山 蔦屋書店", "東京", "本屋", "ひとりでも誰かとでも過ごしやすく、予定の輪郭を作れます。"),
            place("清澄白河カフェ通り", "東京", "散歩", "ゆっくり歩けて、雑な予定名の日も少しイベントにできます。"),
            place("上野恩賜公園", "東京", "公園", "広い景色で当日の気分を作りやすい場所です。"),
            place("銀座 伊東屋", "東京", "ショップ", "小物や文具を見るだけでも気分が上がる候補です。"),
            place("蔵前の雑貨店", "東京", "雑貨店", "歩きながら見つける楽しみを作れる場所です。")
        ]
    }

    private func place(_ name: String, _ area: String, _ category: String, _ reason: String) -> RecommendedPlace {
        let query = "\(name) \(area)"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(encoded)")!
        return RecommendedPlace(
            placeName: name,
            area: area,
            category: category,
            address: "\(area)周辺",
            mapsURL: url,
            imageURL: DemoPlaceImage.url(forName: name, category: category),
            aiReason: reason
        )
    }
}

private enum DemoPlaceImage {
    static func url(forName name: String, category: String) -> URL? {
        let resource = resourceName(forName: name, category: category)
        return Bundle.main.url(forResource: resource, withExtension: "png", subdirectory: "DemoImages")
            ?? Bundle.main.url(forResource: resource, withExtension: "png")
    }

    private static func resourceName(forName name: String, category: String) -> String {
        let text = "\(name) \(category)"

        if containsAny(["海", "水辺", "夜景", "港", "赤レンガ", "大さん橋", "横浜"], in: text) {
            return "demo-waterfront"
        }
        if containsAny(["カフェ", "喫茶", "コーヒー", "ラウンジ", "ベーカリー", "軽食", "デザート"], in: text) {
            return "demo-cafe"
        }
        if containsAny(["公園", "庭園", "植物園", "散歩", "鴨川", "御苑"], in: text) {
            return "demo-park"
        }
        if containsAny(["美術館", "展示", "ギャラリー", "写真", "文化"], in: text) {
            return "demo-gallery"
        }
        if containsAny(["本屋", "書店", "ショップ", "雑貨", "文具"], in: text) {
            return "demo-shop"
        }
        return "demo-city"
    }

    private static func containsAny(_ keywords: [String], in text: String) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

struct PosterFactory {
    func makePosters(for event: CalendarEvent, analysis: EventAnalysis, recommendations: [RecommendedPlace]) -> [CountdownStage: Poster] {
        Dictionary(uniqueKeysWithValues: CountdownStage.allCases.map { stage in
            (stage, makePoster(for: event, analysis: analysis, recommendations: recommendations, stage: stage))
        })
    }

    func makePoster(
        for event: CalendarEvent,
        analysis: EventAnalysis,
        recommendations: [RecommendedPlace],
        stage: CountdownStage,
        styleSeed: Int = Int.random(in: 0...9999)
    ) -> Poster {
        let selectedPlaces = spotlightPlaces(for: stage, recommendations: recommendations)
        let copy = copy(for: event, analysis: analysis, places: selectedPlaces, stage: stage)
        let spotlight = selectedPlaces.first
        let textDesign = fallbackTextDesign(
            stage: stage,
            place: spotlight,
            mainCopy: copy.main,
            subCopy: copy.sub
        )
        return Poster(
            event: event,
            analysis: analysis,
            countdownStage: stage,
            mainCopy: copy.main,
            subCopy: copy.sub,
            templateType: "venue-v5-\(stage.rawValue)-\(analysis.eventType.rawValue)",
            backgroundPrompt: backgroundPrompt(for: spotlight, analysis: analysis, stage: stage),
            recommendedPlaces: selectedPlaces,
            styleSeed: styleSeed,
            textDesign: textDesign
        )
    }

    private func spotlightPlaces(for stage: CountdownStage, recommendations: [RecommendedPlace]) -> [RecommendedPlace] {
        let selected = recommendations.filter(\.selectedForPoster)
        let pool = selected.isEmpty ? recommendations : selected
        guard !pool.isEmpty else {
            return []
        }

        let stageIndex = CountdownStage.allCases.firstIndex(of: stage) ?? 0
        guard pool.indices.contains(stageIndex) else {
            return []
        }
        return [pool[stageIndex]]
    }

    private func backgroundPrompt(for place: RecommendedPlace?, analysis: EventAnalysis, stage: CountdownStage) -> String {
        guard let place else {
            return "Premium Japanese editorial poster background, atmospheric venue mood, \(stage.compactTitle), no readable text, no numbers, no letters"
        }

        return """
        Premium Japanese editorial poster background for \(place.placeName), \(place.category).
        Atmospheric place-focused scene, cinematic light, refined layout space, countdown mood \(stage.compactTitle), no readable text, no numbers, no letters
        """
    }

    private func copy(
        for event: CalendarEvent,
        analysis: EventAnalysis,
        places: [RecommendedPlace],
        stage: CountdownStage
    ) -> (main: String, sub: String) {
        let place = places.first
        let fallback = analysis.recommendationKeywords.prefix(2).joined(separator: " / ")
        let spotLine = spotlightCopy(place: place, fallback: fallback)

        switch stage {
        case .sevenDays:
            return ("少し先の楽しみ", spotLine)
        case .fiveDays:
            return ("気分を温める", spotLine)
        case .threeDays:
            return ("景色を先取り", spotLine)
        case .twoDays:
            return ("ここを目印に", spotLine)
        case .oneDay:
            return ("明日はここから", spotLine)
        case .today:
            return ("今日はここへ", spotLine)
        }
    }

    private func spotlightCopy(place: RecommendedPlace?, fallback: String) -> String {
        guard let place else {
            return "\(fallback)を少し足す。"
        }

        return "\(place.category)を少し足す。"
    }

    private func fallbackTextDesign(
        stage: CountdownStage,
        place: RecommendedPlace?,
        mainCopy: String,
        subCopy: String
    ) -> PosterTextDesign {
        let layout = fallbackLayout(for: stage)
        let mood = fallbackMood(for: stage)
        return PosterTextDesign(
            countdownText: stage.compactTitle,
            placeText: lineBroken(place?.placeName ?? "おすすめスポット"),
            mainCopy: mainCopy,
            subCopy: subCopy,
            layoutVariant: layout,
            fontMood: mood
        )
    }

    private func fallbackLayout(for stage: CountdownStage) -> PosterLayoutVariant {
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

    private func fallbackMood(for stage: CountdownStage) -> PosterFontMood {
        switch stage {
        case .sevenDays, .threeDays:
            return .softEditorial
        case .fiveDays, .twoDays:
            return .compactLabel
        case .oneDay, .today:
            return .boldPop
        }
    }

    private func lineBroken(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 9 else {
            return trimmed
        }

        if let separator = [" ", "・", "＆", "&"].first(where: { trimmed.contains($0) }) {
            return trimmed.replacingOccurrences(of: separator, with: "\n", options: [], range: trimmed.range(of: separator))
        }

        let middle = trimmed.index(trimmed.startIndex, offsetBy: trimmed.count / 2)
        return "\(trimmed[..<middle])\n\(trimmed[middle...])"
    }
}
