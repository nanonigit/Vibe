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
            CommandMenu(environment.model?.text("再生", "Controls") ?? "Controls") {
                Button(action: { environment.player?.togglePlayPause() }) {
                    Text(environment.player?.isPlaying == true ? (environment.model?.text("一時停止", "Pause") ?? "Pause") : (environment.model?.text("再生", "Play") ?? "Play"))
                }
                .keyboardShortcut(.space, modifiers: [])

                Button(action: { environment.player?.next() }) {
                    Text(environment.model?.text("次の曲", "Next Track") ?? "Next Track")
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button(action: { environment.player?.previous() }) {
                    Text(environment.model?.text("前の曲", "Previous Track") ?? "Previous Track")
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }
        }
    }
}

private struct PlayerWindowRoot: View {
    @ObservedObject var environment: AppEnvironment
    @State private var isMiniPlayer = false
    @State private var expandedFrame: NSRect?
    private let playerWindowFrameStorageKey = "player.window.expandedFrame.v1"

    private var miniPlayerBinding: Binding<Bool> {
        Binding(
            get: { isMiniPlayer },
            set: { mini in
                if mini,
                   let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
                    expandedFrame = window.frame
                    saveExpandedFrame(window.frame)
                }
                isMiniPlayer = mini
            }
        )
    }

    var body: some View {
        Group {
            if let model = environment.model, let player = environment.player {
                if isMiniPlayer {
                    MiniPlayerView(player: player, model: model, isMiniPlayer: miniPlayerBinding)
                        .preferredColorScheme(model.appearance.colorScheme)
                        .tint(model.appearance.palette.accent)
                        .background(model.appearance.palette.canvas)
                        .background(MiniPlayerWindowSizeLock(size: NSSize(width: 390, height: 132)))
                } else {
                    ContentView(model: model, player: player, isMiniPlayer: miniPlayerBinding)
                        .frame(minWidth: 980, minHeight: 640)
                        .preferredColorScheme(model.appearance.colorScheme)
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
        .onAppear {
            restoreWindowFrame()
            synchronizeWindowAppearance()
        }
        .onChange(of: isMiniPlayer) { _, mini in resizeWindow(mini: mini) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) {
            persistNormalWindowFrame(from: $0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) {
            persistNormalWindowFrame(from: $0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) {
            persistWindowFrameBeforeClosing(from: $0)
        }
    }

    private func synchronizeWindowAppearance() {
        guard let mode = environment.model?.appearance else { return }
        let appearance = NSAppearance(named: mode.isDark ? .darkAqua : .aqua)
        NSApplication.shared.appearance = appearance
        for window in NSApplication.shared.windows {
            window.appearance = appearance
            window.contentView?.needsDisplay = true
        }
    }

    private func resizeWindow(mini: Bool) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else { return }
            if mini {
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
                if let restoredFrame = expandedFrame {
                    window.setFrame(restoredFrame, display: true, animate: false)
                }
            }
            fit(window: window)
        }
    }

    private func restoreWindowFrame() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else { return }
            if let value = UserDefaults.standard.string(forKey: playerWindowFrameStorageKey) {
                let restoredFrame = NSRectFromString(value)
                if restoredFrame.width >= 980, restoredFrame.height >= 640 {
                    expandedFrame = restoredFrame
                    window.setFrame(restoredFrame, display: true, animate: false)
                }
            }
            fit(window: window)
        }
    }

    private func persistNormalWindowFrame(from notification: Notification) {
        guard !isMiniPlayer,
              let window = notification.object as? NSWindow,
              window == NSApplication.shared.keyWindow || window == NSApplication.shared.mainWindow else { return }
        expandedFrame = window.frame
        saveExpandedFrame(window.frame)
    }

    private func persistWindowFrameBeforeClosing(from notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window == NSApplication.shared.keyWindow || window == NSApplication.shared.mainWindow else { return }
        if isMiniPlayer {
            if let expandedFrame { saveExpandedFrame(expandedFrame) }
        } else {
            expandedFrame = window.frame
            saveExpandedFrame(window.frame)
        }
    }

    private func saveExpandedFrame(_ frame: NSRect) {
        guard !isMiniPlayer else {
            if let expandedFrame {
                UserDefaults.standard.set(NSStringFromRect(expandedFrame), forKey: playerWindowFrameStorageKey)
            }
            return
        }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: playerWindowFrameStorageKey)
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

struct WindowAppearanceSynchronizer: NSViewRepresentable {
    let mode: AppearanceMode

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let appearance = NSAppearance(named: mode.isDark ? .darkAqua : .aqua)
        DispatchQueue.main.async {
            NSApplication.shared.appearance = appearance
            for window in NSApplication.shared.windows {
                window.appearance = appearance
                window.contentView?.needsDisplay = true
            }
            nsView.window?.appearance = appearance
        }
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
