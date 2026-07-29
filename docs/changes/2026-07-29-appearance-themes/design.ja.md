# 外観テーマ 設計

## 調査根拠

Lazywebのデスクトップテーマ設定例では、Todoistの色見本カード、Slack/Craftの明暗グループが、文字だけのPickerより比較しやすい。Vibeでは6枚を「ダーク」「ライト」の2グループで表示する。

## 構成

- `AppearanceMode` を6テーマへ拡張し、各テーマが `AppearancePalette` を返す。
- パレットは canvas / sidebar / library / inspector / elevated / divider / selection / accent を持つ。
- ルートで明暗とaccentを適用し、主要ペインには対応するsurface色を明示する。
- SwiftUIのcolor schemeと`NSApplication`/`NSWindow`の外観を同期し、AppKit標準部品がライトテーマでダーク用の文字・部品色を保持しないようにする。
- 設定画面は小さな3ペインのプレビューカードを2列で表示し、選択中を枠とチェックで示す。
- DBの `app.appearance` にraw valueを保存する。旧値は初期化時に移行する。
