# Dice Board Rogue

Godot 4.7向けの、すごろくローグライクRPG試作です。

## 遊び方

- キャラクターを選ぶと、キャラ固有の5x5すごろくボードで戦闘が始まります。
- 毎ターン、手札のダイスから最大2個まで選べます。
- ダイスを振ると、一本道のコースを出目ぶん自動で前進します。
- 通過した敵には攻撃判定が発生します。
- 通過したマスと止まったマスの効果が自動発動します。
- 敵を全滅させると、毎回スキルマス報酬を1つ選び、永続ボードに配置します。
- 配置したマスは次の戦闘にも持ち越されます。
- 第6戦のボスを倒すとクリアです。

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
```

- `test_preview.gd`: ダイスの1タップ目が情報表示だけで、2タップ目で確定することを確認します。
- `test_readout.gd`: マスに表示される数字と、実際に与えるダメージが一致することを確認します。
- `test_debuffs.gd`: 16マスのリング形状、敵デバフ4種（毒・炎上・凍結・茨）の挙動、
  チャージが「撃たずに待ったターン数」として動くことを確認します。
- `test_newcontent.gd`: 条件付きマス（出目上限・盾所持・毒閾値・手番）と、
  1〜6の外に面を持つダイス（居合の0、大車輪の7〜9）を確認します。

どちらも失敗が0なら終了コード0を返します。

## 生成済みビルド

GitHub Pages用のWebビルドは、リポジトリのルートにある `index.html` などへ配置しています。

この `godot_project` フォルダは編集用のGodotプロジェクト本体です。Godot 4.7以降でこのフォルダをインポートしてください。
