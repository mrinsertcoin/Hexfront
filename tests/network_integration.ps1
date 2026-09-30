param(
    [string]$GodotExecutable = 'C:\Users\linus\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path $PSScriptRoot
$port = 29000 + (Get-Random -Maximum 2000)
$hostResult = Join-Path $projectDirectory '.godot/m18_host_result.json'
$clientResult = Join-Path $projectDirectory '.godot/m18_client_result.json'
$hostLog = Join-Path $projectDirectory '.godot/m18_host.log'
$clientLog = Join-Path $projectDirectory '.godot/m18_client.log'
Remove-Item -LiteralPath $hostResult,$clientResult,$hostLog,$clientLog -Force -ErrorAction SilentlyContinue
$hostArgs = @('--headless','--path',$projectDirectory,'--script','res://tests/network_peer.gd','--','--role=host',"--port=$port","--result=$hostResult")
$clientArgs = @('--headless','--path',$projectDirectory,'--script','res://tests/network_peer.gd','--','--role=client',"--port=$port","--result=$clientResult")
$serverProcess = Start-Process -FilePath $GodotExecutable -ArgumentList $hostArgs -RedirectStandardOutput $hostLog -RedirectStandardError ($hostLog + '.err') -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 700
$clientProcess = Start-Process -FilePath $GodotExecutable -ArgumentList $clientArgs -RedirectStandardOutput $clientLog -RedirectStandardError ($clientLog + '.err') -PassThru -WindowStyle Hidden
$deadline = [DateTime]::UtcNow.AddSeconds(35)
while ((-not $serverProcess.HasExited -or -not $clientProcess.HasExited) -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 200
    $serverProcess.Refresh(); $clientProcess.Refresh()
}
if (-not $serverProcess.HasExited) { $serverProcess.Kill() }
if (-not $clientProcess.HasExited) { $clientProcess.Kill() }
$serverProcess.WaitForExit(); $clientProcess.WaitForExit()
if (-not (Test-Path -LiteralPath $hostResult) -or -not (Test-Path -LiteralPath $clientResult)) {
    Get-Content -LiteralPath $hostLog,$clientLog,($hostLog + '.err'),($clientLog + '.err') -ErrorAction SilentlyContinue
    throw 'Two-process network integration did not produce both results.'
}
$hostData = Get-Content -LiteralPath $hostResult -Raw | ConvertFrom-Json
$clientData = Get-Content -LiteralPath $clientResult -Raw | ConvertFrom-Json
$combinedDiagnostics = (Get-Content -LiteralPath $hostLog,$clientLog,($hostLog + '.err'),($clientLog + '.err') -ErrorAction SilentlyContinue | Out-String)
if (-not $hostData.ok -or -not $clientData.ok -or $combinedDiagnostics -match '(?m)^(SCRIPT ERROR:|ERROR:)(?! \d+ resources still in use)') {
    Get-Content -LiteralPath $hostLog,$clientLog,($hostLog + '.err'),($clientLog + '.err') -ErrorAction SilentlyContinue
    throw "Two-process network integration failed: host=$($hostData.message), client=$($clientData.message)"
}
Write-Output "PASS network_integration ($($hostData.message); $($clientData.message))"
