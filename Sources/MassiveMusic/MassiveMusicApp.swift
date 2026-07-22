import AppKit
import SwiftUI

@main
struct MassiveMusicApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            PlayerWindowRoot(environment: environment)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1_280, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button(environment.model?.text("音楽フォルダを追加…", "Add Music Folder…") ?? "Add Music Folder…") {
                    environment.model?.chooseAndScanFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}

private struct PlayerWindowRoot: View {
    @ObservedObject var environment: AppEnvironment
    @State private var isMiniPlayer = false
    @State private var expandedSize = CGSize(width: 1_280, height: 800)

    var body: some View {
        Group {
            if let model = environment.model, let player = environment.player {
                if isMiniPlayer {
                    MiniPlayerView(player: player, model: model, isMiniPlayer: $isMiniPlayer)
                        .preferredColorScheme(model.appearance.colorScheme)
                } else {
                    ContentView(model: model, player: player, isMiniPlayer: $isMiniPlayer)
                        .frame(minWidth: 980, minHeight: 640)
                }
            } else {
                ContentUnavailableView(
                    "Vibeを起動できません",
                    systemImage: "exclamationmark.triangle",
                    description: Text(environment.errorMessage ?? "不明なエラー")
                )
                .frame(minWidth: 980, minHeight: 640)
            }
        }
        .onAppear { fitWindowToVisibleScreen() }
        .onChange(of: isMiniPlayer) { _, mini in resizeWindow(mini: mini) }
    }

    private func resizeWindow(mini: Bool) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else { return }
            if mini {
                expandedSize = window.contentLayoutRect.size
                window.styleMask.remove(.resizable)
                window.standardWindowButton(.zoomButton)?.isEnabled = false
                window.minSize = NSSize(width: 390, height: 180)
                window.maxSize = NSSize(width: 390, height: 180)
                window.setContentSize(NSSize(width: 390, height: 180))
            } else {
                window.styleMask.insert(.resizable)
                window.standardWindowButton(.zoomButton)?.isEnabled = true
                window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                window.minSize = NSSize(width: 980, height: 640)
                window.setContentSize(NSSize(width: max(980, expandedSize.width), height: max(640, expandedSize.height)))
            }
            fit(window: window)
        }
    }

    private func fitWindowToVisibleScreen() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else { return }
            fit(window: window)
        }
    }

    private func fit(window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        window.setFrame(frame, display: true, animate: false)
    }
}
