param(
    [string]$ZipPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist\windows\UBS_Rapida-Windows-0.1.0.zip')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tempBase = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
$testRoot = [IO.Path]::GetFullPath((Join-Path $tempBase ('ubs-rapida-package-' + [guid]::NewGuid().ToString('N'))))
if (-not $testRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Pasta externa de teste inválida.'
}

$packageDir = Join-Path $testRoot 'package'
$localData = Join-Path $testRoot 'localappdata'
$backend = $null
$launcher = $null
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $packageDir
    $env:LOCALAPPDATA = $localData
    $dataDir = Join-Path $localData 'UBSRapida\dados'
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    $db = Join-Path $dataDir 'ubs_rapida.db'
    $env:DATABASE_URL = 'sqlite:///' + ($db -replace '\\', '/')
    $random = New-Object byte[] 48
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
    $env:JWT_SECRET_KEY = [Convert]::ToBase64String($random)
    $env:SEED_DEMO_DATA = 'false'
    $env:SEED_FUTURE_SCHEDULE = 'false'
    $env:UBS_DISTRIBUTION_NO_DEMO_MODULES = 'true'
    $env:UBS_BACKEND_PORT = '8000'

    $backendExe = Join-Path $packageDir 'backend\UBS_Rapida_Backend\UBS_Rapida_Backend.exe'
    $backend = Start-Process -FilePath $backendExe -WorkingDirectory (Split-Path $backendExe) `
        -RedirectStandardOutput (Join-Path $testRoot 'backend.out') `
        -RedirectStandardError (Join-Path $testRoot 'backend.err') `
        -WindowStyle Hidden -PassThru
    $ready = $false
    foreach ($attempt in 1..90) {
        if ($backend.HasExited) { break }
        try {
            $health = Invoke-RestMethod 'http://127.0.0.1:8000/health' -TimeoutSec 1
            if ($health.status -eq 'ok') { $ready = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) {
        $detail = Get-Content (Join-Path $testRoot 'backend.err') -Raw -ErrorAction SilentlyContinue
        throw "Backend empacotado falhou: $detail"
    }
    $docs = Invoke-WebRequest -UseBasicParsing 'http://127.0.0.1:8000/docs' -TimeoutSec 3
    Write-Output "PACKAGED_BACKEND=PASS HEALTH=$($health.status) DOCS=$($docs.StatusCode) DB_BYTES=$((Get-Item $db).Length)"
    Stop-Process -Id $backend.Id -Force
    $backend.WaitForExit()

    $frontendExe = Join-Path $packageDir 'app\UBS_Rapida.exe'
    $frontend = Start-Process -FilePath $frontendExe -WorkingDirectory (Split-Path $frontendExe) -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 4
    $frontend.Refresh()
    if ($frontend.HasExited) { throw "Frontend empacotado encerrou com código $($frontend.ExitCode)." }
    Write-Output "PACKAGED_FRONTEND=PASS PID=$($frontend.Id)"
    Stop-Process -Id $frontend.Id -Force
    $frontend.WaitForExit()

    $launcherOut = Join-Path $testRoot 'launcher.out'
    $launcherErr = Join-Path $testRoot 'launcher.err'
    $launcher = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $packageDir 'iniciar_ubs_rapida.ps1')
    ) -WorkingDirectory $packageDir -RedirectStandardOutput $launcherOut `
        -RedirectStandardError $launcherErr -WindowStyle Hidden -PassThru
    $launcherReady = $false
    foreach ($attempt in 1..90) {
        if ($launcher.HasExited) { break }
        try {
            $health = Invoke-RestMethod 'http://127.0.0.1:8000/health' -TimeoutSec 1
            if ($health.status -eq 'ok') { $launcherReady = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    if (-not $launcherReady) {
        $detail = Get-Content $launcherErr -Raw -ErrorAction SilentlyContinue
        throw "Launcher externo não iniciou a API: $detail"
    }
    $apps = @()
    foreach ($attempt in 1..30) {
        $apps = @(Get-Process -Name 'UBS_Rapida' -ErrorAction SilentlyContinue | Where-Object {
            $_.Path -and $_.Path.StartsWith($packageDir, [StringComparison]::OrdinalIgnoreCase)
        })
        if ($apps.Count -gt 0) { break }
        if ($launcher.HasExited) { break }
        Start-Sleep -Milliseconds 500
    }
    if ($apps.Count -lt 1) { throw 'Launcher não abriu o frontend externo.' }
    Write-Output "PACKAGED_LAUNCHER=PASS FRONTENDS=$($apps.Count) EXTERNAL=$(-not $packageDir.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase))"
    $apps | Stop-Process -Force
    if (-not $launcher.WaitForExit(15000)) { Stop-Process -Id $launcher.Id -Force }
    Start-Sleep -Milliseconds 500
    $stillListening = $false
    try { $null = Invoke-RestMethod 'http://127.0.0.1:8000/health' -TimeoutSec 1; $stillListening = $true } catch { }
    $launcherText = (Get-Content $launcherOut -Raw -ErrorAction SilentlyContinue) +
        (Get-Content $launcherErr -Raw -ErrorAction SilentlyContinue)
    Write-Output "BACKEND_STOPPED=$(-not $stillListening) PROJECT_PATH_DEPENDENCY=$($launcherText -match [regex]::Escape($projectRoot))"
} finally {
    foreach ($process in @($backend, $launcher)) {
        if ($process -and -not $process.HasExited) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }
    Get-Process -Name 'UBS_Rapida', 'UBS_Rapida_Backend' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($testRoot, [StringComparison]::OrdinalIgnoreCase) } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    $env:JWT_SECRET_KEY = $null
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
    Write-Output "EXTERNAL_TEST_CLEANED=$(-not (Test-Path -LiteralPath $testRoot))"
}
