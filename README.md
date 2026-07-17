# MassiveMusic

## v0.12 の追加機能

- ライブラリ欄に「キャッシュ」を追加しました。Mac内の `Application Support/MassiveMusic/OfflineCache` に実在する曲だけを通常の曲一覧と同じく200曲ずつ表示し、検索、ソート、ダブルクリック再生ができます。SSDが外れていてもキャッシュ済み曲を再生できます。
- キャッシュ画面上部で「再生時に保存」の有効／無効と、直近に保持する曲数（0〜500曲）を変更できます。上限を小さくすると、固定保存したお気に入りを除き、古いキャッシュから整理します。
- キャッシュされていない曲は右クリックメニューに「ローカルにキャッシュ」を表示します。SSD上の元ファイルは移動・変更せず、Mac側へ複製します。キャッシュ済み曲は「ローカルキャッシュから削除」でローカル複製だけを削除できます。
- キャッシュ一覧と状態判定はSQLiteでページングし、ライブラリ全件や全キャッシュ曲をSwift配列へ読み込みません。

## v0.11 の追加機能

- 曲の右クリックメニューから「この曲の情報を編集…」を開き、「MusicBrainzから自動補完」を押すと、曲名・アーティスト・再生時間・現在のアルバムを照合して、アルバム名、アルバムアーティスト、ディスク番号、トラック番号を編集欄へ自動入力します。
- 再発盤やベスト盤など複数の候補がある場合は「他の候補」から選び直し、MusicBrainzのリリースページで確認できます。候補を入力しただけではファイルを変更せず、最後に「ファイルへ保存」を押したときだけ既存の検証・復元付き書き込みを実行します。
- MusicBrainzの利用制限を守るため、Web検索は1.1秒以上の間隔を空けます。現在のアルバムを含む検索で見つからない場合は、アルバム条件を外して自動的に再検索します。

## v0.10 の修正

- 検索語が入っているときは、検索欄右端の×ボタンを1回押すだけで内容を消去し、全件表示へ直ちに戻せます。
- 入力待機中とデータベース検索中は、検索欄内に進捗表示と「検索中…」を表示し、枠線もアクセント色へ変わります。

## v0.9 の追加機能

- 再生を開始した曲は、設定の「再生した曲をローカルにキャッシュ」が有効な場合、Mac内のアプリライブラリ `Application Support/MassiveMusic/OfflineCache` にコピーして以後の再生に使います。既定では直近24曲、設定可能範囲は0〜500曲です。
- 星をクリックして新しくお気に入りへ追加すると、「追加してローカルに保存」「お気に入りだけに追加」「キャンセル」を確認します。ローカル保存は音源をSSDから移動せず、Mac内へ複製します。
- お気に入りから明示的にローカル保存した曲は固定キャッシュとして扱い、直近曲数の上限を超えても削除しません。お気に入り解除時は固定を外し、通常のLRU管理へ戻します。
- 再生時はSSDより先にローカルキャッシュを確認するため、保存済みの曲はSSDが未接続でも再生できます。
- 設定の「オフライン」にキャッシュの絶対パスと「Finderでキャッシュを表示」を追加しました。

## v0.8 の修正

- 曲へ登録した埋め込みアルバムジャケット（MP3のID3 APIC）を右ペインで優先表示します。埋め込み画像がない場合だけ、従来のMusicBrainz/Cover Art Archive画像へフォールバックします。
- ジャケット編集後は該当曲のメモリ／ディスク画像キャッシュを破棄し、再生中の曲であれば右ペインを直ちに再読込します。
- 古いオフライン音源キャッシュにジャケットが入っていない場合はそこで終了せず、接続中の登録元ファイルから画像を取得します。

## v0.7 の追加機能

