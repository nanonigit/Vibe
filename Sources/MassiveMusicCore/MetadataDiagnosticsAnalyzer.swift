import Foundation

public enum MetadataNormalizer {
    public static func key(_ value: String) -> String {
        let folded = value.precomposedStringWithCompatibilityMapping.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    public static func editDistance(_ lhs: String, _ rhs: String, maximum: Int = 2) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if abs(a.count - b.count) > maximum { return maximum + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...b.count {
                current[j] = min(
                    min(previous[j] + 1, current[j - 1] + 1),
                    previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                )
                rowMinimum = min(rowMinimum, current[j])
            }
            if rowMinimum > maximum { return maximum + 1 }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

public actor MetadataDiagnosticsAnalyzer {
    public typealias ProgressHandler = @Sendable (MetadataAnalysisProgress) -> Void
    private let database: LibraryDatabase

    public init(database: LibraryDatabase) { self.database = database }

    public func analyze(progress: ProgressHandler? = nil) async throws {
        try database.resetPendingMetadataAnalysis()
        var processed = 0
        var candidateCount = 0

        for field in MetadataField.allCases {
            var cursor: String?
            while true {
                try Task.checkCancellation()
                let page = try database.distinctMetadataTerms(field: field, after: cursor)
                if page.isEmpty { break }
                let terms = page.map { item -> (value: String, normalized: String, prefix: String, count: Int) in
                    let normalized = MetadataNormalizer.key(item.value)
                    return (item.value, normalized, String(normalized.prefix(3)), item.count)
                }
                try database.insertMetadataTerms(field: field, terms: terms)
                processed += page.count
                cursor = page.last?.value
                progress?(MetadataAnalysisProgress(
                    field: field, processedTerms: processed, candidates: candidateCount, isComplete: false
                ))
                if page.count < 1_000 { break }
                await Task.yield()
            }
        }

        candidateCount += try database.generateNormalizationCandidates()
        for field in MetadataField.allCases {
            var cursorPrefix: String?
            var cursorID: Int64?
            var activePrefix: String?
            var bucket: [MetadataTerm] = []
            var bucketOverflowed = false
            while true {
                try Task.checkCancellation()
                let page = try database.storedMetadataTerms(
                    field: field, afterPrefix: cursorPrefix, afterID: cursorID
                )
                if page.isEmpty { break }
                for stored in page {
                    if activePrefix != stored.prefix {
                        if !bucketOverflowed {
                            candidateCount += try compareTerms(bucket, field: field)
                        }
                        activePrefix = stored.prefix
                        bucket = []
                        bucketOverflowed = false
                    }
                    if bucket.count < 201 { bucket.append(stored.term) }
                    else { bucketOverflowed = true }
                }
                cursorPrefix = page.last?.prefix
                cursorID = page.last?.id
                progress?(MetadataAnalysisProgress(
                    field: field, processedTerms: processed, candidates: candidateCount, isComplete: false
                ))
                if page.count < 1_000 { break }
                await Task.yield()
            }
            if !bucketOverflowed { candidateCount += try compareTerms(bucket, field: field) }
        }
        candidateCount = try database.metadataVariationCount()
        progress?(MetadataAnalysisProgress(
            field: nil, processedTerms: processed, candidates: candidateCount, isComplete: true
        ))
    }

    private func compareTerms(_ terms: [MetadataTerm], field: MetadataField) throws -> Int {
        guard terms.count > 1, terms.count <= 200 else { return 0 }
        var inserted = 0
        for firstIndex in terms.indices.dropLast() {
            for secondIndex in terms.index(after: firstIndex)..<terms.endIndex {
                let first = terms[firstIndex]
                let second = terms[secondIndex]
                guard first.normalized != second.normalized else { continue }
                let maximum = max(first.normalized.count, second.normalized.count) >= 16 ? 2 : 1
                let distance = MetadataNormalizer.editDistance(first.normalized, second.normalized, maximum: maximum)
                if distance <= maximum,
                   try database.insertTypoCandidate(field: field, first: first, second: second, distance: distance) {
                    inserted += 1
                }
            }
        }
        return inserted
    }
}
