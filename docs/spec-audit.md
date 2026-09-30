# HCC OS 仕様適合監査

仕様書 `CLAUDE_SPEC.md` の受け入れ条件をコード確認と実行確認に分けて追跡します。「実装あり」はソース上の経路を確認した状態で、CraftOS/Minecraft/Tom's Peripherals上での成功を意味しません。

## 監査結果

| 要件 | ソース上の証拠 | 状態 |
|---|---|---|
| 576×320論理座標、実画面への拡大縮小と入力座標変換 | `system/ui/gpu_toms.lua`, `system/core/runtime.lua` | 実装あり。複数解像度の実機表示は未確認 |
| Tom's GPU検出、周辺機器能力の列挙、アプリ単位の利用可否表示 | `system/core/capabilities.lua`, `system/core/bootstrap.lua`, `system/ui/desktop_view.lua`, `tests/capabilities_spec.lua` | 必須メソッドの完全一致、部分Detector、切断後の再スキャン、列挙/API例外の隔離をホストテストで確認。実機周辺機器の組合せは未確認 |
| 描画バックエンド不在時の復旧経路 | `system/core/bootstrap.lua`, `system/core/recovery.lua` | 回復経路あり。GPUなし起動の実機操作は未確認 |
| 起動エントリの引数、失敗ログ、Recoveryへの引渡し | `startup.lua`, `tests/startup_spec.lua` | ブート引数の転送、成功時に不要なログを残さないこと、失敗理由のログ保存とstandalone Recoveryへの引渡しをモックFS上で確認。CraftOS起動全体は未確認 |
| ダメージ領域、保持描画、アイドル時の描画要求停止 | `system/core/window_manager.lua`, `system/ui/compositor.lua`, `system/core/scheduler.lua`, `tests/scheduler_spec.lua` | scheduler heartbeatとアプリタイマーをモックイベントキューで実行し、500回の連続アプリ更新を通じてタイマー再設定、idle時に再描画しないこと、イベント待ち中にbusy loopしないこと、正常終了・イベントポンプ例外時に未処理システムタイマーを解放することを確認。長時間の実測負荷は未計測 |
| 適応fps、段階値、入力イベントと独立したイベントポンプ | `system/core/performance.lua`, `system/core/scheduler.lua`, `tests/performance_spec.lua`, `tests/scheduler_spec.lua` | タイマー刻み、15fpsの分数tick配分、過負荷時の段階降下と品質切替、scheduler heartbeatとアプリ更新タイマーの配送をホストテストで確認。ただしCC:Tの50msタイマー刻みにより20TPS時の理論上限は20fpsで、サーバー負荷時はさらに下がります。60/45/30fpsの実機描画は未達であり、fps・入力遅延も未計測 |
| 低fps時の品質段階 | `system/core/performance.lua`, `system/core/image_codec.lua`, `system/apps/calendar/app.lua` | CPU画像の2倍/4倍サンプリング、カレンダー遷移省略を実装。段階切替後の壁紙コマンド再生成を接続。高負荷時の効果は未計測 |
| タスクバー、検索付きスタートメニュー、テーマ | `system/ui/taskbar.lua`, `system/ui/start_menu.lua`, `system/core/window_manager.lua`, `system/core/runtime.lua` | 基本UIとセッション内の最近使ったアプリ4件を実装し、最近順で検索なしの一覧へ反映。タスクバーとスタートメニューの角丸描画・ヒットテストも共有Geometryで揃えた。実画面レイアウトは未確認 |
| UIオーバーレイ境界とタスクバー溢れ | `system/ui/start_menu.lua`, `system/ui/taskbar.lua`, `tests/ui_layout_spec.lua` | 576×320とUIスケール2の288×160論理画面でメニュー/ダイアログ/コンテキストメニュー/通知領域、最近アプリ行のヒット座標、24ウィンドウ時のタスクバー可視範囲とアクティブウィンドウ再表示を確認。実画面の視覚品質は未確認 |
| 角丸ウィンドウ、透明・ぼかし表現 | `system/lib/hcc/geometry.lua`, `system/lib/hcc/color.lua`, `system/ui/canvas.lua`, `system/ui/compositor.lua`, `system/core/image_codec.lua`, `system/core/runtime.lua`, `system/core/input.lua` | 共有角丸マスクを描画・ヒットテストに実装。描画済み壁紙の固定48点サンプルを不透明なUI面へ上限付きで混ぜるMica風近似を実装。半透明・ぼかしは未対応。GPU上の外観は未確認 |
| 画像API公開、入力上限、描画コマンド予算 | `system/core/image_codec.lua`, `system/lib/hcc/qoi_d.lua`, `tests/image_codec_spec.lua` | HCCIの画素数・RLE上限、PNG/JPEG不正ヘッダー、QOIサイズ拒否・正常デコード・ファイル読込・破損時の例外封じ込め、必要なデコーダ/インポート関数の公開、詳細画像描画のfill命令上限をFengariで確認。実画像コーパスとGPU表示は未確認 |
| ウィンドウの移動、リサイズ、最小化、最大化、復元、終了 | `system/core/window_manager.lua`, `system/core/window_actions.lua`, `system/core/input.lua`, `system/ui/compositor.lua` | 実装あり。マウス/キーボードでの手動回帰は未確認 |
| 入力優先順位、標準/周辺機器イベント、異常イベント | `system/core/input.lua`, `tests/input_spec.lua` | 不正イベント、欠損キー/座標、未登録キーボードを無視し、アプリ向けシステムイベントからキー/マウス入力を除外する回帰をFengariで確認。実機操作は未確認 |
| 確認ダイアログと文字入力ダイアログの分離 | `system/core/window_manager.lua`, `system/core/input.lua`, `system/ui/compositor.lua` | `nil`入力が`"nil"`へ変わって全モーダルに入力欄が出る問題を修正。ボタン遷移の実機確認は未確認 |
| 共通Widgetの操作契約 | `system/ui/widgets.lua`, `system/core/input.lua`, `system/core/window_manager.lua` | 無効な操作コールバックを空関数で隠さず、入力しない表示要素はヒット領域を作らない。ドロップダウンの重複領域を除去し、スライダーとリストへクリック値を渡す。アプリコンテキストからウィンドウへヒット領域を登録し、タブ選択のコールバック値を固定する。実画面操作は未確認 |
| アプリパッケージのエントリ解決と初期ライフサイクル | `system/core/app_registry.lua`, `system/core/app_manager.lua`, `tests/app_registry_spec.lua`, `tests/app_manager_spec.lua`, `tests/app_modules_spec.lua` | 実マニフェストをRegistryが検出し、AppManagerがサービス/通常/boot-only Setupを読み込む経路を確認。代替エントリ・欠落・パストラバーサル、失敗時フォールバック、22パッケージすべての登録と空状態での`init`/`interval`/`update`/`draw`をFengari上で確認。描画は共通キャンバスモックであり、画面の視覚品質・CraftOS実機回帰は未確認 |
| モジュール読込とキャッシュ | `system/core/module_loader.lua`, `tests/module_loader_spec.lua` | 名前表記を正規化して同じモジュールの二重読込を防止。ローダー単位のキャッシュ分離、循環依存、失敗後の再試行とキャッシュ解除をホストテストで確認 |
| アプリごとの状態・タイマー・HTTP要求の隔離と例外封じ込め | `system/core/app_registry.lua`, `system/core/app_manager.lua`, `system/core/scheduler.lua`, `system/core/http_service.lua`, `tests/window_manager_spec.lua`, `tests/http_service_spec.lua` | Fengariで複数ウィンドウの状態分離、最小化/復帰時のタイマー管理、アプリ例外後のOS継続と一度だけの後始末、HTTP要求の取消・応答所有・失敗時クローズを確認。MODネットワーク実機動作は未確認 |
| `fit`/`fill`/`center`/`stretch`/`tile`/`solid`と壁紙解除 | `system/core/config.lua`, `system/apps/settings/app.lua`, `system/core/image_codec.lua` | 設定・描画経路あり。6モードの視覚結果は未確認 |
| 壁紙設定の保存・再起動後復元、壊れた画像からの復帰 | `system/core/config.lua`, `system/core/image_codec.lua`, `system/core/file_service.lua` | 保存とフォールバック経路あり。再起動・破損入力の実機確認は未実施 |
| 設定の既定値、範囲正規化、保存バックアップ、破損復旧 | `system/core/config.lua`, `tests/config_spec.lua` | 有効設定の読み込み、fps範囲補正、単純な拡張値保持、原子的保存と失敗時ロールバック、破損プライマリの隔離と`.bak`復旧をホストテストで確認。実機再起動と電源断は未試験 |
| 原子的ファイル保存、ログ上限、管理ファイル保護 | `system/core/file_service.lua`, `system/core/logger.lua`, `tests/file_service_spec.lua` | 原子的な作成・上書き、コミット失敗時のロールバック、中断保存からの復旧、保護パス、管理ファイル所有権をホストテストで確認。実機ファイルシステムでの電源断試験は未実施 |
| 構文、起動から終了までの基本操作、境界値 | 全配布Luaおよび起動経路 | Lua 5.2文法を指定した`luaparse` 0.3.1で107個のLuaファイルを解析し、構文エラー0件。`tests/run.lua`の18個のホスト回帰テストをFengari 0.1.5上で実行し成功。OS起動・画面操作・MOD API互換性・実機境界値は未確認 |