- 右ペインのAIジャンル候補には、キーの登録状態にかかわらず「AI設定を開く（OpenAI・Gemini）」を常時表示します。
- AI設定でOpenAIとGeminiのAPIキーを個別に登録・変更・削除できます。キーは設定ファイルへ書かず、プロバイダー別にmacOS Keychainへ保存します。
- OpenAIとGeminiの接続状態を「未登録・確認中・有効・エラー」で表示します。起動時、保存時、「接続を再確認」時に、曲情報を送信しない認証確認を行います。
- ジャンル判定はOpenAIを優先し、失敗時はGemini、両方が失敗または未登録の場合はオフラインの内蔵AIへ自動的に切り替えます。切替理由と使用したプロバイダーを結果に表示します。
- OpenAIとGeminiのモデル名はそれぞれ変更できます。既定値はOpenAI `gpt-5.6-luna`、Gemini `gemini-3.5-flash`です。

## v0.6 の追加機能

- 曲一覧は通常クリックで選択開始、Commandクリックで個別追加／解除、Shiftクリックで最初に選んだ曲からクリックした曲までを連続選択できます。Command+Shiftでは既存選択へ範囲追加します。
- 「選択」メニューから表示中のページ（最大200曲）を一括選択できます。選択した曲は、タイトル、アーティスト、アルバム、アルバムアーティスト、ジャンル、ディスク番号、トラック番号をまとめて変更できます。トラック番号は開始番号から一覧順に連番を付けるか、同じ番号を設定できます。
- 一括編集には共通のアルバムジャケットを登録できます。JPEG/PNGのファイル選択に加えて、クリップボード内の画像をCommand+Vまたは「クリップボードから貼り付け」で取り込めます。画像は最大1600pxのJPEGへ正規化し、プレビューしてから適用します。
- 大量編集は曲ごとに作業コピーへ書き込み・読戻し検証してから原本へ反映し、進捗、失敗件数、キャンセルを表示します。一曲の失敗で残りすべてを中断しません。
- ジャケットのファイル書き込みは現在MP3（ID3 APIC）のみです。M4A/WAVが混ざる選択では実行前に明示して無効化し、意図しない部分更新を防ぎます。文字項目は従来どおり各対応形式で編集できます。

## v0.5 の追加機能

- アーティストタグが空の曲は、タグやファイルを変更せず、アーティスト一覧の「不明なアーティスト」に論理的にまとめます。項目を開くと該当曲をページング表示します。
- サイドバーの「メタデータ診断」で、曲名なし、不明なアーティスト、アルバム名なし、URLを含むMP3を個別に確認できます。
- 全角・半角、空白、大文字小文字の差と、軽いタイプミスの可能性を、キャンセル可能なバックグラウンド解析で候補化します。候補は自動修正せず、確認用にだけ表示します。
- ミニプレイヤーは別ウインドウを増やさず、同じウインドウを通常表示とミニ表示で切り替えます。ミニ表示にはアプリアイコンと通常表示へ戻すボタンがあります。
- 曲一覧を固定サイズのページ内 `LazyVStack` に変更し、列見出しと曲の間に生じていた大きな上下余白を解消しました。
- タイトル・アーティスト・アルバム・時間の列境界をドラッグして幅を変更できます。ツールバーの「表示項目」からタイトル・アーティスト・アルバム・時間・形式を個別に表示／非表示にでき、幅と表示状態は次回起動後も維持されます。
- 列を広げて画面幅を超えた場合は、列見出しと曲行が同期する横スクロールで隠れた列を表示できます。
- 曲一覧と右側の再生情報・歌詞パネルの境界も左右へドラッグして幅を変更でき、設定した幅は次回起動後も維持されます。
- 狭いウインドウではアルバム／アーティスト情報と検索操作を2段に切り替え、長い名前が一文字ずつ縦に折り返されないようにしています。
- ページ分母は各ビューの正確なDB総数です。現在ページの前後5ページと、その外側に「-1000」「-100」「-10」「+10」「+100」「+1000」を固定順で表示します。移動先が範囲を越える場合は先頭または最終ページへ安全に丸め、ページリンク自体は一定数だけを生成します。

