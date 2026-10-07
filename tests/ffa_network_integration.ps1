param(
    [string]$GodotExecutable = 'C:\Users\linus\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot
$port = 31000 + (Get-Random -Maximum 1500)
$roles = @('host','client2','client3','client4')
$processes = @()
$resultPaths = @()
$logPaths = @()
foreach ($role in $roles) {
    $resultPath = Join-Path $projectDirectory ".godot/m19_$($role)_result.json"
    $logPath = Join-Path $projectDirectory ".godot/m19_$($role).log"
    Remove-Item -LiteralPath $resultPath,$logPath,($logPath + '.err') -Force -ErrorAction SilentlyContinue
    $resultPaths += $resultPath; $logPaths += $logPath
}
for ($index = 0; $index -lt $roles.Count; $index++) {
    $args = @('--headless','--path',$projectDirectory,'--script','res://tests/ffa_network_peer.gd','--',"--role=$($roles[$index])", "--port=$port", "--result=$($resultPaths[$index])")
    $processes += Start-Process -FilePath $GodotExecutable -ArgumentList $args -RedirectStandardOutput $logPaths[$index] -RedirectStandardError ($logPaths[$index] + '.err') -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 450
}
$deadline = [DateTime]::UtcNow.AddSeconds(50)
while (($processes | Where-Object { -not $_.HasExited }).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 200
    foreach ($process in $processes) { $process.Refresh() }
}
foreach ($process in $processes) {
    if (-not $process.HasExited) { $process.Kill() }
    $process.WaitForExit()
}
$missing = @($resultPaths | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($missing.Count -gt 0) {
    foreach ($path in $logPaths) { Get-Content -LiteralPath $path,($path + '.err') -ErrorAction SilentlyContinue }
    throw 'Four-process FFA integration did not produce every result.'
}
$results = @($resultPaths | ForEach-Object { Get-Content -LiteralPath $_ -Raw | ConvertFrom-Json })
$diagnostics = (($logPaths | ForEach-Object { Get-Content -LiteralPath $_,($_ + '.err') -ErrorAction SilentlyContinue }) | Out-String)
if (($results | Where-Object { -not $_.ok }).Count -gt 0 -or $diagnostics -match '(?m)^(SCRIPT ERROR:|ERROR:)(?! \d+ resources still in use)') {
    foreach ($path in $logPaths) { Get-Content -LiteralPath $path,($path + '.err') -ErrorAction SilentlyContinue }
    throw ('Four-process FFA integration failed: ' + (($results | ForEach-Object { "$($_.role)=$($_.message)" }) -join '; '))
}
Write-Output ('PASS ffa_network_integration (' + (($results | ForEach-Object { "$($_.role): P$($_.player_id)" }) -join ', ') + ')')
