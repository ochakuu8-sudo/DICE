param(
    [string]$GodotPath = "C:\Godot_v4.7.1-stable_win64.exe"
)

$ProjectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$WindowsOut = Join-Path $ProjectPath "builds\windows\DiceBoardRogue.exe"
$WebOut = Join-Path $ProjectPath "builds\web\index.html"

if ((Test-Path -LiteralPath $GodotPath -PathType Container)) {
    $ConsolePath = Join-Path $GodotPath "Godot_v4.7.1-stable_win64_console.exe"
    $GuiPath = Join-Path $GodotPath "Godot_v4.7.1-stable_win64.exe"
    if (Test-Path -LiteralPath $ConsolePath) {
        $GodotPath = $ConsolePath
    } else {
        $GodotPath = $GuiPath
    }
}

if (!(Test-Path -LiteralPath $GodotPath)) {
    Write-Error "Godot executable was not found: $GodotPath"
    exit 1
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $WindowsOut), (Split-Path -Parent $WebOut) | Out-Null

& $GodotPath --headless --path $ProjectPath --export-release "Windows Desktop" $WindowsOut
$WindowsExit = $LASTEXITCODE

& $GodotPath --headless --path $ProjectPath --export-release "Web Mobile" $WebOut
$WebExit = $LASTEXITCODE

if ($WindowsExit -ne 0 -or $WebExit -ne 0) {
    Write-Error "One or more exports failed. Windows exit: $WindowsExit; Web exit: $WebExit"
    exit 1
}

exit 0