## v0.4 の追加機能

- 曲を右クリックして「曲情報を編集…」を選ぶと、タイトル、アーティスト、アルバム、アルバムアーティスト、ジャンル、ディスク番号、トラック番号を編集できます。
- MP3はID3v2.3/2.4の対象テキストフレームを編集し、ID3v2.2以前は確認後にv2.3へ変換します。M4AはAudioToolbox、WAVはRIFF `LIST/INFO`を使います。アプリ内の一時コピーへ書き込み、読戻し検証とMP3音声バイトの保持を確認できた場合だけ原本へ反映します。読み取れるジャケット等を保持し、音声は再エンコードしません。
- ID3v2.4からv2.3へ書き換える際は、保持するフレームのサイズ表現も安全に変換します。実際に壊れたMP3タグを検出した場合は「タグを修復して保存」を提示し、音声開始位置を検証した作業コピー上でタグだけを再構築します。読み取れない追加タグや埋め込み画像が失われる可能性は確認画面に明示します。
- 「削除…」では「ライブラリからのみ削除」と「実ファイルをゴミ箱へ移動」を別ボタンで確認します。永久削除は行いません。
- ライブラリだけから外した曲は除外記録を保持し、再スキャンで意図せず復活しません。
- 以前の読み取り専用ブックマークで登録したフォルダは、最初の編集またはゴミ箱移動時だけフォルダの再選択を求め、読み書き権限を安全に更新します。
- コピー処理の内側に含まれるCocoa/POSIX権限エラーも検出し、読み取り専用の旧ブックマークだった場合は音楽ルートの再選択後に一度だけ安全に再試行します。

## v0.3 の追加機能

- 曲一覧の「タイトル」「アーティスト」「アルバム」「時間」「形式」をクリックすると、データベース上で昇順・降順を切り替えます。メモリ上で全曲を並べ替えることはありません。
- 設定の「表示」から日本語・English、システム・ライト・ダーク外観をアプリ内で切り替えて保存できます。
- WikipediaとGoogle Newsは選択言語の地域・言語版を取得します。内蔵ブラウザから開く外部記事は、選択言語のGoogle Translate表示へ導きます。
- アルバム一覧はアーティストと曲数、アーティスト一覧はアルバム数と曲数を表示します。名前をクリックすると、ページングされた詳細ページに移動します。
- 曲・アルバム・アーティストの見出しには件数、対象曲の合計容量（GB）、曲ファイルを含む登録ルートの絶対パスを表示します。容量とパスはSQLiteで集計し、曲の全件読み込みは行いません。
- アーティスト検索は先頭の `The ` を入力しなくても一致します。一覧の並び順と右端の索引も `The ` を無視しますが、表示名は変更しません。

## v0.2 の追加機能

- 「曲を取り込む」は、選択した音源をまずApplication Supportの `Inbox` にコピーします。設定画面で保存先を選び、各曲の「確認して移動」を押した場合だけ保存先へ移動します。
- 保存先はsecurity-scoped bookmarkで保持し、SSDからローカルフォルダへ変更できます。未接続時はサイドバーに警告を表示し、移動ボタンを無効化します。
- 曲一覧の星を押すと、曲情報を複製せず `お気に入り` 動的ビューへ表示します。
- 再生した曲は既定で直近24曲までApplication Supportの `OfflineCache` にコピーし、次回はローカルキャッシュを利用します。設定で無効化または0〜500曲へ変更できます。
- 再生中の曲は右側のインスペクタに歌詞、ライブラリ内の類似曲、Wikipedia、ニュース検索を表示します。歌詞はLRCLIB、アルバム情報はMusicBrainz/Cover Art Archive、WikiはMediaWiki APIを必要時だけ照会します。
- Web画像と歌詞はローカルへキャッシュします。ライブラリ全件への一括Web照会は行いません。
- ツールバーから同じウインドウをミニプレイヤー表示へ切り替えられます。
- 設定画面の「実装状況」で完了・一部完了・未着手を確認できます。

