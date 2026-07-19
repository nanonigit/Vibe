import Foundation

public struct PageJumpEntry: Hashable, Identifiable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case backward
        case page
        case forward
    }

    public let target: Int
    public let label: String
    public let kind: Kind

    public var id: String { "\(kind.rawValue):\(label)" }

    public init(target: Int, label: String, kind: Kind) {
        self.target = target
        self.label = label
        self.kind = kind
    }
}

public enum PageNavigation {
    /// Keeps pagination bounded for very large libraries. Relative jumps are
    /// intentionally ordered around the local page window rather than sorted
    /// by their clamped destination.
    public static func entries(currentPage: Int, pageCount: Int) -> [PageJumpEntry] {
        guard pageCount > 0 else { return [] }
        let current = min(max(currentPage, 1), pageCount)

        if pageCount <= 15 {
            return (1...pageCount).map {
                PageJumpEntry(target: $0, label: String($0), kind: .page)
            }
        }

        let increments = [1_000, 100, 10]
        let backward = increments.filter { current - $0 >= 1 }.map {
            PageJumpEntry(
                target: current - $0,
                label: "-\($0)",
                kind: .backward
            )
        }
        let nearby = (max(1, current - 5)...min(pageCount, current + 5)).map {
            PageJumpEntry(target: $0, label: String($0), kind: .page)
        }
        let forward = increments.reversed().filter { current + $0 <= pageCount }.map {
            PageJumpEntry(
                target: current + $0,
                label: "+\($0)",
                kind: .forward
            )
        }
        return backward + nearby + forward
    }
}
