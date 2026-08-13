param(
    [string]$GodotPath = "C:\Godot_v4.7.1-stable_win64.exe"
)

$ProjectPath = Split-Path -Parent $MyInvocation.MyCommand.Path

if ((Test-Path -LiteralPath $GodotPath -PathType Container)) {
    $GodotPath = Join-Path $GodotPath "Godot_v4.7.1-stable_win64.exe"
}

if (!(Test-Path -LiteralPath $GodotPath)) {
    Write-Error "Godot executable was not found: $GodotPath"
    exit 1
}

& $GodotPath --path $ProjectPath