### v0.2 の保存場所

- DB: `~/Library/Containers/com.local.MassiveMusic/Data/Library/Application Support/MassiveMusic/MassiveMusic.sqlite`
- 新規曲の一時受信箱: `.../Application Support/MassiveMusic/Inbox`
- オフライン再生: `.../Application Support/MassiveMusic/OfflineCache`
- Web画像: sandbox内の `Library/Caches/MassiveMusic/WebArtwork`

音源を保存先へ移動する操作以外は、元のSSD上のファイルを変更・削除しません。移動はUI上の明示確認後にだけ実行されます。

### v0.2 の既知の制限

- SSDとの差分表示は現在「DBに登録済みだが最新スキャンで見つからない曲」の件数までです。SSD上にだけある未登録ファイルの専用差分一覧は未実装です。
- オフラインキャッシュは曲数上限のみです。アルバム枚数単位の上限は未実装です。
- 類似曲はローカルのジャンル・アーティスト・アルバムアーティストから算出します。音響特徴量によるジャンル推定は未実装です。
- アーティストニュースは保存や自動通知を行わず、アプリ内ブラウザでGoogle News検索を開きます。
- ジャンル行を開くと、そのジャンルのアルバム・アーティスト・曲を200件ずつ切り替えて閲覧できます。
- Wikipediaとニュースは右ペイン内に表示され、「情報へ戻る」で再生情報へ戻ります。
- AIジャンル候補は、OpenAI APIキーが未登録でもネットワークを使わない内蔵メタデータ分類器で利用できます。OpenAIを使う場合のキーはmacOS Keychainに保存され、曲名・アーティスト・アルバム等のメタデータだけを送信します。音声解析ではなく、候補のファイル適用には確認操作が必要です。右ペインの設定リンクはAIタブとAPIキー入力欄を直接開きます。
- 曲の右クリックまたは類似曲の追加ボタンから「次に再生」へ追加できます。キューはSQLiteへtrack IDと順序だけを保存し、右ペインで100件ずつ表示します。
- 類似曲の曲名をクリックするとその曲の再生へ切り替わり、右ペインは歌詞表示へ戻ります。情報タブのYouTubeボタンは検索結果と動画を右ペイン内に表示します。
- 曲・アルバム・アーティスト一覧の右端には、A–Z、五十音、0–9の縦スクロール索引があります。文字を押すとSQLiteで位置を求め、その位置から200件だけを読み込みます。
- 一覧と再生情報の境界には常時表示のグリップがあります。18pxの範囲をドラッグして幅を変更でき、ダブルクリックで標準幅へ戻せます。
- Web提供元に一致データがない曲、ネット接続がない場合、画像・歌詞・Wikiは表示されません。

MassiveMusic is a native Apple Silicon macOS application for searching, organizing, and playing very large local music libraries stored on external drives. The first release focuses on predictable memory use and library availability rather than cloud or tag-editing features.

## Requirements

- Apple Silicon Mac
- macOS 26 or later
- Xcode 26 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate the checked-in Xcode project

GRDB 7.10.0 is resolved by Swift Package Manager. No global package installation or `sudo` is required by the project.

## Build and test

```sh
xcodegen generate
xcodebuild -project MassiveMusic.xcodeproj \
  -scheme MassiveMusic \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project MassiveMusic.xcodeproj \
  -scheme MassiveMusic \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO test
```

Open `MassiveMusic.xcodeproj` in Xcode for a signed local run. Select your development team if Xcode requests one.

## Use

1. Launch MassiveMusic.
2. Choose **File → 音楽フォルダを追加…** (`Shift-Command-O`) or use the folder toolbar button.
3. Select a folder containing MP3, M4A, or WAV files.
4. The scan runs outside the main actor and commits every 750 files. Use the status bar to pause, resume, or cancel it.
5. Double-click a row to play it. Click a column header once for ascending order and again for descending order. Search is debounced and cancellable; the table displays only one 200-row keyset page at a time.

