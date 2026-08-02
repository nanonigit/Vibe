# タスク: チェック式自動処理と狭幅レイアウト

- [x] 現在の設定、タスクのライフサイクル、ヘッダー、共通プレイヤー実装を確認する。
- [x] 自動処理設定とテーブル操作の狭幅表示についてLazywebの実例を確認する。
- [x] チェックだけで動く仕様とコンパクト配置の回帰テストを追加する。
- [x] 各保存処理を、オンで開始・オフでキャンセルするよう統一する。
- [x] 重複する開始・停止ボタンを消し、進捗表示だけ残す。
- [x] ライブラリヘッダーと検索窓にコンパクト配置を追加する。
- [x] 操作を欠けさせない共通プレイヤーのコンパクト配置を追加する。
- [x] 保存される翻訳スイッチ、右ペイン状態表示のクリック、現在ページの再読込を追加する。
- [x] 表記ゆれ上下選択、確認、安全な一括書込、一覧更新を追加する。
- [x] アプリを起動せず、対象テスト、全テスト、Apple Silicon Debugビルドを実行する。
  - 対象回帰テストは成功。`LibraryDatabaseTests` 全体では既存の3件（`migrationEnablesExpectedSchemaAndWAL`、`compactBatchEditorAndResizableSummaryColumnsAreWired`、`cacheRetentionLimitCanBeTypedAndStepped`）のみ失敗が継続。arm64 Debugビルドは成功。
- [x] 修正記録と再発防止を英語・日本語で記録する。
