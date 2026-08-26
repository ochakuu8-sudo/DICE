# Dice Board Rogue

Godot 4.7向けの、探索すごろくとダイス戦闘を組み合わせたローグライクRPG試作です。

## 遊び方

- 3層の8x8探索盤は最初から公開されています。探索ダイスを振り、出目とちょうど同じ距離にあるマスを選びます。
- 探索ダイスを振ると、周回を通じて残る疲労が増えます。疲労を払って振り直すこともできます。
- 戦闘に入ると、キャラ固有の5x5すごろくボードで戦います。HPは戦闘ごとの資源で、次の戦闘開始時に全回復します。
- 新しく引いたダイスは伏せた状態（?）で手札に並び、画面をタップするとまとめて振られます。
- 毎ターン、出た目から最大2個まで選んで使います。
- 選んだダイスの出目ぶん、一本道のコースを自動で前進します。
- 通過したマスと止まったマスの効果が自動発動します。
- 使わなかったダイスは目をそのままに次のターンへ残るので、次のターンに伏せられるのは補充された分だけです。振り直しは手札全体をまとめて振り直すので、残した目も一緒に変わります。
- 敵を倒すと、マスかダイスの報酬を1つ選びます。マスは永続ボードに配置され、次の戦闘にも持ち越されます。
- 戦闘でHPが0になると報酬は得られず、疲労だけが増えて探索へ戻ります。疲労が限界の状態でボスに敗れるとゲームオーバーです。
- 各層のボスを倒すと次の探索盤へ進み、3層目を突破するとクリアです。

## 出力想定

Godotでこのフォルダを開き、Exportから以下のプリセットを使います。

- Windows Desktop: `builds/windows/DiceBoardRogue.exe`
- Web Mobile: `builds/web/index.html`

Web版はスマホブラウザのタッチ操作を想定したボタンUIです。直接ファイルを開くのではなく、HTTPサーバー越しに `index.html` を開いてください。

この環境では `C:\Godot_v4.7.1-stable_win64.exe` はフォルダで、その中にGodot本体があります。4.7.1 stableのエクスポートテンプレートも導入済みです。

PowerShellからまとめて書き出す場合:

```powershell
.\export_all.ps1 -GodotPath "C:\Godot_v4.7.1-stable_win64.exe"
```

このパスがフォルダの場合は、中の `Godot_v4.7.1-stable_win64_console.exe` を自動で使います。

エディタで開く場合:

```powershell
.\run_editor.ps1 -GodotPath "C:\Godot_v4.7.1-stable_win64.exe"
```

## テスト

`tests/` はエディタを開かずに走るヘッドレステストです。エクスポートには含まれません
（`export_presets.cfg` の `exclude_filter`）。

```powershell
& "C:\Godot_v4.7.1-stable_win64.exe" --headless --path . --script tests/test_preview.gd
& "C:\Godot_v4.7.1-stable_win64.exe" --headless --path . --script tests/test_readout.gd
& "C:\Godot_v4.7.1-stable_win64.exe" --headless --path . --script tests/test_debuffs.gd
& "C:\Godot_v4.7.1-stable_win64.exe" --headless --path . --script tests/test_newcontent.gd
& "C:\Godot_v4.7.1-stable_win64.exe" --headless --path . --script tests/test_fall.gd
& "C:\Godot_v4.7.1-stable_win64.exe" --headless --path . --script tests/test_exploration.gd
```

- `test_preview.gd`: ダイスの1タップ目が情報表示だけで、2タップ目で確定することを確認します。
- `test_readout.gd`: マスに表示される数字と、実際に与えるダメージが一致することを確認します。
- `test_debuffs.gd`: 16マスのリング形状、敵デバフ4種（毒・炎上・凍結・茨）の挙動、
  チャージが「撃たずに待ったターン数」として動くことを確認します。
- `test_newcontent.gd`: 条件付きマス（出目上限・盾所持・毒閾値・手番）と、
  1〜6の外に面を持つダイス（居合の0、大車輪の7〜9）を確認します。
- `test_fall.gd`: 戦闘HPのリセット、戦闘敗北時の疲労、限界時のボス敗北を確認します。
- `test_exploration.gd`: 8x8探索盤、探索ダイスの疲労コスト、振り直し、移動、フロア遷移を確認します。

どちらも失敗が0なら終了コード0を返します。

## 生成済みビルド

GitHub Pages用のWebビルドは、リポジトリのルートにある `index.html` などへ配置しています。

この `godot_project` フォルダは編集用のGodotプロジェクト本体です。Godot 4.7以降でこのフォルダをインポートしてください。
