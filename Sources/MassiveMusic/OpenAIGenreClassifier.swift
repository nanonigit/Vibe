import Foundation
import MassiveMusicCore
import Security

struct GenreSuggestion: Equatable, Sendable {
    let genre: String
    let confidence: Double
    let rationale: String
    let source: Source

    enum Source: Equatable, Sendable {
        case local
        case openAI
        case gemini
    }
}

enum AIProviderStatus: Equatable, Sendable {
    case notConfigured
    case configured
    case checking
    case valid
    case invalid(String)
}

enum APIKeyReadResult: Sendable {
    case value(String?)
    case authenticationRequired
    case failure(String)
}

enum OpenAIIntegrationError: LocalizedError {
    case keychain(OSStatus)
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case let .keychain(status): "Keychain error (\(status))"
        case .invalidResponse: "OpenAI returned an invalid genre response."
        case let .requestFailed(message): message
        }
    }
}

struct ProviderAPIKeychain: Sendable {
    let service: String
    private let account = "api-key"
    private let dbKey: String

    static let openAI = ProviderAPIKeychain(
        service: "com.local.MassiveMusic.openai",
        dbKey: "openai.key"
    )
    static let gemini = ProviderAPIKeychain(
        service: "com.local.MassiveMusic.gemini",
        dbKey: "gemini.key"
    )

    func readResult(database: LibraryDatabase? = nil, allowAuthenticationUI: Bool = false) -> APIKeyReadResult {
        if let database, let stored = try? database.setting(forKey: dbKey), !stored.isEmpty {
            return .value(stored)
        }
        if let legacy = try? readLegacyKeychain(allowAuthenticationUI: allowAuthenticationUI), !legacy.isEmpty {
            if let database {
                try? database.setSetting(legacy, forKey: dbKey)
                deleteLegacyKeychain()
            }
            return .value(legacy)
        }
        return .value(nil)
    }

    func read(database: LibraryDatabase? = nil, allowAuthenticationUI: Bool = false) throws -> String? {
        if let database, let stored = try? database.setting(forKey: dbKey), !stored.isEmpty {
            return stored
        }
        if let legacy = try? readLegacyKeychain(allowAuthenticationUI: allowAuthenticationUI), !legacy.isEmpty {
            if let database {
                try? database.setSetting(legacy, forKey: dbKey)
                deleteLegacyKeychain()
            }
            return legacy
        }
        return nil
    }

    func save(_ value: String, database: LibraryDatabase? = nil) throws {
        if let database {
            try database.setSetting(value, forKey: dbKey)
        }
        deleteLegacyKeychain()
    }

    func delete(database: LibraryDatabase? = nil) throws {
        if let database {
            try database.removeSetting(forKey: dbKey)
        }
        deleteLegacyKeychain()
    }

    private func readLegacyKeychain(allowAuthenticationUI: Bool) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if !allowAuthenticationUI {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw OpenAIIntegrationError.keychain(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    private func deleteLegacyKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}

actor OpenAIGenreClassifier {
    func validate(apiKey: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        try Self.validateResponse(data: data, response: response, provider: "OpenAI")
    }

    func classify(track: Track, apiKey: String, model: String, language: String) async throws -> GenreSuggestion {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let languageName = language == "ja" ? "Japanese" : "English"
        let metadata = """
        Title: \(track.title)
        Artist: \(track.artist)
        Album: \(track.album)
        Filename: \(track.filename)
        Existing genre: \(track.genre)
        """
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "genre": ["type": "string"],
                "confidence": ["type": "number", "minimum": 0, "maximum": 1],
                "rationale": ["type": "string"]
            ],
            "required": ["genre", "confidence", "rationale"],
            "additionalProperties": false
        ]
        let body: [String: Any] = [
            "model": model,
            "store": false,
            "input": [
                ["role": "system", "content": "Infer one concise music genre from metadata only. Never claim that audio was analyzed. Write the rationale in \(languageName)."],
                ["role": "user", "content": metadata]
            ],
            "text": ["format": ["type": "json_schema", "name": "genre_suggestion", "strict": true, "schema": schema]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIIntegrationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = root?["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "OpenAI request failed (HTTP \(http.statusCode))."
            throw OpenAIIntegrationError.requestFailed(message)
        }
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let output = root["output"] as? [[String: Any]],
            let text = output.lazy.compactMap({ item in
                (item["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.first
            }).first,
            let payload = text.data(using: .utf8),
            let result = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let genre = (result["genre"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !genre.isEmpty,
            let confidence = result["confidence"] as? Double,
            let rationale = result["rationale"] as? String
        else { throw OpenAIIntegrationError.invalidResponse }
        return GenreSuggestion(genre: genre, confidence: min(1, max(0, confidence)), rationale: rationale, source: .openAI)
    }

    private static func validateResponse(data: Data, response: URLResponse, provider: String) throws {
        guard let http = response as? HTTPURLResponse else { throw OpenAIIntegrationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = root?["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "\(provider) HTTP \(http.statusCode)"
            throw OpenAIIntegrationError.requestFailed(message)
        }
    }
}

actor GeminiGenreClassifier {
    func validate(apiKey: String, model: String) async throws {
        var request = URLRequest(url: modelURL(model))
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        _ = try await perform(request)
    }

    func classify(track: Track, apiKey: String, model: String, language: String) async throws -> GenreSuggestion {
        var request = URLRequest(url: generateURL(model))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let languageName = language == "ja" ? "Japanese" : "English"
        let prompt = """
        Infer one concise music genre from metadata only. Never claim audio was analyzed.
        Write the rationale in \(languageName).
        Title: \(track.title)
        Artist: \(track.artist)
        Album: \(track.album)
        Filename: \(track.filename)
        Existing genre: \(track.genre)
        """
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "genre": ["type": "string"],
                "confidence": ["type": "number", "minimum": 0, "maximum": 1],
                "rationale": ["type": "string"]
            ],
            "required": ["genre", "confidence", "rationale"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schema,
                "temperature": 0.1
            ]
        ])
        let data = try await perform(request)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = root["candidates"] as? [[String: Any]],
            let content = candidates.first?["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String,
            let payload = text.data(using: .utf8),
            let result = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let genre = (result["genre"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !genre.isEmpty,
            let confidence = result["confidence"] as? Double,
            let rationale = result["rationale"] as? String
        else { throw OpenAIIntegrationError.invalidResponse }
        return GenreSuggestion(
            genre: genre,
            confidence: min(1, max(0, confidence)),
            rationale: rationale,
            source: .gemini
        )
    }

    private func modelURL(_ model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encoded(model))")!
    }

    private func generateURL(_ model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encoded(model)):generateContent")!
    }

    private func encoded(_ model: String) -> String {
        model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIIntegrationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let error = root?["error"] as? [String: Any]
            let message = error?["message"] as? String ?? "Gemini HTTP \(http.statusCode)"
            throw OpenAIIntegrationError.requestFailed(message)
        }
        return data
    }
}
