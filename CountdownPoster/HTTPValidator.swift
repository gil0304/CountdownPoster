import Foundation

enum HTTPValidator {
    static func validate(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError(message: "HTTPレスポンスを取得できませんでした。")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError(message: "HTTP \(httpResponse.statusCode): \(body)")
        }
    }
}
