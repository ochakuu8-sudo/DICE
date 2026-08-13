# DICE

すごろくローグライクRPG試作 `Dice Board Rogue` のリポジトリです。

## Play

GitHub Pagesでは、リポジトリルートのWeb書き出しをそのまま公開します。

- Branch: `main`
- Folder: `/ (root)`
- Entry point: `index.html`

## Edit In Godot

Godotで編集する場合は、`godot_project/` フォルダをGodot 4.7以降でインポートしてください。

主な編集ファイル:

- `godot_project/project.godot`
- `godot_project/main.tscn`
- `godot_project/scripts/Main.gd`
- `godot_project/assets/NotoSansJP.ttf`

PowerShellでエディタを開く例:

```powershell
cd godot_project
.\run_editor.ps1 -GodotPath "C:\Godot_v4.7.1-stable_win64.exe"
```

Web/Windowsを書き出す例:

```powershell
cd godot_project
.\export_all.ps1 -GodotPath "C:\Godot_v4.7.1-stable_win64.exe"
```

`C:\Godot_v4.7.1-stable_win64.exe` がフォルダの場合は、中のGodot console exeを自動で使います。
