import Foundation

public struct LocalGenrePrediction: Equatable, Sendable {
    public let genre: String
    public let confidence: Double
    public let matchedTerms: [String]

    public init(genre: String, confidence: Double, matchedTerms: [String]) {
        self.genre = genre
        self.confidence = confidence
        self.matchedTerms = matchedTerms
    }
}

/// A small, deterministic metadata classifier bundled with the app. It never
/// opens audio files and never sends metadata over the network.
public struct LocalGenreClassifier: Sendable {
    private struct Rule: Sendable {
        let genre: String
        let terms: [String]
    }

    private let rules: [Rule] = [
        Rule(genre: "Blues Rock", terms: ["blues rock"]),
        Rule(genre: "Progressive Rock", terms: ["progressive rock", "prog rock"]),
        Rule(genre: "Heavy Metal", terms: ["heavy metal", "death metal", "black metal", "thrash metal", "doom metal"]),
        Rule(genre: "Hip-Hop", terms: ["hip hop", "hip-hop", "ヒップホップ", "ラップ", " rap ", "trap music"]),
        Rule(genre: "Electronic", terms: ["electronic", "electronica", "techno", "trance", "synthwave", "drum and bass", "ambient", "edm", "テクノ", "電子音楽"]),
        Rule(genre: "Jazz", terms: ["jazz", "bebop", "be bop", "swing", "coltrane", "miles davis", "charlie parker", "ジャズ"]),
        Rule(genre: "Classical", terms: ["classical", "symphony", "concerto", "sonata", "orchestra", "mozart", "beethoven", "bach", "chopin", "vivaldi", "クラシック", "交響曲", "協奏曲"]),
        Rule(genre: "Blues", terms: ["blues", "delta blues", "chicago blues", "ブルース"]),
        Rule(genre: "R&B/Soul", terms: ["r&b", "rhythm and blues", "neo soul", "soul", "funk", "motown", "ソウル", "ファンク"]),
        Rule(genre: "Reggae", terms: ["reggae", "dancehall", "ska", "dub", "レゲエ"]),
        Rule(genre: "Country", terms: ["country", "bluegrass", "honky tonk", "カントリー"]),
        Rule(genre: "Folk", terms: ["folk", "singer songwriter", "singer-songwriter", "フォーク"]),
        Rule(genre: "Soundtrack", terms: ["soundtrack", "original motion picture", "film score", " ost ", "サウンドトラック", "劇伴"]),
        Rule(genre: "Latin", terms: ["bossa nova", "samba", "salsa", "flamenco", "latin", "ボサノバ", "サンバ"]),
        Rule(genre: "J-Pop", terms: ["j-pop", "jpop", "j pop", "ジェイポップ"]),
        Rule(genre: "K-Pop", terms: ["k-pop", "kpop", "k pop"]),
        Rule(genre: "Pop", terms: ["pop", "dance pop", "ポップ"]),
        Rule(genre: "Rock", terms: ["rock", "hard rock", "alternative", "punk", "grunge", "ロック", "パンク"]),
        Rule(genre: "Enka", terms: ["enka", "演歌"]),
    ]

    public init() {}

    public func classify(track: Track) -> LocalGenrePrediction {
        let existing = track.genre.trimmingCharacters(in: .whitespacesAndNewlines)
        if !existing.isEmpty, !["unknown", "other", "未判定", "不明"].contains(normalize(existing)) {
            return LocalGenrePrediction(genre: existing, confidence: 0.99, matchedTerms: [existing])
        }

        let searchable = " \(track.title) \(track.artist) \(track.album) \(track.albumArtist) \(track.filename) \(track.relativePath) "
        let normalized = normalize(searchable)
        var best: (rule: Rule, matches: [String])?
        for rule in rules {
            let matches = rule.terms.filter { normalized.contains(normalize($0)) }
            guard !matches.isEmpty else { continue }
            if best == nil || matches.count > best!.matches.count {
                best = (rule, matches)
            }
        }

        guard let best else {
            return LocalGenrePrediction(genre: "Other", confidence: 0.20, matchedTerms: [])
        }
        let confidence = min(0.88, 0.56 + Double(best.matches.count - 1) * 0.10)
        return LocalGenrePrediction(genre: best.rule.genre, confidence: confidence, matchedTerms: best.matches)
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}
