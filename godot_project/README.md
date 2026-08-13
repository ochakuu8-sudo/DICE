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

## 生成済みビルド

GitHub Pages用のWebビルドは、リポジトリのルートにある `index.html` などへ配置しています。

この `godot_project` フォルダは編集用のGodotプロジェクト本体です。Godot 4.7以降でこのフォルダをインポートしてください。