## 仕様上の差分と制約

- 仕様は最大60fpsを求めますが、現行スケジューラーは `os.startTimer` を使い、CC:Tではタイマーが50ms刻みです。20TPS時のタイマー駆動描画の理論上限は20fpsで、サーバー負荷時はさらに下がります。60/45/30fpsを選んでも同じ描画間隔を作れません。実行環境側の別APIを確認できていないため、上限超過を偽って表示しません。[CC:Tのタイマー仕様](https://tweaked.cc/module/os.html#v:startTimer)。Tom's PeripheralsのGPU公開メソッドとキーボードのイベント契約は[GPU Peripheral](https://github.com/tom5454/Toms-Peripherals/wiki/GPUExt)、[GPU API](https://github.com/tom5454/Toms-Peripherals/wiki/GPUImpl)、[Keyboard](https://github.com/tom5454/Toms-Peripherals/wiki/Keyboard)で照合しました。これらは静的なAPI照合であり、対象MODの実機動作確認ではありません。
- GPU機能を使うUIの半透明・ぼかしは未対応です。代わりに、壁紙ジョブ完了時だけデコード済み画素を48点サンプリングし、壁紙に連動する不透明な近似色をUI面へ反映します。画面描画ごとの画像走査はしません。角丸と色の実機外観・入力反応は未確認です。
- この作業環境にはネイティブLua 5.2、CraftOS実行環境、Tom's GPUがなく、受け入れ条件の実機試験および性能記録を完了できていません。ホスト単体テストはFengari上で実行しましたが、CC:Tとの同等性を示すものではありません。数値は測定できていない項目を「未計測」として扱います。

## 次の実機確認

1. クリーン起動、論理576×320表示、マウスとコンピューターキーボードの主要操作。
2. 壁紙6モード、解除、存在しない/壊れた/大きな画像、再起動後の復元。
3. スタート検索、複数アプリ、移動/リサイズ/最小化/最大化/復元/終了、アプリ異常終了後の継続。
4. 負荷中の目標・実測fps、品質切替、入力応答、壁紙/大画像デコード時間、ピークメモリ。
5. GPU・各任意周辺機器の取り外し、設定破損、ログと復旧経路。

## この作業環境での検査記録

- Lua 5.2構文解析: `luaparse` 0.3.1で107ファイル、構文エラー0件。依存物はnpmキャッシュから一時利用し、リポジトリへ追加していない。
- `tests/run.lua`経由で起動/Recovery、デスクトップ正常終了・失敗・復旧要求時の後始末、22アプリパッケージの登録と空状態での`init`/`interval`/`update`/`draw`、UIオーバーレイ境界とタスクバー溢れ、500回の連続アプリ更新を含むschedulerのイベント待ち/タイマー所有権とイベントポンプ例外後の解放、画像API公開/入力上限/描画コマンド予算、モジュール読込、アプリレジストリ/管理、ファイル/HTTPサービス、能力検出、性能制御、設定、ウィンドウ管理、入力ルーター、色処理、テーマ統合の18仕様をFengari 0.1.5で実行し、すべて成功。描画は共通キャンバスモックであり、実画面での視覚品質は未確認。VMと依存物はnpmキャッシュから一時利用し、リポジトリへ追加していない。
- 配布マニフェスト: 84項目、重複・欠落・64KiB超のファイルなし。ルートと`system/`の項目集合は一致。
- ルート配布物の宣言サイズ: 650219 bytes。`startup.lua`: 4582 bytes。
- `git -c core.autocrlf=false diff --check`: 指摘なし。
- `system/**/*.lua` のTODO/FIXME/placeholder/stub検索: 該当なし。
- ネイティブ`lua`/`luac`/`luajit`とCraftOSはなく、アプリ統合動作・実機API・FPS等は未計測。
