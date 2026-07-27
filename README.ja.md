# Vibe

<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-256.png" width="128" alt="Vibe app icon">
</p>

<p align="center">
  <a href="README.md">English</a> | 日本語
</p>

Vibeは、大容量のローカル音楽コレクションをMacと外付けストレージで管理するためのmacOS音楽プレイヤーです。曲をストリーミングサービスへ預けず、手元のMP3・M4A・WAV・FLACを高速に検索、再生、整理できます。

> 現在のリリースはApple Silicon向けです。配布バイナリはアドホック署名で、Appleによる公証は行っていません。

## 特長

### 大規模ライブラリ

- SQLite／GRDBとFTS5を使った検索、ソート、ページング
- 37万曲規模でも全曲を一度にメモリへ読み込まない設計
- MP3、M4A、WAV、FLACのスキャンと再生
- 曲、アルバム、アーティスト、ジャンル、フォルダ、お気に入り、最近追加した曲を横断して閲覧
- 表示列の並び順、表示／非表示、列幅を保存
- アーティスト一覧へ戻った際のスクロール位置を復元

### 外付けSSDとオフライン再生

- メイン保管先の接続状態をサイドバーへ表示
- SSDが外れていてもライブラリのメタデータを保持
- 再生曲をMac側へ自動キャッシュし、接続時は原本、切断時はキャッシュから再生
- お気に入りとプレイリスト内の曲はLRU整理の対象外として保護
- SSD切断中に取り込んだ曲をMacへ一時保管し、再接続後に移動
- キャッシュ、差分、保管先、取り込み状態を「設定と管理」に集約

### 再生とギター練習

- 右ペイン上部に常設した再生コントロール
- ランダム、一曲リピート、アルバム／プレイリストリピート
- 60〜95%の5%刻みと100%の再生速度
- 再生速度を維持したまま半音下げ／原音／半音上げ
- 曲ごとに3枠保存できるA–B区間リピート
- 練習設定と区間をアプリ終了後も復元
- Chordifyを表示する「コード」タブと内蔵ブラウザの戻る操作
- 固定サイズのミニプレイヤー

### 曲情報と発見

- 右ペインに曲情報、歌詞、発見、練習、コードを表示
- 未再生時は話題の曲、YouTube、音楽ニュースへのリンクを表示
- YouTubeや外部記事を内蔵ブラウザで開き、情報へ戻る際はメディアを停止
- 埋め込みジャケットを優先し、取得できない場合は外部アートワークへフォールバック
- 歌詞キャッシュと同期歌詞の自動スクロール

### プレイリストと操作

- プレイリスト作成、削除、ドラッグ並び替え、ダブルクリックでの名前変更
- M3U／M3U8の読み込みと書き出し
- Shift／Commandクリックによる複数選択
- 複数曲をまとめてお気に入りやプレイリストへ追加
- 空のプレイリストでも表示が点滅しない安定した空状態
- ライブラリ項目の表示／非表示と並び替え

### 安全なメタデータ編集

- MP3、M4A、WAVのタイトル、アーティスト、アルバム、アルバムアーティスト、ジャンル、番号を編集
- 複数曲のアーティスト、アルバム、アルバムアーティスト、ジャンル、ディスク番号を一括編集
- 作業コピーへ書き込み、読戻しと音声データを検証してから原本へ反映
- 失敗時は原本を復元し、実ファイル削除はゴミ箱を使用
- 古いID3v2.2を確認後にID3v2.3へ安全変換し、同じ操作内で編集を完了
- バックグラウンドでのID3移行、文字幅正規化、MusicBrainz番号候補
- 重複、欠損、文字化け、表記ゆれをメタデータ診断で確認

### AIジャンル候補

- OpenAI、Gemini、内蔵ルールの順で利用可能な判定経路へフォールバック
- 確信度80%以上の未分類曲だけを自動登録する設定
- 既存ジャンルは自動で上書きしない安全設定
- APIキーはKeychainへ新規保存せず、Vibeのアプリ内保護データベースへ保存
- 起動時はAPIキー本文を読み出さず、登録状態だけを復元

## 画面構成

```mermaid
flowchart LR
    Sidebar["左ペイン\nライブラリ・プレイリスト・管理"]
    Library["中央ペイン\n検索・一覧・編集"]
    Inspector["右ペイン\n再生・情報・歌詞・練習・コード"]
    Sidebar --> Library --> Inspector
```

バックグラウンド解析やID3移行の進捗は左ペイン下部へまとめ、中央の曲一覧の高さを消費しません。左右のペインは開閉でき、右ペインは幅を調整できます。

## 動作環境

- Apple Silicon Mac
- macOS 26.0以降
- Xcode 26系（ソースからビルドする場合）
- インターネット接続はMusicBrainz、外部記事、YouTube、Chordify、AIプロバイダーを使う場合のみ必要

## インストール

GitHub Releasesから`Vibe-v0.15.0-macos-arm64.zip`をダウンロードし、展開した`Vibe.app`を任意の場所へ移動してください。

現在の配布物は公証されていません。macOSが初回起動を止めた場合は、FinderでVibeをControlクリックして「開く」を選択し、表示内容を確認したうえで起動してください。

## ソースからビルド

依存するGRDBはSwift Package Managerが自動取得します。

```bash
git clone https://github.com/nanonigit/Vibe.git
cd Vibe
xcodebuild \
  -project MassiveMusic.xcodeproj \
  -scheme MassiveMusic \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .build \
  build
open .build/Build/Products/Release/Vibe.app
```

## テスト

```bash
xcodebuild \
  test \
  -project MassiveMusic.xcodeproj \
  -scheme MassiveMusic \
  -destination 'platform=macOS'
```

大規模ライブラリ向けの確認方法は[PERFORMANCE.md](PERFORMANCE.md)も参照してください。

## データと安全性

- ライブラリDBとオフラインキャッシュは`Application Support/MassiveMusic`配下に保存します。
- 既存ユーザーとの互換性維持のため、表示名がVibeになった後もBundle IDと保存ディレクトリ名には`MassiveMusic`が残ります。
- 音楽フォルダへのアクセスはユーザーが選択したパスとセキュリティスコープ付きブックマークで管理します。
- メタデータ変更は作業コピーと検証を経由しますが、重要な音源は別途バックアップすることを推奨します。
- APIキー、音源パス、ライブラリDBをリポジトリへコミットしないでください。

## 現在の制限

- FLACはスキャンと再生に対応しますが、タグの直接書き戻し対象はMP3、M4A、WAVです。
- ジャケットのファイル書き込みとコンピレーションタグは現在MP3のみ対応します。
- Chordify、YouTube、ニュースなど外部サイトの表示は各サービスの仕様や利用条件に依存します。
- 配布アプリはAppleによる公証を行っていません。

## 技術構成

- Swift 6 / SwiftUI / AppKit
- AVFoundation / AVAudioEngine
- SQLite / GRDB / FTS5
- XCTest / Swift Testing

第三者ライブラリについては[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)を参照してください。
