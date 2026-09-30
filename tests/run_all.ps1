param(
    [string]$GodotExecutable = 'C:\Users\linus\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
)
# Godot writes benign shutdown diagnostics to stderr; evaluate its captured
# output and exit code below instead of letting PowerShell promote stderr.
$ErrorActionPreference = 'Continue'
$projectDirectory = Split-Path $PSScriptRoot
if (-not (Test-Path -LiteralPath $GodotExecutable)) { throw "Godot executable not found: $GodotExecutable" }
$importOutput = & $GodotExecutable --headless --path $projectDirectory --editor --import 2>&1 | Out-String
$importOutput | Set-Content (Join-Path $projectDirectory '.godot/10_import.log')
if ($LASTEXITCODE -ne 0 -or $importOutput -match '(?m)^(SCRIPT ERROR:|ERROR:)') {
    Write-Output $importOutput
    throw 'Godot import failed.'
}
Write-Output 'PASS import/parse'
foreach ($suite in @('planet_grid','planet_world','hydrology','world_ui','terrain','world_dressing','smoke','camera_navigation','music','frontend','frontend_navigation','content_foundation','world_interaction','world_population','living_migration','living_migration_ui','baumeister','baumeister_ui','strategic_ui','visibility','multiplayer','movement','hotseat','combat','combat_ui','economy','economy_ui','ai','resources','animation')) {
    # Watchdog prevents an aborted async test from hanging forever.
    # Exit code alone is insufficient: Godot can return 0 after a script error.
    $output = & $GodotExecutable --headless --path $projectDirectory --script "res://tests/$suite.gd" --quit-after 5000 2>&1 | Out-String
    $output | Set-Content (Join-Path $projectDirectory ".godot/10_$suite.log")
    $diagnostics = $output -replace '(?m)^WARNING: ObjectDB instances leaked at exit.*\r?\n?', '' `
                           -replace '(?m)^ERROR: \d+ resources still in use at exit.*\r?\n?', ''
    if ($LASTEXITCODE -ne 0 -or $diagnostics -match '(?m)^(SCRIPT ERROR:|ERROR:)' -or $output -notmatch 'checks complete.*failures=0|checks:.*failures=0') {
        Write-Output $output
        throw "Suite failed or did not finish: $suite"
    }
    Write-Output ("PASS " + $suite)
}
& (Join-Path $PSScriptRoot 'network_integration.ps1') -GodotExecutable $GodotExecutable
