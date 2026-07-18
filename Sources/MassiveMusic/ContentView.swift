import MassiveMusicCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsTab: Hashable {
    case display
    case storage
    case offline
    case ai
}

private struct BatchMetadataEditRequest: Identifiable {
    let id = UUID()
    let tracks: [Track]
}

private struct SidebarNavigationLabel: View {
    let title: String
    let systemImage: String
    var trailingText: String? = nil
    var trailingColor: Color = .secondary

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 8)
            if let trailingText {
                Text(trailingText)
                    .foregroundStyle(trailingColor)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct ContentView: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var player: PlaybackController
    @Binding var isMiniPlayer: Bool
    @State private var showSettings = false
    @State private var settingsTab: SettingsTab = .display
    @State private var showInspector = true
    @State private var browserURL: URL?
    @State private var trackBeingEdited: Track?
    @State private var trackPendingDeletion: Track?
    @State private var tracksPendingDeletion: [Track]? = nil
    @State private var trackPendingFavoriteCache: Track?
    @State private var batchMetadataEditRequest: BatchMetadataEditRequest?
    @State private var selectionAnchorID: Int64?
    @State private var inspectorDragStartWidth: Double?
    @State private var isInspectorDividerHovered = false
    @AppStorage("inspector.width") private var inspectorWidth = 310.0
    @AppStorage("columns.title.width") private var titleColumnWidth = 150.0
    @AppStorage("columns.artist.width") private var artistColumnWidth = 150.0
    @AppStorage("columns.album.width") private var albumColumnWidth = 180.0
    @AppStorage("columns.discNumber.width") private var discNumberColumnWidth = 82.0
    @AppStorage("columns.trackNumber.width") private var trackNumberColumnWidth = 90.0
    @AppStorage("columns.duration.width") private var durationColumnWidth = 65.0
    @AppStorage("columns.title.visible") private var isTitleColumnVisible = true
    @AppStorage("columns.artist.visible") private var isArtistColumnVisible = true
    @AppStorage("columns.album.visible") private var isAlbumColumnVisible = true
    @AppStorage("columns.discNumber.visible") private var isDiscNumberColumnVisible = true
    @AppStorage("columns.trackNumber.visible") private var isTrackNumberColumnVisible = true
    @AppStorage("columns.duration.visible") private var isDurationColumnVisible = true
    @AppStorage("columns.format.visible") private var isFormatColumnVisible = true
    @AppStorage("columns.albumView.artist.visible") private var isAlbumViewArtistVisible = true
    @AppStorage("columns.albumView.songs.visible") private var isAlbumViewSongsVisible = true
    @AppStorage("columns.artistView.albums.visible") private var isArtistViewAlbumsVisible = true
    @AppStorage("columns.artistView.songs.visible") private var isArtistViewSongsVisible = true

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            HStack(spacing: 0) {
                libraryContent
                    .frame(minWidth: 420)
                if showInspector {
                    inspectorDivider
                    NowPlayingInspector(
                        model: model,
                        player: player,
                        browserURL: $browserURL,
                        openAISettings: {
                            settingsTab = .ai
                            showSettings = true
                        }
                    )
                        .frame(width: inspectorWidth)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                PlayerBar(player: player, model: model)
            }
        }
        .toolbar { toolbar }
        .onChange(of: player.currentTrack) { _, track in model.enrich(track) }
        .onChange(of: model.language) { _, _ in
            model.savePresentationSettings()
            model.enrich(player.currentTrack)
        }
        .onChange(of: model.appearance) { _, _ in model.savePresentationSettings() }
        .onChange(of: browserURL) { _, url in
            if url != nil {
                showInspector = true
                inspectorWidth = max(inspectorWidth, 480)
            }
        }
        .preferredColorScheme(model.appearance.colorScheme)
        .sheet(isPresented: $showSettings) { LibrarySettingsView(model: model, selectedTab: $settingsTab) }
        .sheet(item: $trackBeingEdited) { track in
            TrackMetadataEditor(model: model, track: track)
        }
        .sheet(item: $batchMetadataEditRequest, onDismiss: model.resetBatchMetadataProgress) { request in
            BatchTrackMetadataEditor(model: model, tracks: request.tracks)
        }
        .confirmationDialog(
            model.text("お気に入りに追加", "Add to Favorites"),
            isPresented: Binding(
                get: { trackPendingFavoriteCache != nil },
                set: { if !$0 { trackPendingFavoriteCache = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let track = trackPendingFavoriteCache {
                Button(model.text("追加してローカルに保存", "Add and Save Locally")) {
                    model.setFavorite(track, isFavorite: true, cacheLocally: true)
                    trackPendingFavoriteCache = nil
                }
                Button(model.text("お気に入りだけに追加", "Add to Favorites Only")) {
                    model.setFavorite(track, isFavorite: true)
                    trackPendingFavoriteCache = nil
                }
            }
            Button(model.text("キャンセル", "Cancel"), role: .cancel) {
                trackPendingFavoriteCache = nil
            }
        } message: {
            Text(model.text(
                "この曲をMac内のライブラリキャッシュにも保存しますか？ ローカル保存したお気に入りは、SSDが未接続でも再生できます。",
                "Also save this song in the Mac library cache? Locally saved favorites remain playable while the SSD is disconnected."
            ))
        }
        .confirmationDialog(
            model.text("曲を削除", "Delete Song"),
            isPresented: Binding(
                get: { trackPendingDeletion != nil || tracksPendingDeletion != nil },
                set: { if !$0 { trackPendingDeletion = nil; tracksPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let tracks = tracksPendingDeletion {
                Button(model.text("ライブラリからのみ削除", "Remove from Library Only"), role: .destructive) {
                    model.removeTracksFromLibrary(tracks)
                    tracksPendingDeletion = nil
                }
                Button(model.text("実ファイルをゴミ箱へ移動", "Move Source Files to Trash"), role: .destructive) {
                    model.moveFilesToTrash(tracks)
                    tracksPendingDeletion = nil
                }
            } else if let track = trackPendingDeletion {
                Button(model.text("ライブラリからのみ削除", "Remove from Library Only"), role: .destructive) {
                    model.removeFromLibrary(track)
                    trackPendingDeletion = nil
                }
                Button(model.text("実ファイルをゴミ箱へ移動", "Move Source File to Trash"), role: .destructive) {
                    model.moveFileToTrash(track)
                    trackPendingDeletion = nil
                }
            }
            Button(model.text("キャンセル", "Cancel"), role: .cancel) { trackPendingDeletion = nil; tracksPendingDeletion = nil }
        } message: {
            if let tracks = tracksPendingDeletion {
                Text(model.text(
                    "選択した\(tracks.count)曲をライブラリから削除しますか？\n「実ファイルをゴミ箱へ移動」を選ぶと、パソコンからファイルが削除されます。",
                    "Are you sure you want to delete the \(tracks.count) selected songs from the library?\nChoosing 'Move Source Files to Trash' will delete the files from your computer."
                ))
            } else if let track = trackPendingDeletion {
                Text(model.text(
                    "「\(track.title)」をライブラリから削除しますか？\n「実ファイルをゴミ箱へ移動」を選ぶと、パソコンからファイルが削除されます。",
                    "Are you sure you want to delete '\(track.title)' from the library?\nChoosing 'Move Source File to Trash' will delete the file from your computer."
                ))
            }
        }
        .confirmationDialog(
            model.text("古い／壊れたID3タグを変換・修復", "Convert or Repair ID3 Tag"),
            isPresented: Binding(
                get: { model.metadataRepairRequest != nil },
                set: { if !$0 { model.cancelMetadataRepair() } }
            ),
            titleVisibility: .visible
        ) {
            Button(model.text("ID3v2.3へ変換して保存", "Convert to ID3v2.3 and Save")) {
                model.confirmMetadataRepair()
            }
            Button(model.text("キャンセル", "Cancel"), role: .cancel) {
                model.cancelMetadataRepair()
            }
        } message: {
            Text(model.text(
                "古いID3v2.2以前または壊れたタグを作業コピー上でID3v2.3へ変換し、MP3音声が一切変わっていないことを確認してから元ファイルへ反映します。主要な曲情報と読み取れるジャケットは引き継ぎます。読み取れない追加情報は失われる場合があります。失敗時は元ファイルを復元します。",
                "MassiveMusic will convert a legacy ID3v2.2-or-earlier or damaged tag to ID3v2.3 on a working copy, verify that the MP3 audio is unchanged, then update the source. Primary metadata and recoverable artwork are preserved. Unreadable extra fields may be lost. Failures restore the original file."
            ))
        }
        .alert(model.text("エラー", "Error"), isPresented: Binding(
            get: { model.errorMessage != nil || player.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.dismissError()
                    player.dismissError()
                }
            }
        )) {
            Button("OK") {
                model.dismissError()
                player.dismissError()
            }
        } message: {
            Text(model.errorMessage ?? player.errorMessage ?? "")
        }
    }

    private var inspectorDivider: some View {
        ZStack {
            Rectangle()
                .fill(isInspectorDividerHovered || inspectorDragStartWidth != nil
                    ? Color.accentColor.opacity(0.16)
                    : Color.clear)
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: inspectorDragStartWidth == nil ? 1 : 2)
            Capsule()
                .fill(isInspectorDividerHovered || inspectorDragStartWidth != nil
                    ? Color.accentColor
                    : Color.secondary.opacity(0.68))
                .frame(
                    width: isInspectorDividerHovered || inspectorDragStartWidth != nil ? 6 : 4,
                    height: isInspectorDividerHovered || inspectorDragStartWidth != nil ? 72 : 52
                )
                .overlay {
                    VStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(Color(nsColor: .windowBackgroundColor)).frame(width: 2.5, height: 2.5)
                        }
                    }
                }
        }
        .frame(width: 18)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isInspectorDividerHovered)
        .animation(.easeOut(duration: 0.12), value: inspectorDragStartWidth != nil)
        .onHover { hovering in
            isInspectorDividerHovered = hovering
            if hovering { NSCursor.resizeLeftRight.push() }
            else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let start = inspectorDragStartWidth ?? inspectorWidth
                    inspectorDragStartWidth = start
                    inspectorWidth = min(600, max(260, start - value.translation.width))
                }
                .onEnded { _ in inspectorDragStartWidth = nil }
        )
        .onTapGesture(count: 2) { inspectorWidth = 310 }
        .help(model.text("ドラッグで幅を変更・ダブルクリックで元に戻す", "Drag to resize; double-click to reset"))
        .accessibilityLabel(model.text("再生情報パネルの幅を変更", "Resize Now Playing panel"))
    }

    private var sidebar: some View {
        List {
            Section(model.text("ライブラリ", "Library")) {
                ForEach(LibrarySection.allCases.filter { $0 != .playlists && $0 != .diagnostics && $0 != .activityLog }) { section in
                    Button {
                        model.changeSection(section)
                    } label: {
                        SidebarNavigationLabel(
                            title: model.sectionTitle(section), systemImage: icon(for: section)
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(model.section == section ? Color.accentColor : Color.primary)
                }
            }
            Section(model.text("管理", "Manage")) {
                Button { model.changeSection(.activityLog) } label: {
                    SidebarNavigationLabel(
                        title: model.sectionTitle(.activityLog), systemImage: icon(for: .activityLog)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(model.section == .activityLog ? Color.accentColor : Color.primary)
                Button { model.changeSection(.diagnostics) } label: {
                    SidebarNavigationLabel(
                        title: model.sectionTitle(.diagnostics), systemImage: icon(for: .diagnostics)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(model.section == .diagnostics ? Color.accentColor : Color.primary)
                Button {
                    settingsTab = .storage
                    showSettings = true
                } label: {
                    SidebarNavigationLabel(
                        title: model.text("保存先・受信箱", "Storage & Inbox"), systemImage: "internaldrive"
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    settingsTab = .storage
                    showSettings = true
                } label: {
                    SidebarNavigationLabel(
                        title: model.text("SSDとの差分", "Storage Differences"),
                        systemImage: "arrow.left.arrow.right",
                        trailingText: model.unavailableTrackCount.formatted(),
                        trailingColor: model.unavailableTrackCount > 0 ? .orange : .secondary
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

            }
            Section {
                ForEach(model.playlists) { playlist in
                    Button {
                        model.selectPlaylist(playlist.id)
                    } label: {
                        SidebarNavigationLabel(
                            title: playlist.name, systemImage: "music.note.list",
                            trailingText: playlist.itemCount.formatted()
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(model.selectedPlaylistID == playlist.id ? Color.accentColor : Color.primary)
                    .contextMenu {
                        Button(model.text("名前を変更…", "Rename…")) {
                            model.selectPlaylist(playlist.id)
                            model.renameSelectedPlaylist()
                        }
                        Button(model.text("削除", "Delete"), role: .destructive) {
                            model.deletePlaylist(id: playlist.id)
                        }
                    }
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        handleDroppedProviders(providers, playlistID: playlist.id)
                        return true
                    }
                }
            } header: {
                HStack {
                    Text(model.text("プレイリスト", "Playlists"))
                    Spacer()
                    Button(action: model.createPlaylist) { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = model.driveMessage {
                Label(message, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
        }
    }

    private var libraryContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                ZStack(alignment: .top) {
                    if model.section == .activityLog {
                        activityLogView
                    } else if model.section == .diagnostics {
                        metadataDiagnosticsView
                    } else if model.selectedAlbum != nil || model.selectedArtist?.name.isEmpty == true {
                        trackTable
                    } else if model.selectedArtist != nil || model.section == .albums {
                        albumSummaryList
                    } else if model.selectedGenre != nil {
                        genreDetailContent
                    } else if model.section == .artists {
                        artistSummaryList
                    } else if model.section == .genres || model.section == .folders {
                        facetList
                    } else {
                        trackTable
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if model.supportsAlphabetIndex {
                    Divider()
                    alphabetIndexRail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            pageControls
            if [.running, .paused].contains(model.scanProgress.state) { scanStatus }
            if model.importProgress.state != .idle { importStatus }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDroppedProviders(providers)
            return true
        }
    }

    private var alphabetIndexRail: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 3) {
                Text(model.text("索引", "Index"))
                    .font(.caption2.bold()).foregroundStyle(.secondary)
                ForEach(alphabetIndexTokens, id: \.self) { token in
                    Button(token) {
                        model.selectedIndexToken = token
                        model.jumpToIndex(token)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.bold())
                    .frame(width: 25, height: 23)
                    .background(model.selectedIndexToken == token ? Color.accentColor : Color.secondary.opacity(0.09), in: Capsule())
                    .foregroundStyle(model.selectedIndexToken == token ? Color.white : Color.primary)
                    .help(model.text("「\(token)」から始まる位置へ移動", "Jump to entries beginning at \(token)"))
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 7)
        }
        .frame(width: 39)
        .background(.bar)
    }

    private var alphabetIndexTokens: [String] {
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
            + ["あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ",
               "さ", "し", "す", "せ", "そ", "た", "ち", "つ", "て", "と",
               "な", "に", "ぬ", "ね", "の", "は", "ひ", "ふ", "へ", "ほ",
               "ま", "み", "む", "め", "も", "や", "ゆ", "よ", "ら", "り",
               "る", "れ", "ろ", "わ", "を", "ん"]
            + (0...9).map(String.init)
    }

    private var header: some View {
        HStack(spacing: 12) {
            headerIdentity
                .frame(maxWidth: .infinity, alignment: .leading)
            headerControls
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var headerIdentity: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.isInDetail {
                Button(action: model.closeDetail) { Label(model.text("戻る", "Back"), systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if model.selectedPlaylistID != nil {
                Button {
                    model.renameSelectedPlaylist()
                } label: {
                    Text(headerTitle)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.text("クリックしてプレイリスト名を変更", "Click to rename playlist"))
            } else {
                let hideTitle = [.favorites, .cache].contains(model.section) && model.selectedAlbum == nil && model.selectedArtist == nil && model.selectedGenre == nil
                if !hideTitle {
                    Text(headerTitle)
                        .font(.title2.bold())
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            if let album = model.selectedAlbum {
                HStack(spacing: 8) {
                    Button { model.openArtist(named: album.artist) } label: {
                        Text(model.displayArtist(album.artist))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .buttonStyle(.link)
                    Text(model.text("\(model.totalCount.formatted())曲", "\(model.totalCount.formatted()) songs"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
            } else if let artist = model.selectedArtist {
                Text(model.text("\(artist.albumCount.formatted())アルバム・\(artist.trackCount.formatted())曲", "\(artist.albumCount.formatted()) albums · \(artist.trackCount.formatted()) songs"))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if model.selectedGenre != nil {
                Text(model.text("\(model.genreDetailTitle(model.genreDetailMode))・\(model.totalCount.formatted()) 件", "\(model.genreDetailTitle(model.genreDetailMode)) · \(model.totalCount.formatted()) items"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(model.text("\(model.totalCount.formatted()) 件", "\(model.totalCount.formatted()) items"))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                if model.section == .cache {
                    Text(model.localCacheDirectoryPath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.localCacheDirectoryPath)
                }
            }
            if showsStorageSummary, let summary = model.headerStorageSummary {
                Text(model.text(
                    "容量: \(formattedGigabytes(summary.totalBytes)) GB",
                    "Size: \(formattedGigabytes(summary.totalBytes)) GB"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                ForEach(summary.absoluteRootPaths, id: \.self) { path in
                    Text(model.text("絶対パス: \(path)", "Absolute path: \(path)"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var showsStorageSummary: Bool {
        model.selectedAlbum != nil || model.selectedArtist != nil || [.tracks, .albums, .artists].contains(model.section)
    }

    private func formattedGigabytes(_ bytes: Int64) -> String {
        let gigabytes = Double(max(0, bytes)) / 1_000_000_000
        return gigabytes.formatted(.number.precision(.fractionLength(gigabytes >= 100 ? 1 : 2)))
    }

    private var headerControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                if model.section == .cache { cacheHeaderControls }
                nonCacheHeaderControls
            }
            VStack(alignment: .trailing, spacing: 10) {
                if model.section == .cache { cacheHeaderControls }
                nonCacheHeaderControls
            }
        }
    }

    private var cacheHeaderControls: some View {
        HStack(spacing: 12) {
            Toggle(model.text("再生時に保存", "Save When Played"), isOn: $model.cacheEnabled)
                .toggleStyle(.switch)
                .onChange(of: model.cacheEnabled) { _, _ in model.saveCacheSettings() }
            Stepper(
                model.text("保持: \(model.cacheTrackLimit)曲", "Keep: \(model.cacheTrackLimit) songs"),
                value: $model.cacheTrackLimit,
                in: 0...500
            )
            .fixedSize()
            .onChange(of: model.cacheTrackLimit) { _, _ in model.saveCacheSettings() }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var nonCacheHeaderControls: some View {
        HStack(spacing: 12) {
            if model.section == .activityLog {
                Picker(model.text("種類", "Type"), selection: $model.activityKindFilter) {
                    Text(model.text("すべて", "All")).tag(LibraryActivityKind?.none)
                    ForEach(LibraryActivityKind.allCases) { kind in
                        Text(activityKindTitle(kind)).tag(Optional(kind))
                    }
                }
                .frame(width: 180)
                .onChange(of: model.activityKindFilter) { _, kind in model.changeActivityKind(kind) }
            }
            if model.selectedGenre != nil, model.selectedAlbum == nil, model.selectedArtist == nil {
                Picker(model.text("表示", "View"), selection: $model.genreDetailMode) {
                    ForEach(GenreDetailMode.allCases) { mode in
                        Text(model.genreDetailTitle(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
                .onChange(of: model.genreDetailMode) { _, mode in model.changeGenreDetailMode(mode) }
            }

            if showsTrackColumns || [.albums, .artists].contains(model.section) || model.selectedArtist != nil {
                if selectedTracksOnPage.count > 1 && showsTrackColumns {
                    Button { openBatchMetadataEditor() } label: {
                        Label(
                            model.text("\(selectedTracksOnPage.count)曲を一括編集", "Edit \(selectedTracksOnPage.count) Songs"),
                            systemImage: "square.and.pencil"
                        )
                    }
                    .help(model.text("選択した曲の共通情報を一括変更", "Bulk edit shared metadata for selected songs"))
                }
                Menu {
                    if (model.section == .albums || model.selectedArtist != nil) && model.selectedAlbum == nil {
                        columnVisibilityButton(model.text("アーティスト", "Artist"), isVisible: $isAlbumViewArtistVisible)
                        columnVisibilityButton(model.text("曲数", "Songs"), isVisible: $isAlbumViewSongsVisible)
                    } else if model.section == .artists && model.selectedArtist == nil {
                        columnVisibilityButton(model.text("アルバム数", "Albums"), isVisible: $isArtistViewAlbumsVisible)
                        columnVisibilityButton(model.text("曲数", "Songs"), isVisible: $isArtistViewSongsVisible)
                    } else {
                        columnVisibilityButton(model.text("タイトル", "Title"), isVisible: $isTitleColumnVisible)
                        columnVisibilityButton(model.text("アーティスト", "Artist"), isVisible: $isArtistColumnVisible)
                        columnVisibilityButton(model.text("アルバム", "Album"), isVisible: $isAlbumColumnVisible)
                        columnVisibilityButton(model.text("ディスク番号", "Disc Number"), isVisible: $isDiscNumberColumnVisible)
                        columnVisibilityButton(model.text("トラック番号", "Track Number"), isVisible: $isTrackNumberColumnVisible)
                        columnVisibilityButton(model.text("時間", "Duration"), isVisible: $isDurationColumnVisible)
                        columnVisibilityButton(model.text("形式", "Format"), isVisible: $isFormatColumnVisible)
                    }
                } label: {
                    Label(model.text("表示項目", "Columns"), systemImage: "rectangle.3.group")
                }
                .help(model.text("表示する列を選択", "Choose visible columns"))
            }
            if model.section != .diagnostics {
                LibrarySearchField(model: model)
            }
        }
    }

    private var selectedTracksOnPage: [Track] {
        model.tracks.filter { model.selectedTrackIDs.contains($0.id) }
    }

    private var currentSelectionModifiers: NSEvent.ModifierFlags {
        NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
    }

    private var hasSelectionModifier: Bool {
        let modifiers = currentSelectionModifiers
        return modifiers.contains(.command) || modifiers.contains(.shift)
    }

    private func handleTrackSelection(_ track: Track, at index: Int) {
        let modifiers = currentSelectionModifiers
        if modifiers.contains(.shift),
           let anchorID = selectionAnchorID,
           let anchorIndex = model.tracks.firstIndex(where: { $0.id == anchorID }) {
            let range = min(anchorIndex, index)...max(anchorIndex, index)
            let rangeIDs = Set(range.map { model.tracks[$0].id })
            if modifiers.contains(.command) {
                model.selectedTrackIDs.formUnion(rangeIDs)
            } else {
                model.selectedTrackIDs = rangeIDs
            }
        } else if modifiers.contains(.command) {
            if model.selectedTrackIDs.contains(track.id) {
                model.selectedTrackIDs.remove(track.id)
            } else {
                model.selectedTrackIDs.insert(track.id)
            }
            selectionAnchorID = track.id
        } else {
            model.selectedTrackIDs = [track.id]
            selectionAnchorID = track.id
        }
    }

    private func openBatchMetadataEditor() {
        let selected = selectedTracksOnPage
        guard selected.count > 1 else { return }
        model.resetBatchMetadataProgress()
        batchMetadataEditRequest = BatchMetadataEditRequest(tracks: selected)
    }

    private var trackTable: some View {
        GeometryReader { geometry in
            let contentWidth = max(geometry.size.width, trackContentWidth)
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    TrackSortHeader(
                        model: model,
                        titleWidth: $titleColumnWidth,
                        artistWidth: $artistColumnWidth,
                        albumWidth: $albumColumnWidth,
                        discNumberWidth: $discNumberColumnWidth,
                        trackNumberWidth: $trackNumberColumnWidth,
                        durationWidth: $durationColumnWidth,
                        showTitle: isTitleColumnVisible,
                        showArtist: isArtistColumnVisible,
                        showAlbum: isAlbumColumnVisible,
                        showDiscNumber: isDiscNumberColumnVisible,
                        showTrackNumber: isTrackNumberColumnVisible,
                        showDuration: isDurationColumnVisible,
                        showFormat: isFormatColumnVisible
                    )
                    .frame(width: contentWidth, alignment: .leading)
                    Divider()
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.tracks.enumerated()), id: \.element.id) { index, track in
                                HStack(spacing: 8) {
                                Button {
                                    if track.isFavorite {
                                        model.setFavorite(track, isFavorite: false)
                                    } else {
                                        trackPendingFavoriteCache = track
                                    }
                                } label: {
                                    Image(systemName: track.isFavorite ? "star.fill" : "star")
                                        .foregroundStyle(track.isFavorite ? .yellow : .secondary)
                                        .frame(width: 30)
                                }
                                .buttonStyle(.plain)
                                .help(track.isFavorite ? model.text("お気に入りから外す", "Remove from Favorites") : model.text("お気に入りに追加", "Add to Favorites"))
                                if isTitleColumnVisible {
                                     TrackTitleCell(track: track, helpText: track.isAvailable ? "" : model.text("保管先ストレージが未接続です（ローカルキャッシュからのみ再生可能）", "Storage destination is disconnected (Playable only via local cache)")).frame(width: titleColumnWidth, alignment: .leading)
                                }
                                if isArtistColumnVisible {
                                    TrackNavigationCell(
                                        title: model.displayArtist(track.artist),
                                        width: artistColumnWidth
                                    ) {
                                        if hasSelectionModifier {
                                            handleTrackSelection(track, at: index)
                                        } else {
                                            model.openArtist(named: track.artist)
                                        }
                                    }
                                }
                                if isAlbumColumnVisible {
                                    TrackNavigationCell(title: track.album, width: albumColumnWidth) {
                                        if hasSelectionModifier {
                                            handleTrackSelection(track, at: index)
                                        } else {
                                            model.openAlbum(AlbumSummary(
                                                name: track.album,
                                                artist: track.artist,
                                                trackCount: 0
                                            ))
                                        }
                                    }
                                    .disabled(track.album.isEmpty)
                                }
                                if isDiscNumberColumnVisible {
                                    Text(track.discNumber.map(String.init) ?? "—")
                                        .monospacedDigit()
                                        .foregroundStyle(track.discNumber == nil ? .secondary : .primary)
                                        .frame(width: discNumberColumnWidth, alignment: .leading)
                                }
                                if isTrackNumberColumnVisible {
                                    Text(track.trackNumber.map(String.init) ?? "—")
                                        .monospacedDigit()
                                        .foregroundStyle(track.trackNumber == nil ? .secondary : .primary)
                                        .frame(width: trackNumberColumnWidth, alignment: .leading)
                                }
                                if isDurationColumnVisible {
                                    Text(formatDuration(track.duration)).monospacedDigit().frame(width: durationColumnWidth, alignment: .leading)
                                }
                                if isFormatColumnVisible {
                                    Text(track.format.uppercased()).frame(width: 55, alignment: .leading)
                                }
                                }
                                .padding(.horizontal, 8)
                                .frame(width: contentWidth, height: 32, alignment: .leading)
                                .background(model.selectedTrackIDs.contains(track.id) ? Color.accentColor.opacity(0.28) : (track.id.isMultiple(of: 2) ? Color.secondary.opacity(0.06) : Color.clear))
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    if hasSelectionModifier {
                                        handleTrackSelection(track, at: index)
                                    } else {
                                        model.selectedTrackIDs = [track.id]
                                        selectionAnchorID = track.id
                                        if let context = model.trackPlaybackContext {
                                            player.playFromList(track, context: context)
                                        } else {
                                            player.play(track)
                                        }
                                    }
                                }
                                .onTapGesture { handleTrackSelection(track, at: index) }
                                .contextMenu { trackContextMenu(track) }
                            }
                        }
                    }
                    .frame(width: contentWidth, height: max(0, geometry.size.height - 32), alignment: .top)
                }
                .frame(width: contentWidth, height: geometry.size.height, alignment: .topLeading)
            }
            .id(trackTableContextID)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if model.isLoading { ProgressView().controlSize(.large) }
            else if model.tracks.isEmpty {
                if model.section == .cache {
                    ContentUnavailableView(
                        model.text("キャッシュされた曲がありません", "No Cached Songs"),
                        systemImage: "internaldrive",
                        description: Text(model.text(
                            "曲を再生するか、曲の右クリックメニューからローカルにキャッシュできます。",
                            "Play a song or use Cache Locally from its context menu."
                        ))
                    )
                } else {
                    ContentUnavailableView(model.text("曲がありません", "No Songs"), systemImage: "music.note", description: Text(model.text("音楽フォルダを追加してください。", "Add a music folder.")))
                }
            }
        }
    }

    private var trackTableContextID: String {
        [
            model.section.rawValue,
            model.selectedPlaylistID.map(String.init) ?? "",
            model.selectedAlbum.map { "\($0.artist)|\($0.name)" } ?? "",
            model.selectedArtist?.name ?? "",
            model.selectedGenre ?? "",
            model.genreDetailMode.rawValue
        ].joined(separator: "::")
    }

    @ViewBuilder
    private func trackContextMenu(_ track: Track) -> some View {
        Button(model.text("次に再生", "Play Next")) { player.addToUpNext(track) }
        if model.isStorageExternal {
            if model.isCached(track) {
                Button(model.text("ローカルキャッシュから削除", "Remove from Local Cache"), role: .destructive) {
                    model.removeTrackFromCache(track)
                }
            } else {
                Button {
                    model.cacheTrack(track)
                } label: {
                    if model.cachingTrackIDs.contains(track.id) {
                        Text(model.text("キャッシュ中…", "Caching…"))
                    } else {
                        Text(model.text("ローカルにキャッシュ", "Cache Locally"))
                    }
                }
                .disabled(model.cachingTrackIDs.contains(track.id))
            }
            Divider()
        }
        Menu(model.text("プレイリストに追加", "Add to Playlist")) {
            ForEach(model.playlists) { playlist in
                Button(playlist.name) {
                    if !model.selectedTrackIDs.contains(track.id) { model.selectedTrackIDs = [track.id] }
                    model.addSelectionToPlaylist(playlist.id)
                }
            }
        }
        Divider()
        if model.selectedTrackIDs.contains(track.id), selectedTracksOnPage.count > 1 {
            Button(model.text(
                "選択した\(selectedTracksOnPage.count)曲を一括編集…",
                "Bulk Edit \(selectedTracksOnPage.count) Selected Songs…"
            )) { openBatchMetadataEditor() }
        }
        Button(model.text("この曲の情報を編集…", "Edit This Song…")) { trackBeingEdited = track }
        if model.selectedTrackIDs.contains(track.id), selectedTracksOnPage.count > 1 {
            Button(model.text("選択した\(selectedTracksOnPage.count)曲を削除…", "Delete \(selectedTracksOnPage.count) Selected Songs…"), role: .destructive) {
                tracksPendingDeletion = selectedTracksOnPage
            }
        } else {
            Button(model.text("削除…", "Delete…"), role: .destructive) { trackPendingDeletion = track }
        }
        if model.selectedPlaylistID != nil {
            Button(model.text("上へ移動", "Move Up")) { model.moveTrackInSelectedPlaylist(track.id, by: -1) }
            Button(model.text("下へ移動", "Move Down")) { model.moveTrackInSelectedPlaylist(track.id, by: 1) }
            Button(model.text("プレイリストから削除", "Remove from Playlist"), role: .destructive) {
                model.selectedTrackIDs = [track.id]
                model.removeSelectionFromPlaylist()
            }
        }
    }

    private var albumSummaryList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                albumHeaderButton(.name, title: model.text("アルバム", "Album"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isAlbumViewArtistVisible {
                    albumHeaderButton(.artist, title: model.text("アーティスト", "Artist"))
                        .frame(width: 260, alignment: .leading)
                }
                if isAlbumViewSongsVisible {
                    albumHeaderButton(.trackCount, title: model.text("曲数", "Songs"))
                        .frame(width: 80, alignment: .trailing)
                }
                Spacer().frame(width: 28)
            }
            .font(.caption.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
            Divider()
            List(model.albumSummaries) { album in
                HStack {
                    Button { model.openAlbum(album) } label: { Label(album.name, systemImage: "square.stack").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                    if isAlbumViewArtistVisible {
                        Button(model.displayArtist(album.artist)) { model.openArtist(named: album.artist) }.buttonStyle(.link).frame(width: 260, alignment: .leading).lineLimit(1)
                    }
                    if isAlbumViewSongsVisible {
                        Text(album.trackCount.formatted()).frame(width: 80, alignment: .trailing).monospacedDigit()
                    }
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary).frame(width: 20)
                }.padding(.vertical, 3)
            }
        }
    }

    private func albumHeaderButton(_ sort: AlbumSort, title: String) -> some View {
        let isActive = model.albumSort == sort
        return Button {
            model.albumSortChanged(to: sort)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .fontWeight(isActive ? .bold : .regular)
                if isActive {
                    Image(systemName: model.albumSortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity, alignment: sort == .trackCount ? .trailing : .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor.opacity(0.7) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.text("クリックして並び順を変更", "Click to change sort order"))
    }

    private var artistSummaryList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                artistHeaderButton(.name, title: model.text("アーティスト", "Artist"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isArtistViewAlbumsVisible {
                    artistHeaderButton(.albumCount, title: model.text("アルバム数", "Albums"))
                        .frame(width: 100, alignment: .trailing)
                }
                if isArtistViewSongsVisible {
                    artistHeaderButton(.trackCount, title: model.text("曲数", "Songs"))
                        .frame(width: 100, alignment: .trailing)
                }
                Spacer().frame(width: 28)
            }
            .font(.caption.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
            Divider()
            List(model.artistSummaries) { artist in
                Button { model.openArtist(artist) } label: {
                    HStack {
                        Label(model.displayArtist(artist.name), systemImage: artist.name.isEmpty ? "person.crop.circle.badge.questionmark" : "music.mic").frame(maxWidth: .infinity, alignment: .leading)
                        if isArtistViewAlbumsVisible {
                            Text(artist.albumCount.formatted()).frame(width: 100, alignment: .trailing).monospacedDigit()
                        }
                        if isArtistViewSongsVisible {
                            Text(artist.trackCount.formatted()).frame(width: 100, alignment: .trailing).monospacedDigit()
                        }
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary).frame(width: 20)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.vertical, 3)
            }
        }
    }

    private func artistHeaderButton(_ sort: ArtistSort, title: String) -> some View {
        let isActive = model.artistSort == sort
        return Button {
            model.artistSortChanged(to: sort)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .fontWeight(isActive ? .bold : .regular)
                if isActive {
                    Image(systemName: model.artistSortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity, alignment: sort == .name ? .leading : .trailing)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor.opacity(0.7) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.text("クリックして並び順を変更", "Click to change sort order"))
    }

    private var facetList: some View {
        List(model.facets) { facet in
            if model.section == .genres {
                Button { model.openGenre(facet.name) } label: {
                    HStack {
                        Image(systemName: icon(for: model.section)).frame(width: 24)
                        Text(facet.name)
                        Spacer()
                        Text(facet.count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            } else {
                HStack {
                    Image(systemName: icon(for: model.section)).frame(width: 24)
                    Text(facet.name)
                    Spacer()
                    Text(facet.count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var activityLogView: some View {
        List(model.activityEvents) { event in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: activityKindIcon(event.kind))
                    .font(.title3)
                    .foregroundStyle(activityKindColor(event.kind))
                    .frame(width: 28, height: 28)
                    .background(activityKindColor(event.kind).opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(activityKindTitle(event.kind)).font(.headline)
                        Text(event.title.isEmpty ? event.filename : event.title)
                            .fontWeight(.semibold).lineLimit(1)
                        Spacer(minLength: 16)
                        Text(event.occurredAt.formatted(date: .abbreviated, time: .standard))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    if !event.artist.isEmpty || !event.album.isEmpty {
                        Text([event.artist, event.album].filter { !$0.isEmpty }.joined(separator: " — "))
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    ForEach(event.changes.prefix(4), id: \.self) { change in
                        HStack(spacing: 6) {
                            Text(activityFieldTitle(change.field)).fontWeight(.medium)
                            Text(change.oldValue.isEmpty ? model.text("（空）", "(empty)") : change.oldValue)
                                .foregroundStyle(.secondary).lineLimit(1)
                            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                            Text(change.newValue.isEmpty ? model.text("（空）", "(empty)") : change.newValue)
                                .lineLimit(1)
                        }
                        .font(.caption)
                    }
                    if event.changes.count > 4 {
                        Text(model.text("ほか\(event.changes.count - 4)件の変更", "\(event.changes.count - 4) more changes"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(event.absolutePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                        .help(event.absolutePath).textSelection(.enabled)
                }
            }
            .padding(.vertical, 5)
        }
        .overlay {
            if !model.isLoading && model.activityEvents.isEmpty {
                ContentUnavailableView(
                    model.text("ログはまだありません", "No Activity Yet"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(model.text(
                        "スキャンや曲情報の編集、ライブラリからの削除がここに記録されます。",
                        "Scans, metadata edits, and library removals will appear here."
                    ))
                )
            }
        }
    }

    @ViewBuilder private var genreDetailContent: some View {
        switch model.genreDetailMode {
        case .albums: albumSummaryList
        case .artists: artistSummaryList
        case .tracks: trackTable
        }
    }

    private var metadataDiagnosticsView: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MetadataIssueKind.allCases) { kind in
                        Button { model.selectDiagnostic(kind) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Label(diagnosticTitle(kind), systemImage: diagnosticIcon(kind))
                                Text(diagnosticCount(kind).formatted())
                                    .font(.title3.bold()).monospacedDigit()
                            }
                            .frame(minWidth: 150, alignment: .leading)
                            .padding(10)
                            .background(model.diagnosticKind == kind ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
            Divider()
            if model.diagnosticKind == .suspectedVariations {
                HStack {
                    if model.isAnalyzingMetadata {
                        ProgressView().controlSize(.small)
                        Text(model.text(
                            "\(model.metadataAnalysisProgress.processedTerms.formatted())件を確認・\(model.metadataAnalysisProgress.candidates.formatted())候補",
                            "Checked \(model.metadataAnalysisProgress.processedTerms.formatted()) terms · \(model.metadataAnalysisProgress.candidates.formatted()) candidates"
                        )).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(model.text("キャンセル", "Cancel"), action: model.cancelMetadataAnalysis)
                    } else {
                        Text(model.text("候補は自動変更せず、確認用に表示します。", "Candidates are shown for review; nothing is changed automatically."))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(model.text("表記ゆれを解析", "Analyze Variations"), action: model.runMetadataAnalysis)
                    }
                }.padding(10)
                Divider()
                List(model.variationCandidates) { candidate in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(metadataFieldTitle(candidate.field)).font(.caption.bold()).foregroundStyle(.secondary)
                                Text(variationReason(candidate)).font(.caption).foregroundStyle(.orange)
                            }
                            Button("\(candidate.valueA)  (\(candidate.trackCountA.formatted()))") { model.searchVariationValue(candidate.valueA) }
                                .buttonStyle(.link).lineLimit(1)
                            Button("\(candidate.valueB)  (\(candidate.trackCountB.formatted()))") { model.searchVariationValue(candidate.valueB) }
                                .buttonStyle(.link).lineLimit(1)
                        }
                        Spacer()
                        Button(model.text("候補から除外", "Ignore")) { model.ignoreVariation(candidate) }
                    }.padding(.vertical, 4)
                }
                .overlay {
                    if !model.isAnalyzingMetadata && model.variationCandidates.isEmpty {
                        ContentUnavailableView(
                            model.text("表記ゆれ候補はまだありません", "No Variation Candidates Yet"),
                            systemImage: "text.magnifyingglass",
                            description: Text(model.text("「表記ゆれを解析」をクリックしてください。", "Click Analyze Variations to scan the library."))
                        )
                    }
                }
            } else {
                trackTable
            }
        }
    }

    private var pageControls: some View {
        HStack {
            Button(action: model.previousPage) { Label(model.text("前へ", "Previous"), systemImage: "chevron.left") }
                .disabled(!model.canGoPrevious)
            Text(model.text("ページ \(model.currentPageNumber) / \(model.pageCount)", "Page \(model.currentPageNumber) / \(model.pageCount)"))
                .font(.caption).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(pageJumpEntries) { entry in
                        Button(entry.label) { model.goToPage(entry.target) }
                            .buttonStyle(.plain)
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(
                                entry.kind == .page && entry.target == model.currentPageNumber ? Color.accentColor : Color.clear,
                                in: Capsule()
                            )
                            .foregroundStyle(
                                entry.kind == .page && entry.target == model.currentPageNumber ? Color.white : Color.primary
                            )
                    }
                }
            }
            .frame(maxWidth: 900)
            Button(action: model.nextPage) { Label(model.text("次へ", "Next"), systemImage: "chevron.right") }
                .disabled(!model.canGoNext)
        }
        .padding(8)
    }

    private var pageJumpEntries: [PageJumpEntry] {
        PageNavigation.entries(currentPage: model.currentPageNumber, pageCount: model.pageCount)
    }

    private var scanStatus: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(model.text("\(model.scanProgress.processed.formatted()) 曲", "\(model.scanProgress.processed.formatted()) songs"))
            let speed = String(format: "%.1f", model.scanProgress.tracksPerSecond)
            Text(model.text("\(speed) 曲/秒", "\(speed) songs/sec"))
            if model.scanProgress.errors > 0 {
                Label(model.text("\(model.scanProgress.errors) エラー", "\(model.scanProgress.errors) errors"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Text(model.scanProgress.currentPath).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            Spacer()
            if model.scanProgress.state == .paused {
                Button(model.text("再開", "Resume"), action: model.resumeScan)
            } else {
                Button(model.text("一時停止", "Pause"), action: model.pauseScan)
            }
            Button(model.text("キャンセル", "Cancel"), role: .destructive, action: model.cancelScan)
        }
        .font(.caption)
        .padding(8)
        .background(.bar)
    }

    private var importStatus: some View {
        HStack(spacing: 12) {
            ProgressView(value: model.importProgress.fileProgress)
                .progressViewStyle(.linear)
                .frame(width: 80)
            
            let percentStr = String(format: "%.0f%%", model.importProgress.fileProgress * 100)
            Text(model.text(
                "MP3に変換中... (\(model.importProgress.currentFileIndex)/\(model.importProgress.totalFiles)) \(percentStr)",
                "Converting... (\(model.importProgress.currentFileIndex)/\(model.importProgress.totalFiles)) \(percentStr)"
            ))
            
            Text(model.importProgress.currentFileName)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .font(.caption)
        .padding(8)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            // 1. ローカルキャッシュ
            if model.isStorageExternal {
                Menu {
                    Button(model.text("Finderでキャッシュフォルダーを表示", "Show Cache Folder in Finder"), action: model.revealLocalCache)
                    Divider()
                    Text(model.text("場所: \(model.localCacheDirectoryPath)", "Path: \(model.localCacheDirectoryPath)"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "internaldrive.fill")
                        Text(model.text("キャッシュ", "Cache"))
                    }
                }
                .help(model.text("キャッシュ保存場所: \(model.localCacheDirectoryPath)", "Cache Location: \(model.localCacheDirectoryPath)"))
            }

            // 2. 外付けSSD (保管先)
            Menu {
                Button(model.text("保管先を変更…", "Change Storage Destination…"), action: model.chooseStorageDestination)
                if let primary = model.storageDestinations.first(where: \.isPrimary) {
                    Button(model.text("Finderで保管先フォルダーを表示", "Show Storage in Finder")) {
                        NSWorkspace.shared.open(URL(filePath: primary.path))
                    }
                    .disabled(!primary.isAvailable)
                    
                    Button(model.text("保管先フォルダを再スキャン", "Rescan Storage Folder")) {
                        model.startScan(url: URL(filePath: primary.path))
                    }
                    .disabled(!primary.isAvailable)
                    
                    Divider()
                    Text(model.text("場所: \(primary.path)", "Path: \(primary.path)"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Divider()
                    Text(model.text("保管先が設定されていません", "No storage destination set"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "externaldrive.fill")
                    Text(model.storageDestinations.first(where: \.isPrimary)?.name ?? model.text("保管先未設定", "No Storage"))
                }
            }
            .help(model.text(
                "保管先: \(model.storageDestinations.first(where: \.isPrimary)?.path ?? "未設定")",
                "Storage: \(model.storageDestinations.first(where: \.isPrimary)?.path ?? "Not set")"
            ))

            Divider()

            Button(action: model.chooseAndScanFolder) { Label(model.text("フォルダを追加", "Add Folder"), systemImage: "folder.badge.plus") }
            Button(action: model.importNewTracks) { Label(model.text("曲を取り込む", "Import Songs"), systemImage: "tray.and.arrow.down") }
            Button { isMiniPlayer = true } label: { Label(model.text("ミニプレイヤーに切り替え", "Switch to Mini Player"), systemImage: "pip") }
            Button { showInspector.toggle() } label: { Label(model.text("再生情報", "Now Playing Info"), systemImage: "sidebar.right") }
            Menu {
                Button(model.text("M3U/M3U8を読み込む", "Import M3U/M3U8"), action: model.importPlaylist)
                Button(model.text("選択中をM3U8へ書き出す", "Export Selected as M3U8"), action: model.exportSelectedPlaylist)
                    .disabled(model.selectedPlaylistID == nil)
                Button(model.text("選択中の名前を変更", "Rename Selected"), action: model.renameSelectedPlaylist)
                    .disabled(model.selectedPlaylistID == nil)
                Divider()
                Button(model.text("選択中を削除", "Delete Selected"), role: .destructive, action: model.deleteSelectedPlaylist)
                    .disabled(model.selectedPlaylistID == nil)
            } label: { Label(model.text("プレイリスト操作", "Playlist Actions"), systemImage: "ellipsis.circle") }
        }
    }

    private var headerTitle: String {
        if let id = model.selectedPlaylistID, let playlist = model.playlists.first(where: { $0.id == id }) { return playlist.name }
        if let album = model.selectedAlbum { return album.name }
        if let artist = model.selectedArtist { return model.displayArtist(artist.name) }
        if let genre = model.selectedGenre { return genre }
        return model.sectionTitle(model.section)
    }

    private func icon(for section: LibrarySection) -> String {
        switch section {
        case .tracks: "music.note"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .genres: "guitars"
        case .playlists: "music.note.list"
        case .folders: "folder"
        case .favorites: "star.fill"
        case .cache: "internaldrive.fill"
        case .activityLog: "clock.arrow.circlepath"
        case .diagnostics: "stethoscope"
        }
    }

    private func activityKindTitle(_ kind: LibraryActivityKind) -> String {
        switch kind {
        case .added: model.text("ファイル追加", "File Added")
        case .fileModified: model.text("ファイル情報を更新", "File Info Updated")
        case .metadataChanged: model.text("曲情報を編集", "Metadata Edited")
        case .unavailable: model.text("ファイルが見つかりません", "File Unavailable")
        case .restored: model.text("ファイルを再検出", "File Restored")
        case .removedFromLibrary: model.text("リストから削除", "Removed from Library")
        case .movedToTrash: model.text("ファイルをゴミ箱へ移動", "File Moved to Trash")
        }
    }

    private func activityKindIcon(_ kind: LibraryActivityKind) -> String {
        switch kind {
        case .added: "plus.circle.fill"
        case .fileModified, .metadataChanged: "pencil.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        case .restored: "arrow.clockwise.circle.fill"
        case .removedFromLibrary: "minus.circle.fill"
        case .movedToTrash: "trash.circle.fill"
        }
    }

    private func activityKindColor(_ kind: LibraryActivityKind) -> Color {
        switch kind {
        case .added, .restored: .green
        case .fileModified, .metadataChanged: .blue
        case .unavailable: .orange
        case .removedFromLibrary, .movedToTrash: .red
        }
    }

    private func activityFieldTitle(_ field: String) -> String {
        switch field {
        case "title": model.text("タイトル", "Title")
        case "artist": model.text("アーティスト", "Artist")
        case "album": model.text("アルバム", "Album")
        case "album_artist": model.text("アルバムアーティスト", "Album Artist")
        case "genre": model.text("ジャンル", "Genre")
        case "disc_number": model.text("ディスク番号", "Disc Number")
        case "track_number": model.text("トラック番号", "Track Number")
        case "file_size": model.text("ファイルサイズ", "File Size")
        case "modified_at": model.text("更新日時", "Modified Date")
        case "relative_path": model.text("相対パス", "Relative Path")
        case "filename": model.text("ファイル名", "Filename")
        case "format": model.text("形式", "Format")
        case "bitrate": model.text("ビットレート", "Bitrate")
        case "has_artwork": model.text("ジャケット", "Artwork")
        default: field
        }
    }

    private func diagnosticTitle(_ kind: MetadataIssueKind) -> String {
        switch kind {
        case .missingTitle: model.text("曲名なし", "Missing Title")
        case .missingArtist: model.text("不明なアーティスト", "Unknown Artist")
        case .missingAlbum: model.text("アルバム名なし", "Missing Album")
        case .urlInMP3Metadata: model.text("URLを含むMP3", "MP3 Metadata URLs")
        case .duplicateTracks: model.text("重複曲", "Duplicate Tracks")
        case .suspectedVariations: model.text("表記ゆれ候補", "Variation Candidates")
        }
    }

    private func diagnosticIcon(_ kind: MetadataIssueKind) -> String {
        switch kind {
        case .missingTitle: "music.note"
        case .missingArtist: "person.crop.circle.badge.questionmark"
        case .missingAlbum: "square.stack.3d.up.slash"
        case .urlInMP3Metadata: "link.badge.plus"
        case .duplicateTracks: "square.2.layers.3d"
        case .suspectedVariations: "text.magnifyingglass"
        }
    }

    private func diagnosticCount(_ kind: MetadataIssueKind) -> Int {
        model.diagnosticSummaries.first(where: { $0.kind == kind })?.count ?? 0
    }

    private var showsTrackColumns: Bool {
        if model.section == .activityLog { return false }
        if model.section == .diagnostics { return model.diagnosticKind != .suspectedVariations }
        if model.selectedAlbum != nil || model.selectedArtist?.name.isEmpty == true { return true }
        if model.selectedGenre != nil { return model.genreDetailMode == .tracks }
        return ![.albums, .artists, .genres, .folders].contains(model.section)
    }

    private var trackContentWidth: Double {
        var width = 46.0 // outer padding and the persistent favorite/action column
        var visibleColumns = 0
        if isTitleColumnVisible { width += titleColumnWidth; visibleColumns += 1 }
        if isArtistColumnVisible { width += artistColumnWidth; visibleColumns += 1 }
        if isAlbumColumnVisible { width += albumColumnWidth; visibleColumns += 1 }
        if isDiscNumberColumnVisible { width += discNumberColumnWidth; visibleColumns += 1 }
        if isTrackNumberColumnVisible { width += trackNumberColumnWidth; visibleColumns += 1 }
        if isDurationColumnVisible { width += durationColumnWidth; visibleColumns += 1 }
        if isFormatColumnVisible { width += 55; visibleColumns += 1 }
        return width + Double(visibleColumns) * 8
    }

    private func columnVisibilityButton(_ title: String, isVisible: Binding<Bool>) -> some View {
        Button {
            isVisible.wrappedValue.toggle()
        } label: {
            Label(title, systemImage: isVisible.wrappedValue ? "checkmark" : "")
        }
    }

    private func metadataFieldTitle(_ field: MetadataField) -> String {
        switch field {
        case .title: model.text("曲名", "Title")
        case .artist: model.text("アーティスト", "Artist")
        case .album: model.text("アルバム", "Album")
        }
    }

    private func variationReason(_ candidate: MetadataVariationCandidate) -> String {
        switch candidate.reason {
        case .normalization: model.text("全角・半角／空白／大文字小文字", "Width, spacing, or case")
        case .likelyTypo: model.text("タイプミスの可能性（距離 \(candidate.editDistance)）", "Possible typo (distance \(candidate.editDistance))")
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func handleDroppedProviders(_ providers: [NSItemProvider], playlistID: Int64? = nil) {
        let group = DispatchGroup()
        var urls: [URL] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let data = item as? Data {
                        if let url = URL(dataRepresentation: data, relativeTo: nil) {
                            urls.append(url)
                        } else if let path = String(data: data, encoding: .utf8), let url = URL(string: path) {
                            urls.append(url)
                        }
                    } else if let url = item as? URL {
                        urls.append(url)
                    }
                    group.leave()
                }
            } else {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        urls.append(url)
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                model.importURLs(urls, toPlaylist: playlistID)
            }
        }
    }
}

private struct LibrarySearchField: View {
    @ObservedObject var model: LibraryViewModel

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                model.text("タイトル、アーティスト、アルバムを検索", "Search title, artist, or album"),
                text: $model.searchText
            )
            .textFieldStyle(.plain)
            .onChange(of: model.searchText) { _, _ in model.searchChanged() }

            if model.isSearchInProgress {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(model.text("検索中", "Searching"))
                Text(model.text("検索中…", "Searching…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !model.searchText.isEmpty {
                Button(action: model.clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help(model.text("検索内容を消去", "Clear Search"))
                .accessibilityLabel(model.text("検索内容を消去", "Clear Search"))
            }
        }
        .padding(.horizontal, 9)
        .frame(minWidth: 160, idealWidth: 280, maxWidth: 360)
        .frame(height: 30)
        .background(.background, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(model.isSearchInProgress ? Color.accentColor.opacity(0.65) : Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.15), value: model.isSearchInProgress)
    }
}

private struct TrackSortHeader: View {
    @ObservedObject var model: LibraryViewModel
    @Binding var titleWidth: Double
    @Binding var artistWidth: Double
    @Binding var albumWidth: Double
    @Binding var discNumberWidth: Double
    @Binding var trackNumberWidth: Double
    @Binding var durationWidth: Double
    let showTitle: Bool
    let showArtist: Bool
    let showAlbum: Bool
    let showDiscNumber: Bool
    let showTrackNumber: Bool
    let showDuration: Bool
    let showFormat: Bool

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 30)
            if showTitle {
                header(.title).frame(width: titleWidth, alignment: .leading)
                    .overlay(alignment: .trailing) { ColumnResizeHandle(width: $titleWidth, range: 80...500) }
            }
            if showArtist {
                header(.artist).frame(width: artistWidth, alignment: .leading)
                    .overlay(alignment: .trailing) { ColumnResizeHandle(width: $artistWidth, range: 80...420) }
            }
            if showAlbum {
                header(.album).frame(width: albumWidth, alignment: .leading)
                    .overlay(alignment: .trailing) { ColumnResizeHandle(width: $albumWidth, range: 80...500) }
            }
            if showDiscNumber {
                header(.discNumber).frame(width: discNumberWidth, alignment: .leading)
                    .overlay(alignment: .trailing) { ColumnResizeHandle(width: $discNumberWidth, range: 64...160) }
            }
            if showTrackNumber {
                header(.trackNumber).frame(width: trackNumberWidth, alignment: .leading)
                    .overlay(alignment: .trailing) { ColumnResizeHandle(width: $trackNumberWidth, range: 64...170) }
            }
            if showDuration {
                header(.duration).frame(width: durationWidth, alignment: .leading)
                    .overlay(alignment: .trailing) { ColumnResizeHandle(width: $durationWidth, range: 50...140) }
            }
            if showFormat { header(.format).frame(width: 55, alignment: .leading) }
        }
        .font(.caption.bold())
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func header(_ sort: TrackSort) -> some View {
        let isActive = model.sort == sort
        return Button {
            model.sortChanged(to: sort)
        } label: {
            HStack(spacing: 4) {
                Text(model.sortTitle(sort))
                    .lineLimit(1)
                    .fontWeight(isActive ? .bold : .regular)
                if isActive {
                    Image(systemName: model.sortDirection == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }
            .foregroundStyle(isActive ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.accentColor.opacity(0.7) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(model.text("クリックして並び順を変更", "Click to change sort order"))
    }
}

private struct ColumnResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    @State private var dragStartWidth: Double?

    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.28))
            .frame(width: 1)
            .frame(width: 9, height: 22)
            .contentShape(Rectangle())
            .offset(x: 4)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidth == nil { dragStartWidth = width }
                        let proposed = (dragStartWidth ?? width) + value.translation.width
                        width = min(range.upperBound, max(range.lowerBound, proposed))
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
            .help("Drag to resize column")
    }
}

private struct PlayerArtwork: View {
    let artworkURL: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    let placeholderPointSize: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: placeholderPointSize))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: artworkURL) {
            image = artworkURL.flatMap(NSImage.init(contentsOf:))
        }
    }
}

private struct NowPlayingInspector: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var player: PlaybackController
    @Binding var browserURL: URL?
    let openAISettings: () -> Void
    @State private var tab = 0
    @AppStorage("lyrics.autoScroll") private var lyricsAutoScroll = true
    @State private var lyricsContentHeight: CGFloat = 0
    @State private var lyricsViewHeight: CGFloat = 0
    private let lyricsAnchorCount = 100

    var body: some View {
        Group {
            if let browserURL {
                EmbeddedBrowserView(url: browserURL, targetLanguage: model.language.rawValue) {
                    self.browserURL = nil
                }
            } else {
                playerInformation
            }
        }
        .background(.background)
    }

    private var playerInformation: some View {
        VStack(spacing: 12) {
            if player.currentTrack == nil {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 210, height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    PlayerArtwork(
                        artworkURL: nil,
                        size: 210,
                        cornerRadius: 12,
                        placeholderPointSize: 48
                    )
                }
            } else {
                PlayerArtwork(
                    artworkURL: model.enrichedInfo?.artworkURL,
                    size: 210,
                    cornerRadius: 12,
                    placeholderPointSize: 48
                )
            }
            Text(player.currentTrack?.title ?? model.text("再生していません", "Not Playing")).font(.title3.bold()).lineLimit(2).multilineTextAlignment(.center)
            Text(player.currentTrack?.artist ?? "").foregroundStyle(.secondary).lineLimit(1)
            Picker("情報", selection: $tab) {
                Text(model.text("歌詞", "Lyrics")).tag(0)
                Text(model.text("発見", "Discover")).tag(1)
                Text(model.text("情報", "Info")).tag(2)
                Text(model.text("次に再生", "Up Next")).tag(3)
            }.pickerStyle(.segmented).labelsHidden()
            Group {
                if model.isEnriching { ProgressView(model.text("情報を取得中…", "Loading information…")) }
                else if tab == 0 { lyrics }
                else if tab == 1 { discovery }
                else if tab == 2 { information }
                else { upNext }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
    }

    private var lyrics: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Toggle(isOn: $lyricsAutoScroll) {
                    Label(model.text("自動スクロール", "Auto Scroll"), systemImage: "arrow.up.and.down.text.horizontal")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .tint(.accentColor)
                .opacity(lyricsAutoScroll ? 1.0 : 0.4)
            }
            .padding(.bottom, 4)

            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Text(model.enrichedInfo?.lyrics?.plainLyrics ?? model.text(
                                "歌詞が見つかりませんでした。LRCLIBで一致した歌詞は自動保存され、次回はオフラインで表示されます。",
                                "No matching lyrics were found. LRCLIB matches are saved for offline viewing."
                            ))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                GeometryReader { contentGeo in
                                    Color.clear
                                        .onAppear { lyricsContentHeight = contentGeo.size.height }
                                        .onChange(of: contentGeo.size.height) { lyricsContentHeight = $0 }
                                }
                            )

                            // Bottom spacer so last line is never hidden
                            Color.clear.frame(height: 80)

                            // Anchor at the very bottom for 100% position
                            Color.clear.frame(height: 1).id("lyricsAnchorEnd")
                        }
                        // Proportional scroll anchors: placed at equally spaced intervals in layout
                        .background(
                            GeometryReader { fullGeo in
                                ZStack(alignment: .topLeading) {
                                    ForEach(0...lyricsAnchorCount, id: \.self) { i in
                                        Color.clear
                                            .frame(width: 1, height: 1)
                                            .position(
                                                x: 1,
                                                y: fullGeo.size.height * CGFloat(i) / CGFloat(lyricsAnchorCount)
                                            )
                                            .id("lyricsAnchor_\(i)")
                                    }
                                }
                            }
                        )
                    }
                    .onAppear {
                        lyricsViewHeight = geo.size.height
                    }
                    .onChange(of: geo.size.height) { lyricsViewHeight = $0 }
                    .onChange(of: player.elapsed) { _ in
                        guard lyricsAutoScroll,
                              player.duration > 0,
                              lyricsContentHeight > lyricsViewHeight else { return }
                        // Scroll so that the visible window tracks playback:
                        // target offset = pct * scrollableRange, anchor = .top of an
                        // anchor placed at pct * totalContentHeight → approx correct
                        let pct = player.elapsed / player.duration
                        let rawIndex = Int((pct * Double(lyricsAnchorCount)).rounded())
                        let anchorIndex = min(lyricsAnchorCount, max(0, rawIndex))
                        withAnimation(.linear(duration: 0.9)) {
                            proxy.scrollTo("lyricsAnchor_\(anchorIndex)", anchor: .top)
                        }
                    }
                    .onChange(of: model.enrichedInfo?.lyrics?.plainLyrics) { _ in
                        proxy.scrollTo("lyricsAnchor_0", anchor: .top)
                    }
                }
            }
        }
    }


    private var discovery: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.text("ライブラリ内の似た曲", "Similar Songs in Your Library")).font(.headline)
            ForEach(model.similarTracks.prefix(8)) { track in
                HStack {
                    Button {
                        player.play(track)
                        tab = 0
                    } label: {
                        VStack(alignment: .leading) { Text(track.title).lineLimit(1); Text(track.artist).font(.caption).foregroundStyle(.secondary) }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button { player.addToUpNext(track) } label: { Image(systemName: "text.badge.plus") }
                        .buttonStyle(.borderless)
                        .help(model.text("次に再生へ追加", "Add to Up Next"))
                }
            }
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.text("次に再生（\(player.queueTotalCount.formatted())曲）", "Up Next (\(player.queueTotalCount.formatted()) songs)"))
                    .font(.headline)
                Spacer()
                Button(model.text("すべて消去", "Clear"), action: player.clearUpNext)
                    .disabled(player.queueTotalCount == 0)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(player.upNextTracks.enumerated()), id: \.offset) { _, track in
                        HStack {
                            Button { player.playQueued(track) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title).lineLimit(1)
                                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button { player.removeFromUpNext(track) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            HStack {
                Button(model.text("前へ", "Previous"), action: player.previousQueuePage)
                    .disabled(!player.canGoToPreviousQueuePage)
                Spacer()
                Text(model.text("ページ \(player.queuePageNumber) / \(player.queuePageCount)", "Page \(player.queuePageNumber) / \(player.queuePageCount)"))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button(model.text("次へ", "Next"), action: player.nextQueuePage)
                    .disabled(!player.canGoToNextQueuePage)
            }
        }
    }
    private var information: some View {
        Group {
            if let track = player.currentTrack {
                CurrentTrackInfoEditorView(model: model, player: player, track: track, browserURL: $browserURL, openAISettings: openAISettings)
            } else {
                ContentUnavailableView(
                    model.text("曲情報がありません", "No Track Info"),
                    systemImage: "info.circle",
                    description: Text(model.text("再生中の曲がありません。", "No song is currently playing."))
                )
            }
        }
    }
}

private struct CurrentTrackInfoEditorView: View {
    @ObservedObject var model: LibraryViewModel
    @ObservedObject var player: PlaybackController
    let track: Track
    @Binding var browserURL: URL?
    let openAISettings: () -> Void

    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var album: String = ""
    @State private var albumArtist: String = ""
    @State private var genre: String = ""
    @State private var discNumber: String = ""
    @State private var trackNumber: String = ""

    @State private var isSaving = false
    @State private var saveError: String? = nil
    @State private var saveSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Editable Fields
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.text("基本情報", "Basic Info")).font(.headline)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("曲名", "Title")).font(.caption).foregroundStyle(.secondary)
                        TextField(model.text("曲名", "Title"), text: $title)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("アーティスト", "Artist")).font(.caption).foregroundStyle(.secondary)
                        TextField(model.text("アーティスト", "Artist"), text: $artist)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("アルバム", "Album")).font(.caption).foregroundStyle(.secondary)
                        TextField(model.text("アルバム", "Album"), text: $album)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("アルバムアーティスト", "Album Artist")).font(.caption).foregroundStyle(.secondary)
                        TextField(model.text("アルバムアーティスト", "Album Artist"), text: $albumArtist)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("ジャンル", "Genre")).font(.caption).foregroundStyle(.secondary)
                        TextField(model.text("ジャンル", "Genre"), text: $genre)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.text("ディスク番号", "Disc #")).font(.caption).foregroundStyle(.secondary)
                            TextField("", text: $discNumber)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.text("トラック番号", "Track #")).font(.caption).foregroundStyle(.secondary)
                            TextField("", text: $trackNumber)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                
                // Save button & status
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button(action: saveChanges) {
                            if isSaving {
                                ProgressView().controlSize(.small).padding(.trailing, 4)
                            }
                            Text(model.text("ファイルへ保存", "Save to File"))
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasChanges || isSaving || !numbersAreValid)
                        
                        if saveSuccess {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title3)
                                .transition(.opacity)
                        }
                    }
                    
                    if let saveError {
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                
                Divider()
                
                // Read-Only Specs
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.text("ファイル仕様", "File Specifications")).font(.headline)
                    LabeledContent(model.text("形式", "Format"), value: track.format.uppercased())
                    if let bitrate = track.bitrate {
                        LabeledContent(model.text("ビットレート", "Bitrate"), value: "\(bitrate) kbps")
                    }
                    LabeledContent(model.text("再生時間", "Duration"), value: formatDuration(track.duration))
                    LabeledContent(model.text("ファイルサイズ", "File Size"), value: ByteCountFormatter.string(fromByteCount: track.fileSize, countStyle: .file))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.text("ファイル名", "Filename")).font(.caption).foregroundStyle(.secondary)
                        Text(track.filename)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(track.filename)
                        
                        Text(model.text("相対パス", "Relative Path")).font(.caption).foregroundStyle(.secondary)
                            .padding(.top, 4)
                        Text(track.relativePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .help(track.relativePath)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 4)
                }
                
                Divider()
                
                // Navigation/Search Buttons
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.text("関連リンク", "Related Links")).font(.headline)
                    HStack(spacing: 8) {
                        Button(model.text("Wikipedia", "Wikipedia")) { browserURL = model.enrichedInfo?.wikipediaURL }
                            .disabled(model.enrichedInfo?.wikipediaURL == nil)
                        Button(model.text("ニュース", "News")) {
                            browserURL = model.newsURL(for: track.artist)
                        }.disabled(track.artist.isEmpty)
                        Button(model.text("YouTube", "YouTube")) {
                            browserURL = model.youtubeURL(for: track)
                        }
                    }
                }
                
                Divider()
                
                // AI Suggestions
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.text("AIジャンル候補", "AI Genre Suggestion")).font(.headline)
                    if model.isClassifyingGenre {
                        ProgressView(model.text("メタデータから判定中…", "Classifying from metadata…"))
                    } else if let suggestion = model.genreSuggestion {
                        Text(suggestion.genre).font(.title3.bold())
                        Label(
                            suggestion.source == .local ? model.text("内蔵AI", "Built-in AI") :
                                (suggestion.source == .openAI ? "OpenAI" : "Gemini"),
                            systemImage: suggestion.source == .local ? "desktopcomputer" : "cloud"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Text(model.text("確信度 \(Int(suggestion.confidence * 100))%", "Confidence \(Int(suggestion.confidence * 100))%"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(suggestion.rationale).font(.caption)
                        HStack {
                            Button(model.text("ファイルへ適用", "Apply to File")) { model.applyGenreSuggestion(to: track) }
                            Button(model.text("閉じる", "Dismiss"), action: model.clearGenreSuggestion)
                        }
                        if let message = model.aiFallbackMessage {
                            Label(message, systemImage: "arrow.triangle.branch")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    } else {
                        Button(model.text("AIでジャンル候補を提案", "Suggest Genre with AI")) { model.classifyGenre(for: track) }
                        Text(model.text("曲名・アーティスト・アルバム等だけを送信します。音声解析ではありません。", "Only title, artist, album, and related metadata are sent. Audio is not analyzed."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        AIProviderStatusBadge(model: model, name: "OpenAI", status: model.openAIStatus)
                        AIProviderStatusBadge(model: model, name: "Gemini", status: model.geminiStatus)
                    }
                    Button(model.text("AI設定を開く（OpenAI・Gemini）", "Open AI Settings (OpenAI & Gemini)"), action: openAISettings)
                        .buttonStyle(.link)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear(perform: loadTrackData)
        .onChange(of: track) { _, _ in loadTrackData() }
    }

    private var hasChanges: Bool {
        title != track.title ||
        artist != track.artist ||
        album != track.album ||
        albumArtist != track.albumArtist ||
        genre != track.genre ||
        discNumber != (track.discNumber.map(String.init) ?? "") ||
        trackNumber != (track.trackNumber.map(String.init) ?? "")
    }

    private var numbersAreValid: Bool {
        let discOK = discNumber.isEmpty || Int(discNumber) != nil
        let trackOK = trackNumber.isEmpty || Int(trackNumber) != nil
        return discOK && trackOK
    }

    private func loadTrackData() {
        title = track.title
        artist = track.artist
        album = track.album
        albumArtist = track.albumArtist
        genre = track.genre
        discNumber = track.discNumber.map(String.init) ?? ""
        trackNumber = track.trackNumber.map(String.init) ?? ""
        saveError = nil
        saveSuccess = false
    }

    private func saveChanges() {
        guard hasChanges && !isSaving && numbersAreValid else { return }
        isSaving = true
        saveError = nil
        saveSuccess = false
        
        let editTitle = title
        let editArtist = artist
        let editAlbum = album
        let editAlbumArtist = albumArtist
        let editGenre = genre
        let editDisc = Int(discNumber)
        let editTrackNum = Int(trackNumber)
        
        var edit = TrackMetadataEdit(track: track)
        edit.title = editTitle
        edit.artist = editArtist
        edit.album = editAlbum
        edit.albumArtist = editAlbumArtist
        edit.genre = editGenre
        edit.discNumber = editDisc
        edit.trackNumber = editTrackNum
        
        Task {
            do {
                try await model.updateMetadataAsync(for: track, edit: edit)
                await MainActor.run {
                    player.updateCurrentTrack(
                        title: editTitle,
                        artist: editArtist,
                        album: editAlbum,
                        albumArtist: editAlbumArtist,
                        genre: editGenre,
                        discNumber: editDisc,
                        trackNumber: editTrackNum
                    )
                    isSaving = false
                    saveSuccess = true
                    withAnimation {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            saveSuccess = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct AIProviderStatusBadge: View {
    @ObservedObject var model: LibraryViewModel
    let name: String
    let status: AIProviderStatus

    var body: some View {
        Label("\(name): \(title)", systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
            .help(detail)
    }

    private var title: String {
        switch status {
        case .notConfigured: model.text("未登録", "Not Set")
        case .configured: model.text("保存済み", "Saved")
        case .checking: model.text("確認中", "Checking")
        case .valid: model.text("有効", "Valid")
        case .invalid: model.text("エラー", "Error")
        }
    }

    private var icon: String {
        switch status {
        case .notConfigured: "key.slash"
        case .configured: "key.fill"
        case .checking: "clock"
        case .valid: "checkmark.circle.fill"
        case .invalid: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .valid: .green
        case .invalid: .red
        case .checking: .orange
        case .configured: .blue
        case .notConfigured: .secondary
        }
    }

    private var detail: String {
        if case let .invalid(message) = status { return message }
        return title
    }
}

private struct TrackMetadataEditor: View {
    @ObservedObject var model: LibraryViewModel
    let track: Track
    @Environment(\.dismiss) private var dismiss
    @State private var edit: TrackMetadataEdit
    @State private var discNumber: String
    @State private var trackNumber: String
    @State private var metadataCandidates: [MusicMetadataCandidate] = []
    @State private var selectedCandidateID: String?
    @State private var isLookingUpMetadata = false
    @State private var metadataLookupMessage: String?

    init(model: LibraryViewModel, track: Track) {
        self.model = model
        self.track = track
        _edit = State(initialValue: TrackMetadataEdit(track: track))
        _discNumber = State(initialValue: track.discNumber.map(String.init) ?? "")
        _trackNumber = State(initialValue: track.trackNumber.map(String.init) ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent(model.text("ファイル", "File")) {
                    Text(track.filename).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                }
                TextField(model.text("タイトル", "Title"), text: $edit.title)
                TextField(model.text("アーティスト", "Artist"), text: $edit.artist)
                TextField(model.text("アルバム", "Album"), text: $edit.album)
                TextField(model.text("アルバムアーティスト", "Album Artist"), text: $edit.albumArtist)
                TextField(model.text("ジャンル", "Genre"), text: $edit.genre)
                HStack {
                    TextField(model.text("ディスク番号", "Disc Number"), text: $discNumber)
                    TextField(model.text("トラック番号", "Track Number"), text: $trackNumber)
                }
                LabeledContent(model.text("Web情報", "Web Metadata")) {
                    HStack(spacing: 10) {
                        Button(model.text("MusicBrainzから自動補完", "Auto-Fill from MusicBrainz"), action: lookUpMetadata)
                            .disabled(isLookingUpMetadata || edit.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if isLookingUpMetadata {
                            ProgressView().controlSize(.small)
                            Text(model.text("検索中…", "Searching…"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let candidate = selectedCandidate {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(model.text("自動入力した候補", "Auto-Filled Match"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            if metadataCandidates.count > 1 {
                                Menu(model.text("他の候補（\(metadataCandidates.count)件）", "Other Matches (\(metadataCandidates.count))")) {
                                    ForEach(metadataCandidates) { item in
                                        Button(candidateLabel(item)) { apply(item) }
                                    }
                                }
                            }
                        }
                        Text(candidateLabel(candidate)).font(.caption).foregroundStyle(.secondary)
                        if let url = URL(string: "https://musicbrainz.org/release/\(candidate.releaseID)") {
                            Link(model.text("MusicBrainzで確認", "Review on MusicBrainz"), destination: url)
                                .font(.caption)
                        }
                        Text(model.text(
                            "編集欄へ入力しただけで、まだファイルは変更していません。内容を確認して「ファイルへ保存」を押してください。",
                            "The fields are filled in, but the file has not changed. Review them, then choose Save to File."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                } else if let metadataLookupMessage {
                    Text(metadataLookupMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(model.text(
                    "アプリ内の一時領域へコピーして書き込み結果を確認してから、元ファイルへ反映します。失敗時はバックアップから復元し、音声データは再エンコードしません。",
                    "An app-local temporary copy is written and verified before updating the source. Failures restore the backup, and audio is not re-encoded."
                )).font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            Divider()
            HStack {
                Spacer()
                Button(model.text("キャンセル", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.text("ファイルへ保存", "Save to File")) {
                    edit.discNumber = positiveInteger(discNumber)
                    edit.trackNumber = positiveInteger(trackNumber)
                    model.updateMetadata(for: track, edit: edit)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(edit.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !numbersAreValid)
            }
            .padding(14)
            .background(.bar)
        }
        .frame(width: 620, height: 650)
    }

    private var selectedCandidate: MusicMetadataCandidate? {
        guard let selectedCandidateID else { return nil }
        return metadataCandidates.first { $0.id == selectedCandidateID }
    }

    private func lookUpMetadata() {
        guard !isLookingUpMetadata else { return }
        isLookingUpMetadata = true
        metadataLookupMessage = nil
        metadataCandidates = []
        selectedCandidateID = nil
        var lookupTrack = track
        if edit.title != track.title || edit.artist != track.artist || edit.album != track.album {
            lookupTrack = Track(
                id: track.id, rootID: track.rootID, relativePath: track.relativePath, filename: track.filename,
                title: edit.title, artist: edit.artist, album: edit.album, albumArtist: edit.albumArtist,
                genre: edit.genre, discNumber: track.discNumber, trackNumber: track.trackNumber,
                duration: track.duration, fileSize: track.fileSize, modifiedAt: track.modifiedAt,
                format: track.format, bitrate: track.bitrate, hasArtwork: track.hasArtwork,
                isAvailable: track.isAvailable, addedAt: track.addedAt, isFavorite: track.isFavorite
            )
        }
        Task {
            do {
                let results = try await model.webMetadataCandidates(for: lookupTrack)
                metadataCandidates = Array(results.prefix(30))
                if let first = metadataCandidates.first {
                    apply(first)
                } else {
                    metadataLookupMessage = model.text(
                        "一致する候補が見つかりませんでした。曲名やアーティスト名を確認してください。",
                        "No matching release was found. Check the song title and artist."
                    )
                }
            } catch {
                metadataLookupMessage = model.text(
                    "Web検索に失敗しました: \(error.localizedDescription)",
                    "Web lookup failed: \(error.localizedDescription)"
                )
            }
            isLookingUpMetadata = false
        }
    }

    private func apply(_ candidate: MusicMetadataCandidate) {
        selectedCandidateID = candidate.id
        edit.album = candidate.album
        if !candidate.albumArtist.isEmpty { edit.albumArtist = candidate.albumArtist }
        discNumber = String(candidate.discNumber)
        trackNumber = String(candidate.trackNumber)
        metadataLookupMessage = nil
    }

    private func candidateLabel(_ candidate: MusicMetadataCandidate) -> String {
        let date = candidate.releaseDate.map { " · \($0)" } ?? ""
        return model.text(
            "\(candidate.album) · ディスク \(candidate.discNumber) / トラック \(candidate.trackNumber)\(date)",
            "\(candidate.album) · Disc \(candidate.discNumber) / Track \(candidate.trackNumber)\(date)"
        )
    }

    private var numbersAreValid: Bool {
        [discNumber, trackNumber].allSatisfy { value in
            value.trimmingCharacters(in: .whitespaces).isEmpty || positiveInteger(value) != nil
        }
    }

    private func positiveInteger(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let number = Int(trimmed), number > 0 else { return nil }
        return number
    }
}

private struct BatchTrackMetadataEditor: View {
    @ObservedObject var model: LibraryViewModel
    let tracks: [Track]
    @Environment(\.dismiss) private var dismiss
    @State private var changeTitle = false
    @State private var changeArtist = false
    @State private var changeAlbum = false
    @State private var changeAlbumArtist = false
    @State private var changeGenre = false
    @State private var changeArtwork = false
    @State private var changeDiscNumber = false
    @State private var changeTrackNumber = false
    @State private var incrementTrackNumber = true
    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var albumArtist: String
    @State private var genre: String
    @State private var discNumber: String
    @State private var trackNumber: String
    @State private var artworkData: Data?
    @State private var artworkImage: NSImage?
    @State private var artworkPasteError: String?

    init(model: LibraryViewModel, tracks: [Track]) {
        self.model = model
        self.tracks = tracks
        _title = State(initialValue: Self.commonValue(tracks.map(\.title)))
        _artist = State(initialValue: Self.commonValue(tracks.map(\.artist)))
        _album = State(initialValue: Self.commonValue(tracks.map(\.album)))
        _albumArtist = State(initialValue: Self.commonValue(tracks.map(\.albumArtist)))
        _genre = State(initialValue: Self.commonValue(tracks.map(\.genre)))
        _discNumber = State(initialValue: Self.commonNumber(tracks.map(\.discNumber)))
        _trackNumber = State(initialValue: Self.commonNumber(tracks.map(\.trackNumber)))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.text("曲情報を一括編集", "Bulk Edit Song Info"))
                    .font(.title2.bold())
                Text(model.text(
                    "選択した\(tracks.count)曲のうち、チェックした項目だけを変更します。",
                    "Only checked fields will be changed for the \(tracks.count) selected songs."
                ))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Form {
                batchField(model.text("タイトル", "Title"), enabled: $changeTitle, value: $title)
                batchField(model.text("アーティスト", "Artist"), enabled: $changeArtist, value: $artist)
                batchField(model.text("アルバム", "Album"), enabled: $changeAlbum, value: $album)
                batchField(model.text("アルバムアーティスト", "Album Artist"), enabled: $changeAlbumArtist, value: $albumArtist)
                batchField(model.text("ジャンル", "Genre"), enabled: $changeGenre, value: $genre)
                batchNumberField(
                    model.text("ディスク番号", "Disc Number"),
                    enabled: $changeDiscNumber,
                    value: $discNumber
                )
                batchNumberField(
                    model.text("トラック番号", "Track Number"),
                    enabled: $changeTrackNumber,
                    value: $trackNumber,
                    showsIncrement: true
                )
                LabeledContent(model.text("アルバムジャケット", "Album Artwork")) {
                    HStack(spacing: 12) {
                        Toggle("", isOn: $changeArtwork)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        if let artworkImage {
                            Image(nsImage: artworkImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Button(model.text("画像を選択…", "Choose Image…"), action: chooseArtwork)
                            .disabled(isRunning)
                        Button(model.text("クリップボードから貼り付け", "Paste from Clipboard"), action: pasteArtworkFromClipboard)
                            .disabled(isRunning)
                            .help(model.text("クリップボードの画像を貼り付け（⌘V）", "Paste an image from the clipboard (⌘V)"))
                        if artworkData != nil {
                            Button(model.text("解除", "Clear")) {
                                artworkData = nil
                                artworkImage = nil
                                changeArtwork = false
                            }
                            .buttonStyle(.link)
                            .disabled(isRunning)
                        }
                    }
                }
                Text(model.text(
                    "この画面で画像をコピーして⌘Vを押すか、「クリップボードから貼り付け」を使用できます。",
                    "Copy an image, then press ⌘V in this screen or use Paste from Clipboard."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                if let artworkPasteError {
                    Text(artworkPasteError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if changeArtwork, unsupportedArtworkCount > 0 {
                    Text(model.text(
                        "ジャケットの安全なファイル書き込みは現在MP3のみです。選択中にMP3以外が\(unsupportedArtworkCount)曲含まれています。",
                        "Safe artwork writing currently supports MP3. The selection contains \(unsupportedArtworkCount) non-MP3 songs."
                    ))
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                if hasInvalidNumber {
                    Text(model.text("番号には0以上の整数を入力してください。", "Enter a whole number of zero or greater."))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text(model.text(
                    "空欄を有効にすると、その項目を空にします。各ファイルは作業コピーで検証してから個別に反映されます。",
                    "Enabling an empty field clears it. Every file is individually verified on a working copy before it is updated."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .disabled(isRunning || isFinished)
            .padding(.horizontal, 20)

            Divider()
            footer
                .padding(14)
                .background(.bar)
        }
        .frame(width: 680, height: 680)
        .interactiveDismissDisabled(isRunning)
        .onPasteCommand(of: [.image]) { _ in
            guard !isRunning, !isFinished else { return }
            pasteArtworkFromClipboard()
        }
    }

    @ViewBuilder
    private func batchField(_ title: String, enabled: Binding<Bool>, value: Binding<String>) -> some View {
        LabeledContent(title) {
            HStack {
                Toggle("", isOn: enabled).labelsHidden().toggleStyle(.checkbox)
                TextField(title, text: value).disabled(!enabled.wrappedValue)
            }
        }
    }

    @ViewBuilder
    private func batchNumberField(
        _ title: String,
        enabled: Binding<Bool>,
        value: Binding<String>,
        showsIncrement: Bool = false
    ) -> some View {
        LabeledContent(title) {
            HStack {
                Toggle("", isOn: enabled).labelsHidden().toggleStyle(.checkbox)
                TextField(title, text: value)
                    .frame(width: 90)
                    .disabled(!enabled.wrappedValue)
                if showsIncrement {
                    Toggle(model.text("一覧順に連番", "Increment in List Order"), isOn: $incrementTrackNumber)
                        .disabled(!enabled.wrappedValue || parsedNumber(value.wrappedValue) == nil)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        let progress = model.batchMetadataProgress
        if isRunning {
            VStack(spacing: 8) {
                ProgressView(value: Double(progress.processed), total: Double(max(1, progress.total)))
                HStack {
                    Text(model.text(
                        "\(progress.processed) / \(progress.total)曲・失敗 \(progress.failed)曲",
                        "\(progress.processed) / \(progress.total) songs · \(progress.failed) failed"
                    ))
                    .monospacedDigit()
                    Spacer()
                    Text(progress.currentFilename).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Button(model.text("キャンセル", "Cancel"), action: model.cancelBatchMetadataUpdate)
                }
            }
        } else if isFinished {
            HStack {
                Text(completionText(progress)).foregroundStyle(progress.failed == 0 ? Color.secondary : Color.red)
                Spacer()
                Button(model.text("閉じる", "Close")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        } else {
            HStack {
                Spacer()
                Button(model.text("キャンセル", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.text("\(tracks.count)曲に適用", "Apply to \(tracks.count) Songs")) {
                    model.updateMetadata(for: tracks, changes: changes)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            }
        }
    }

    private var changes: BatchMetadataChanges {
        BatchMetadataChanges(
            title: changeTitle ? title : nil,
            artist: changeArtist ? artist : nil,
            album: changeAlbum ? album : nil,
            albumArtist: changeAlbumArtist ? albumArtist : nil,
            genre: changeGenre ? genre : nil,
            discNumber: parsedNumber(discNumber),
            changesDiscNumber: changeDiscNumber,
            trackNumber: parsedNumber(trackNumber),
            changesTrackNumber: changeTrackNumber,
            incrementsTrackNumber: changeTrackNumber && incrementTrackNumber,
            artworkData: changeArtwork ? artworkData : nil
        )
    }

    private var canApply: Bool {
        !changes.isEmpty && !hasInvalidNumber &&
            (!changeArtwork || (artworkData != nil && unsupportedArtworkCount == 0))
    }

    private var isRunning: Bool { model.batchMetadataProgress.state == .running }
    private var isFinished: Bool {
        [.completed, .cancelled].contains(model.batchMetadataProgress.state)
    }
    private var unsupportedArtworkCount: Int {
        tracks.lazy.filter { $0.format.lowercased() != "mp3" }.count
    }
    private var hasInvalidNumber: Bool {
        (changeDiscNumber && !isValidNumberInput(discNumber)) ||
            (changeTrackNumber && !isValidNumberInput(trackNumber))
    }

    private func completionText(_ progress: BatchMetadataProgress) -> String {
        switch progress.state {
        case .cancelled:
            model.text(
                "キャンセルしました（成功 \(progress.succeeded)曲・失敗 \(progress.failed)曲）",
                "Cancelled (\(progress.succeeded) succeeded · \(progress.failed) failed)"
            )
        default:
            model.text(
                "完了しました（成功 \(progress.succeeded)曲・失敗 \(progress.failed)曲）",
                "Completed (\(progress.succeeded) succeeded · \(progress.failed) failed)"
            )
        }
    }

    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.title = model.text("アルバムジャケットを選択", "Choose Album Artwork")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png]
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url),
              let normalized = Self.normalizedJPEG(from: image) else {
            return
        }
        artworkData = normalized
        artworkImage = NSImage(data: normalized)
        changeArtwork = true
        artworkPasteError = nil
    }

    private func pasteArtworkFromClipboard() {
        guard let image = NSPasteboard.general.readObjects(
            forClasses: [NSImage.self],
            options: nil
        )?.first as? NSImage else {
            artworkPasteError = model.text(
                "クリップボードに貼り付け可能な画像がありません。",
                "The clipboard does not contain a pasteable image."
            )
            return
        }
        guard let normalized = Self.normalizedJPEG(from: image) else {
            artworkPasteError = model.text(
                "クリップボードの画像を読み込めませんでした。",
                "The clipboard image could not be read."
            )
            return
        }
        artworkData = normalized
        artworkImage = NSImage(data: normalized)
        changeArtwork = true
        artworkPasteError = nil
    }

    private static func commonValue(_ values: [String]) -> String {
        guard let first = values.first, values.dropFirst().allSatisfy({ $0 == first }) else { return "" }
        return first
    }

    private static func commonNumber(_ values: [Int?]) -> String {
        guard let first = values.first, values.dropFirst().allSatisfy({ $0 == first }) else { return "" }
        return first.map(String.init) ?? ""
    }

    private func parsedNumber(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    private func isValidNumberInput(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || (Int(trimmed).map { $0 >= 0 } ?? false)
    }

    private static func normalizedJPEG(from image: NSImage) -> Data? {
        let maximum = 1_600.0
        let scale = min(1, maximum / max(image.size.width, image.size.height))
        let size = NSSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let output = NSImage(size: size)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        let representation = NSBitmapImageRep(focusedViewRect: NSRect(origin: .zero, size: size))
        output.unlockFocus()
        return representation?.representation(using: .jpeg, properties: [.compressionFactor: 0.88])
    }
}

private struct LibrarySettingsView: View {
    @ObservedObject var model: LibraryViewModel
    @Binding var selectedTab: SettingsTab
    @Environment(\.dismiss) private var dismiss
    @State private var openAIAPIKey = ""
    @State private var openAIModel = ""
    @State private var geminiAPIKey = ""
    @State private var geminiModel = ""
    @FocusState private var isAPIKeyFocused: Bool

    var body: some View {
        TabView(selection: $selectedTab) {
            Form {
                Picker(model.text("言語", "Language"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                Picker(model.text("外観", "Appearance"), selection: $model.appearance) {
                    ForEach(AppearanceMode.allCases) { Text(model.appearanceTitle($0)).tag($0) }
                }
                Text(model.text("Wikipediaとニュースは選択言語の版を優先し、外部記事は内部ブラウザで選択言語へ自動翻訳します。", "Wikipedia and news prefer the selected locale. External articles are automatically translated in the internal browser."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding().tabItem { Label(model.text("表示", "Display"), systemImage: "textformat") }.tag(SettingsTab.display)

            Form {
                LabeledContent(model.text("現在の保存先", "Current Destination")) {
                    Text(model.storageDestinations.first(where: \.isPrimary)?.path ?? model.text("未設定（ローカル受信箱のみ）", "Not set (local Inbox only)"))
                        .lineLimit(1).truncationMode(.middle)
                }
                Button(model.text("保存先を変更…", "Change Destination…"), action: model.chooseStorageDestination)
                Divider()
                Text(model.text("ローカル受信箱", "Local Inbox")).font(.headline)
                if model.pendingImports.isEmpty { Text(model.text("移動待ちの曲はありません", "No songs are waiting to be moved.")).foregroundStyle(.secondary) }
                ForEach(model.pendingImports.filter { $0.state == .staged }) { item in
                    HStack {
                        Text(item.filename).lineLimit(1)
                        Spacer()
                        if let destination = model.storageDestinations.first(where: \.isPrimary) {
                            Button(model.text("確認して移動", "Confirm and Move")) { model.moveImport(item, to: destination) }
                                .disabled(!destination.isAvailable)
                        }
                    }
                }
            }
            .padding().tabItem { Label(model.text("保存先", "Storage"), systemImage: "externaldrive") }.tag(SettingsTab.storage)

            if model.isStorageExternal {
                Form {
                    Toggle(model.text("再生した曲をローカルにキャッシュ", "Cache Played Songs Locally"), isOn: $model.cacheEnabled)
                    Stepper(model.text("保持する直近の曲: \(model.cacheTrackLimit) 曲", "Recent songs to keep: \(model.cacheTrackLimit)"), value: $model.cacheTrackLimit, in: 0...500)
                    Text(model.text("上限を超えた曲は最終アクセスの古い順に自動削除します。SSD上の原本は変更しません。", "Songs beyond the limit are evicted least-recently-used. Originals on the SSD are not changed."))
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent(model.text("キャッシュ保存場所", "Cache Location")) {
                        Text(model.localCacheDirectoryPath).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                    Text(model.text(
                        "お気に入り登録時に「追加してローカルに保存」を選んだ曲は、直近曲の上限とは別に保持します。",
                        "Favorites saved locally are retained separately from the recent-song limit."
                    )).font(.caption).foregroundStyle(.secondary)
                    Button(model.text("Finderでキャッシュを表示", "Show Cache in Finder"), action: model.revealLocalCache)
                    Button(model.text("設定を保存", "Save Settings"), action: model.saveCacheSettings)
                }
                .padding().tabItem { Label(model.text("オフライン", "Offline"), systemImage: "arrow.down.circle") }.tag(SettingsTab.offline)
            }

            Form {
                Section("OpenAI") {
                    LabeledContent(model.text("接続状態", "Connection")) {
                        AIProviderStatusBadge(model: model, name: "OpenAI", status: model.openAIStatus)
                    }
                    if case let .invalid(message) = model.openAIStatus {
                        Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                    SecureField(model.text("変更するOpenAI APIキー", "Replacement OpenAI API Key"), text: $openAIAPIKey)
                        .focused($isAPIKeyFocused)
                    TextField(model.text("OpenAIモデル", "OpenAI Model"), text: $openAIModel)
                    HStack {
                        Link(model.text("OpenAIでAPIキーを作成", "Create an OpenAI API Key"), destination: URL(string: "https://platform.openai.com/settings/organization/api-keys")!)
                        if model.hasOpenAIAPIKey {
                            Button(model.text("OpenAIキーを削除", "Delete OpenAI Key"), role: .destructive, action: model.removeOpenAIAPIKey)
                        }
                    }
                }

                Section("Gemini") {
                    LabeledContent(model.text("接続状態", "Connection")) {
                        AIProviderStatusBadge(model: model, name: "Gemini", status: model.geminiStatus)
                    }
                    if case let .invalid(message) = model.geminiStatus {
                        Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                    SecureField(model.text("変更するGemini APIキー", "Replacement Gemini API Key"), text: $geminiAPIKey)
                    TextField(model.text("Geminiモデル", "Gemini Model"), text: $geminiModel)
                    HStack {
                        Link(model.text("Google AI Studioでキーを作成", "Create a Key in Google AI Studio"), destination: URL(string: "https://aistudio.google.com/apikey")!)
                        if model.hasGeminiAPIKey {
                            Button(model.text("Geminiキーを削除", "Delete Gemini Key"), role: .destructive, action: model.removeGeminiAPIKey)
                        }
                    }
                }

                Text(model.text(
                    "キーはmacOS Keychainに保存します。ジャンル判定はOpenAI、失敗時はGemini、さらに失敗した場合は内蔵AIへ自動で切り替えます。外部へ送るのは曲名・アーティスト・アルバム等だけで、音声ファイルは送信しません。",
                    "Keys are stored in macOS Keychain. Genre classification tries OpenAI, then Gemini on failure, and finally the built-in AI. Only title, artist, album, and related metadata are sent; audio files are never uploaded."
                )).font(.caption).foregroundStyle(.secondary)

                HStack {
                    Button(model.text("キーとモデルを保存", "Save Keys and Models")) {
                        model.saveAISettings(
                            openAIAPIKey: openAIAPIKey, openAIModel: openAIModel,
                            geminiAPIKey: geminiAPIKey, geminiModel: geminiModel
                        )
                        openAIAPIKey = ""
                        geminiAPIKey = ""
                    }
                    .keyboardShortcut(.defaultAction)
                    Button(model.text("接続を再確認", "Test Connections"), action: model.validateAIProviders)
                }
            }
            .padding()
            .tabItem { Label("AI", systemImage: "sparkles") }
            .tag(SettingsTab.ai)
        }
        .onAppear {
            openAIModel = model.openAIModel
            geminiModel = model.geminiModel
            focusAPIKeyIfNeeded()
        }
        .onChange(of: selectedTab) { _, _ in focusAPIKeyIfNeeded() }
        .frame(width: 760, height: 650)
        .safeAreaInset(edge: .bottom) { HStack { Spacer(); Button(model.text("閉じる", "Close")) { dismiss() }.keyboardShortcut(.defaultAction) }.padding().background(.bar) }
    }

    private func focusAPIKeyIfNeeded() {
        guard selectedTab == .ai else { return }
        DispatchQueue.main.async { isAPIKeyFocused = true }
    }
}



private struct TrackTitleCell: View {
    let track: Track
    let helpText: String

    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundStyle(track.isAvailable ? Color.secondary : Color.orange)
            Text(track.title).lineLimit(1)
        }
        .contentShape(Rectangle())
        .help(track.isAvailable ? "" : helpText)
    }

    private var iconName: String {
        track.isAvailable ? "music.note" : "externaldrive.badge.exclamationmark"
    }
}

private struct TrackNavigationCell: View {
    let title: String
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .frame(width: width, height: 32, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PlayerBar: View {
    @ObservedObject var player: PlaybackController
    @ObservedObject var model: LibraryViewModel

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if player.currentTrack == nil {
                    if let appIcon = NSApp.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        PlayerArtwork(
                            artworkURL: nil,
                            size: 48,
                            cornerRadius: 6,
                            placeholderPointSize: 18
                        )
                    }
                } else {
                    PlayerArtwork(
                        artworkURL: model.enrichedInfo?.artworkURL,
                        size: 48,
                        cornerRadius: 6,
                        placeholderPointSize: 18
                    )
                }
            }
            .accessibilityLabel(model.text("アルバムジャケット", "Album artwork"))
            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.title ?? model.text("再生していません", "Not Playing")).lineLimit(1).fontWeight(.medium)
                Text(player.currentTrack?.artist ?? "").lineLimit(1).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 200, alignment: .leading)
            Button(action: player.previous) { Image(systemName: "backward.fill") }
            Button(action: player.togglePlayPause) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
            }
            .buttonStyle(.plain)
            Button(action: player.next) { Image(systemName: "forward.fill") }
            Text(format(player.elapsed)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { player.elapsed },
                    set: { newValue in player.seek(to: newValue) }
                ),
                in: 0...max(1, player.duration)
            )
            Text(format(player.duration)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Button(action: player.toggleShuffle) {
                Image(systemName: "shuffle")
                    .foregroundStyle(player.shuffleEnabled ? Color.accentColor : Color.secondary)
                    .frame(width: 36, height: 32)
                    .background(player.shuffleEnabled ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.text("ランダム再生", "Shuffle"))
            .accessibilityLabel(model.text("ランダム再生", "Shuffle"))
            .accessibilityValue(player.shuffleEnabled ? model.text("オン", "On") : model.text("オフ", "Off"))
            Menu {
                ForEach(PlaybackController.RepeatMode.allCases, id: \.self) { mode in
                    Button(mode.rawValue) { player.repeatMode = mode }
                }
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.accentColor)
                    .frame(width: 40, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .help(model.text("リピート", "Repeat"))
            Image(systemName: "speaker.fill").foregroundStyle(.secondary)
            Slider(value: $player.volume, in: 0...1).frame(width: 90)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .frame(height: 70)
        .background(.bar)
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

struct MiniPlayerView: View {
    @ObservedObject var player: PlaybackController
    @ObservedObject var model: LibraryViewModel
    @Binding var isMiniPlayer: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                PlayerArtwork(
                    artworkURL: model.enrichedInfo?.artworkURL,
                    size: 54,
                    cornerRadius: 11,
                    placeholderPointSize: 20
                )
                .accessibilityLabel(model.text("アルバムジャケット", "Album artwork"))
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.currentTrack?.title ?? model.text("再生していません", "Not Playing")).fontWeight(.semibold).lineLimit(1)
                    Text(player.currentTrack?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { isMiniPlayer = false } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help(model.text("通常画面に戻す", "Return to Full Player"))
            }
            Slider(value: Binding(
                get: { player.elapsed },
                set: { value in player.seek(to: value) }
            ), in: 0...max(1, player.duration))
            HStack {
                Button(action: player.previous) { Image(systemName: "backward.fill") }
                Button(action: player.togglePlayPause) { Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.title) }.buttonStyle(.plain)
                Button(action: player.next) { Image(systemName: "forward.fill") }
                Spacer()
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...1).frame(width: 90)
            }.buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 390, height: 180)
        .background(.ultraThinMaterial)
        .onAppear { model.enrich(player.currentTrack) }
        .onChange(of: player.currentTrack) { _, track in model.enrich(track) }
    }
}
