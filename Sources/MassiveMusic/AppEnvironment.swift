import Combine
import Foundation
import MassiveMusicCore

@MainActor
final class AppEnvironment: ObservableObject {
    let model: LibraryViewModel?
    let player: PlaybackController?
    let errorMessage: String?

    init() {
        do {
            let database = try LibraryDatabase(url: LibraryDatabase.applicationSupportURL())
            let scanner = LibraryScanner(database: database)
            let player = PlaybackController(database: database)
            self.player = player
            model = LibraryViewModel(database: database, scanner: scanner)
            errorMessage = nil
        } catch {
            model = nil
            player = nil
            errorMessage = error.localizedDescription
        }
    }
}

