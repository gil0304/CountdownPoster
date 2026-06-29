import Foundation

struct PersistedPosterState: Codable {
    var events: [CalendarEvent]
    var analyses: [String: EventAnalysis]
    var recommendations: [String: [RecommendedPlace]]
    var posters: [String: [Poster]]
    var hiddenEventKeys: [String]
    var lastSyncDate: Date?
}

enum LocalPosterCache {
    static func load() -> PersistedPosterState? {
        guard let data = try? Data(contentsOf: cacheURL()) else {
            return nil
        }
        return try? JSONDecoder().decode(PersistedPosterState.self, from: data)
    }

    static func save(_ state: PersistedPosterState) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            let url = cacheURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("LocalPosterCache save failed: \(error)")
            #endif
        }
    }

    private static func cacheURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CountdownPoster", isDirectory: true)
        return directory.appendingPathComponent("poster-state.json")
    }
}
