import Foundation

struct APIConfiguration: Equatable {
    var googleOAuthClientID: String
    var googleOAuthRedirectScheme: String
    var googlePlacesAPIKey: String
    var openAIAPIKey: String
    var openAITextModel: String
    var openAIImageModel: String

    static let empty = APIConfiguration(
        googleOAuthClientID: "",
        googleOAuthRedirectScheme: "",
        googlePlacesAPIKey: "",
        openAIAPIKey: "",
        openAITextModel: "gpt-5.5",
        openAIImageModel: "gpt-image-2"
    )

    var hasGoogleOAuth: Bool {
        !googleOAuthClientID.isBlank && !googleOAuthRedirectScheme.isBlank
    }

    var hasGooglePlaces: Bool {
        !googlePlacesAPIKey.isBlank
    }

    var hasOpenAI: Bool {
        !openAIAPIKey.isBlank
    }
}

enum APIConfigurationLoader {
    static func load() -> APIConfiguration {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: String]
        else {
            return .empty
        }

        return APIConfiguration(
            googleOAuthClientID: dictionary["GoogleOAuthClientID"] ?? "",
            googleOAuthRedirectScheme: dictionary["GoogleOAuthRedirectScheme"] ?? "",
            googlePlacesAPIKey: dictionary["GooglePlacesAPIKey"] ?? "",
            openAIAPIKey: dictionary["OpenAIAPIKey"] ?? "",
            openAITextModel: (dictionary["OpenAITextModel"] ?? "").nonBlank ?? APIConfiguration.empty.openAITextModel,
            openAIImageModel: (dictionary["OpenAIImageModel"] ?? "").nonBlank ?? APIConfiguration.empty.openAIImageModel
        )
    }
}

extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var nonBlank: String? {
        isBlank ? nil : self
    }
}

struct APIError: LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}