The sidebar provides tracks, albums, artists, genres, folders, and playlists. Playlist imports and exports accept M3U/M3U8. The **All Tracks** view is dynamic and never creates a fixed 360,000-item playlist or queue.

The **Metadata Diagnostics** section pages deterministic issue lists directly from SQLite. Variation analysis persists distinct terms and bounded candidate buckets in SQLite instead of loading all tracks into memory. Typo candidates are heuristic review hints and are never applied automatically.

The **Log** section under **Manage** records file additions, scan-detected changes, metadata edits, unavailable/restored files, library-only removals, and files moved to Trash. Log rows retain path and metadata snapshots, support type filters and text search, and are fetched in 200-row pages. The newest 100,000 entries are retained; installing schema v7 does not fabricate history for earlier activity.

The **Up Next** queue is persisted in SQLite as track IDs and order only. Its inspector page fetches 100 rows at a time; Next consumes one queued row before falling back to adjacent or bounded-shuffle playback.

## Storage

The database is stored at:

```text
~/Library/Application Support/MassiveMusic/MassiveMusic.sqlite
```

For a sandboxed build, macOS may map this path into the application container. Artwork thumbnails are stored under the user Caches directory in `MassiveMusic/Artwork`. No database, cache, or settings are written into the selected music folder.

The database uses WAL mode, foreign keys, versioned migrations, FTS5 synchronization triggers, and short transactions. Security-scoped bookmarks retain read/write access to user-selected roots; file mutations still require an explicit in-app action.

## Architecture and scale safeguards

- Track tables and playlists are fetched in bounded pages.
- Track browsing uses keyset cursors, avoiding deep `OFFSET` queries during normal scrolling.
- FTS5 queries run on the database reader pool after a 280 ms UI debounce.
- Scanning, metadata parsing, playlist bulk operations, and database reads do not run on the main actor.
- Scanner state and its resume cursor are persisted after each 750-file commit.
- Deleted or disconnected tracks are marked unavailable, not immediately deleted.
- Shuffle selects bounded deterministic candidate buckets and never runs `ORDER BY RANDOM()` over the full library.
- Artwork is decoded only on demand, with 64 MB memory and 2 GB disk cache limits.

## Performance and verification

See [PERFORMANCE.md](PERFORMANCE.md) for commands and measurements from the 360,000-row synthetic benchmark and real WAV playback smoke test.

## Known limitations

- The target drive `/Volumes/Transcend/Music/Music` was fully scanned on 2026-07-16: 370,270 tracks were registered with no scan errors. See `PERFORMANCE.md` for the filesystem/DB reconciliation and measurements.
- Playlist rows can be moved one position at a time from the row context menu; drag-and-drop reordering is deferred.
- Folder views are paged textual facets. Genre rows drill down to separately paged albums, artists, and songs; dedicated artwork grids are deferred.
- Media key and Now Playing handlers are implemented but depend on the active macOS media-session policy and were not exhaustively tested with every keyboard model.
- A CoreSimulator version warning may appear in `xcodebuild` output on this Mac. macOS builds and tests still run successfully; no simulator is used.
- The direct WAV tag writer currently supports standard RIFF/WAVE files up to 4 GB. RF64 metadata editing is rejected without changing the original.

## Safety

Normal scanning, searching, browsing, and playback open source audio read-only. Source files are changed only after the user explicitly chooses **Save to File** or **Move Source File to Trash**; metadata writes use a verified temporary copy and deletion uses the recoverable macOS Trash.

If an older scan bookmark only grants read access, the first edit asks the user to choose the original music root again. MassiveMusic retains that live security scope until the temporary copy is verified and the source replacement finishes, then stores the renewed bookmark for later edits.
