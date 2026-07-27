import AppKit
import SwiftUI

@main
struct MassiveMusicApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            PlayerWindowRoot(environment: environment)
        }
        .windowStyle(.hiddenTitleBar)
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
                        .background(MiniPlayerWindowSizeLock(size: NSSize(width: 390, height: 132)))
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
                let miniSize = NSSize(width: 390, height: 132)
                window.contentMinSize = miniSize
                window.contentMaxSize = miniSize
                window.setContentSize(miniSize)
                window.minSize = window.frame.size
                window.maxSize = window.frame.size
            } else {
                window.styleMask.insert(.resizable)
                window.standardWindowButton(.zoomButton)?.isEnabled = true
                window.contentMinSize = NSSize(width: 980, height: 640)
                window.contentMaxSize = NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
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

private struct MiniPlayerWindowSizeLock: NSViewRepresentable {
    let size: NSSize

    func makeNSView(context: Context) -> MiniPlayerWindowLockView {
        MiniPlayerWindowLockView(size: size)
    }

    func updateNSView(_ view: MiniPlayerWindowLockView, context: Context) {
        view.size = size
        view.lockWindowSize()
    }
}

private final class MiniPlayerWindowLockView: NSView {
    var size: NSSize
    private var resizeObserver: NSObjectProtocol?
    private var isApplyingSize = false

    init(size: NSSize) {
        self.size = size
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
        guard let window else { return }
        lockWindowSize()
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockWindowSize() }
        }
    }

    func lockWindowSize() {
        guard let window, !isApplyingSize else { return }
        isApplyingSize = true
        defer { isApplyingSize = false }
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.contentMinSize = size
        window.contentMaxSize = size
        if window.contentLayoutRect.size != size {
            window.setContentSize(size)
        }
        window.minSize = window.frame.size
        window.maxSize = window.frame.size
    }
}
