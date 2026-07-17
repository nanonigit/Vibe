import Foundation

public struct SecurityScopedRoot: Sendable {
    public let url: URL
    public let bookmark: Data
    public let isStale: Bool

    public init(url: URL, bookmark: Data, isStale: Bool = false) {
        self.url = url
        self.bookmark = bookmark
        self.isStale = isStale
    }

    public static func create(for url: URL) throws -> SecurityScopedRoot {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: [.volumeUUIDStringKey, .nameKey],
            relativeTo: nil
        )
        // The URL returned by NSOpenPanel carries only the panel's temporary
        // grant. Resolve the bookmark immediately so callers that cross an actor
        // boundary receive a URL backed by the persistent security scope.
        return try resolve(bookmark: bookmark)
    }

    public static func resolve(bookmark: Data) throws -> SecurityScopedRoot {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return SecurityScopedRoot(url: url, bookmark: bookmark, isStale: stale)
    }

    public func withAccess<T>(_ operation: (URL) throws -> T) throws -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try operation(url)
    }

    public func withAccess<T>(_ operation: (URL) async throws -> T) async throws -> T {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try await operation(url)
    }
}
