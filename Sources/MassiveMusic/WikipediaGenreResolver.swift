import Foundation
import MassiveMusicCore

actor WikipediaGenreResolver {
    private let database: LibraryDatabase
    private let session: URLSession
    private var attemptedRawKeys: Set<String> = []

    init(database: LibraryDatabase, session: URLSession? = nil) {
        self.database = database
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            configuration.httpAdditionalHeaders = [
                "User-Agent": "Vibe/0.17 (local macOS music library; genre metadata lookup)"
            ]
            self.session = URLSession(configuration: configuration)
        }
    }

    func resolve(_ rawGenre: String) async -> GenreKnowledge? {
        if let cached = try? database.genreKnowledge(forRawGenre: rawGenre) {
            return cached
        }
        let rawKey = GenreNormalizer.lookupKey(rawGenre)
        guard !rawKey.isEmpty, attemptedRawKeys.insert(rawKey).inserted else { return nil }
        do {
            let bundledCanonical = GenreNormalizer.normalize(rawGenre)
            if !GenreNormalizer.containsJapanese(bundledCanonical) {
                return try await resolveEnglishCanonical(
                    bundledCanonical,
                    rawGenre: rawGenre
                )
            }
            let japanesePage = try await searchJapaneseMusicPage(for: rawGenre)
            let englishPage = try await languagePage(
                code: "en",
                fromLanguage: "ja",
                pageKey: japanesePage.key
            )
            let englishSummary = try await summary(language: "en", pageKey: englishPage.key)
            let japaneseSummary = try? await summary(language: "ja", pageKey: japanesePage.key)
            let canonical = canonicalName(from: englishSummary.title)
            guard !canonical.isEmpty, !GenreNormalizer.containsJapanese(canonical) else { return nil }
            let knowledge = GenreKnowledge(
                rawGenre: rawGenre,
                canonicalName: canonical,
                summaryJapanese: japaneseSummary?.extract ?? "",
                summaryEnglish: englishSummary.extract,
                sourceTitle: englishSummary.title,
                sourceURL: wikipediaURL(language: "en", pageKey: englishPage.key),
                resolvedAt: Date()
            )
            try database.saveGenreKnowledge(knowledge)
            return knowledge
        } catch {
            return nil
        }
    }

    func resetTransientFailures() {
        attemptedRawKeys.removeAll()
    }

    private func resolveEnglishCanonical(
        _ canonical: String,
        rawGenre: String
    ) async throws -> GenreKnowledge {
        let englishPage = try await searchMusicPage(for: canonical, language: "en")
        let englishSummary = try await summary(language: "en", pageKey: englishPage.key)
        let japanesePage = try? await languagePage(
            code: "ja",
            fromLanguage: "en",
            pageKey: englishPage.key
        )
        let japaneseSummary: PageSummary?
        if let japanesePage {
            japaneseSummary = try? await summary(language: "ja", pageKey: japanesePage.key)
        } else {
            japaneseSummary = nil
        }
        let knowledge = GenreKnowledge(
            rawGenre: rawGenre,
            canonicalName: canonical,
            summaryJapanese: japaneseSummary?.extract ?? "",
            summaryEnglish: englishSummary.extract,
            sourceTitle: englishSummary.title,
            sourceURL: wikipediaURL(language: "en", pageKey: englishPage.key),
            resolvedAt: Date()
        )
        try database.saveGenreKnowledge(knowledge)
        return knowledge
    }

    private func searchJapaneseMusicPage(for rawGenre: String) async throws -> SearchPage {
        try await searchMusicPage(for: rawGenre, language: "ja")
    }

    private func searchMusicPage(for query: String, language: String) async throws -> SearchPage {
        let queries = [query, "\(query) music genre"]
        for query in queries {
            var components = URLComponents(string: "https://\(language).wikipedia.org/w/rest.php/v1/search/page")!
            components.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: "5")
            ]
            let response: SearchResponse = try await fetch(components.url!)
            if let match = response.pages
                .filter(isMusicRelated)
                .max(by: { candidateScore($0, query: query) < candidateScore($1, query: query) }) {
                return match
            }
        }
        throw ResolutionError.noMusicPage
    }

    private func languagePage(
        code: String,
        fromLanguage: String,
        pageKey: String
    ) async throws -> LanguagePage {
        let url = restURL(
            language: fromLanguage,
            path: ["page", pageKey, "links", "language"]
        )
        let pages: [LanguagePage] = try await fetch(url)
        guard let match = pages.first(where: { $0.code == code }) else {
            throw ResolutionError.noEnglishPage
        }
        return match
    }

    private func summary(language: String, pageKey: String) async throws -> PageSummary {
        try await fetch(restURL(language: language, path: ["api", "rest_v1", "page", "summary", pageKey], legacyAPI: true))
    }

    private func fetch<Value: Decodable>(_ url: URL) async throws -> Value {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ResolutionError.invalidResponse
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func restURL(
        language: String,
        path: [String],
        legacyAPI: Bool = false
    ) -> URL {
        var url = URL(string: "https://\(language).wikipedia.org")!
        if !legacyAPI {
            for component in ["w", "rest.php", "v1"] { url.append(path: component) }
        }
        for component in path { url.append(path: component) }
        return url
    }

    private func wikipediaURL(language: String, pageKey: String) -> URL {
        var url = URL(string: "https://\(language).wikipedia.org/wiki")!
        url.append(path: pageKey)
        return url
    }

    private func canonicalName(from pageTitle: String) -> String {
        let withoutQualifier = pageTitle.replacingOccurrences(
            of: #"\s*\((music|genre|style)\)\s*$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return GenreNormalizer.normalize(withoutQualifier)
    }

    private func isMusicRelated(_ page: SearchPage) -> Bool {
        let text = [page.title, page.description ?? "", page.excerpt ?? ""]
            .joined(separator: " ").lowercased()
        let signals = [
            "音楽", "楽曲", "ジャンル", "ロック", "ポップ", "民謡", "歌謡",
            "クラシック", "ヒップホップ", "電子音楽", "music", "genre"
        ]
        return signals.contains(where: text.contains)
    }

    private func candidateScore(_ page: SearchPage, query: String) -> Int {
        let queryKey = GenreNormalizer.lookupKey(query
            .replacingOccurrences(of: " music genre", with: ""))
        let titleKey = GenreNormalizer.lookupKey(page.title)
        var score = 10
        if titleKey == queryKey { score += 100 }
        else if titleKey.contains(queryKey) || queryKey.contains(titleKey) { score += 40 }
        if page.title.localizedCaseInsensitiveContains("list of")
            || page.title.contains("一覧") {
            score -= 50
        }
        return score
    }

    private enum ResolutionError: Error {
        case noMusicPage
        case noEnglishPage
        case invalidResponse
    }

    private struct SearchResponse: Decodable {
        let pages: [SearchPage]
    }

    private struct SearchPage: Decodable {
        let key: String
        let title: String
        let description: String?
        let excerpt: String?
    }

    private struct LanguagePage: Decodable {
        let code: String
        let key: String
        let title: String
    }

    private struct PageSummary: Decodable {
        let title: String
        let extract: String
    }
}
