param(
    [switch]$SkipFlutterBuild
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$frontend = Join-Path $root 'frontend'
$python = Join-Path $root 'backend\venv\Scripts\python.exe'
$buildRoot = Join-Path $root 'build\distribution-windows'
$pyDist = Join-Path $buildRoot 'dist'
$pyWork = Join-Path $buildRoot 'work'
$pySpec = Join-Path $buildRoot 'spec'
$windowsDir = Join-Path $root 'dist\windows'
$windowsPackage = Join-Path $windowsDir 'UBS_Rapida'

function Assert-ProjectChild {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolved = [IO.Path]::GetFullPath($Path)
    $prefix = $root.TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Caminho fora do projeto recusado: $resolved"
    }
    return $resolved
}

function Remove-GeneratedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $safePath = Assert-ProjectChild $Path
    if (Test-Path -LiteralPath $safePath) {
        Remove-Item -LiteralPath $safePath -Recurse -Force
    }
}

if (-not (Test-Path -LiteralPath $python)) {
    throw 'Ambiente backend/venv não encontrado. Prepare o ambiente antes de empacotar.'
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter não encontrado no PATH.'
}
& $python -c 'import PyInstaller' *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'PyInstaller não está instalado no ambiente backend/venv.'
}

$pubspec = Get-Content -LiteralPath (Join-Path $frontend 'pubspec.yaml') -Encoding UTF8
$versionMatch = $pubspec | Select-String -Pattern '^version:\s*(\d+\.\d+\.\d+)'
if (-not $versionMatch) { throw 'Versão não encontrada em frontend/pubspec.yaml.' }
$version = $versionMatch.Matches[0].Groups[1].Value

if (-not $SkipFlutterBuild) {
    Push-Location $frontend
    try {
        flutter pub get
        if ($LASTEXITCODE -ne 0) { throw 'flutter pub get falhou.' }
        flutter build windows --release `
            --dart-define=API_BASE_URL=http://127.0.0.1:8000 `
            --dart-define=APP_ENV=desktop
        if ($LASTEXITCODE -ne 0) { throw 'Build Windows Release falhou.' }
    } finally {
        Pop-Location
    }
}

$releaseDir = Join-Path $frontend 'build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath (Join-Path $releaseDir 'UBS_Rapida.exe'))) {
    throw 'Executável Windows Release não encontrado.'
}

Remove-GeneratedPath $buildRoot
New-Item -ItemType Directory -Path $pyDist,$pyWork,$pySpec -Force | Out-Null
$excludes = @(
    '--exclude-module', 'app.core.demo_accounts',
    '--exclude-module', 'app.services.demo_seed',
    '--exclude-module', 'app.core.extended_demo_staff',
    '--exclude-module', 'app.services.extended_demo_seed',
    '--exclude-module', 'pytest'
)

& $python -m PyInstaller --noconfirm --clean --onedir --noupx `
    --name UBS_Rapida_Backend --paths (Join-Path $root 'backend') `
    --hidden-import app.main --collect-all email_validator --collect-all tzdata `
    --distpath $pyDist --workpath (Join-Path $pyWork 'backend') --specpath $pySpec `
    @excludes (Join-Path $root 'backend\distribution_entry.py')
if ($LASTEXITCODE -ne 0) { throw 'Empacotamento do backend falhou.' }

& $python -m PyInstaller --noconfirm --clean --onedir --noupx `
    --name Configurar_Administrador --paths (Join-Path $root 'backend') `
    --hidden-import app.main --collect-all email_validator --collect-all tzdata `
    --distpath $pyDist --workpath (Join-Path $pyWork 'admin') --specpath $pySpec `
    @excludes (Join-Path $root 'backend\criar_admin_inicial.py')
if ($LASTEXITCODE -ne 0) { throw 'Empacotamento do configurador falhou.' }

Remove-GeneratedPath $windowsPackage
New-Item -ItemType Directory -Path `
    (Join-Path $windowsPackage 'app'),(Join-Path $windowsPackage 'backend') `
    -Force | Out-Null
Copy-Item -Path (Join-Path $releaseDir '*') `
    -Destination (Join-Path $windowsPackage 'app') -Recurse
Copy-Item -LiteralPath (Join-Path $pyDist 'UBS_Rapida_Backend') `
    -Destination (Join-Path $windowsPackage 'backend') -Recurse
Copy-Item -LiteralPath (Join-Path $pyDist 'Configurar_Administrador') `
    -Destination (Join-Path $windowsPackage 'backend') -Recurse
Copy-Item -Path (Join-Path $root 'packaging\windows\*') `
    -Destination $windowsPackage -Recurse
[IO.File]::WriteAllText(
    (Join-Path $windowsPackage 'VERSION.txt'),
    "UBS Rápida $version`n",
    $utf8
)

$prohibited = @(
    Get-ChildItem -LiteralPath $windowsPackage -Recurse -Force |
        Where-Object {
            $_.Name -match '^(\.env|ubs_rapida\.db)$' -or
            $_.Extension -in @('.db', '.sqlite', '.sqlite3', '.bak', '.log', '.pyc') -or
            ($_.PSIsContainer -and $_.Name -in @('venv', '.venv', '__pycache__', 'tests'))
        }
)
if ($prohibited.Count -gt 0) {
    throw "O pacote contém $($prohibited.Count) arquivo(s) ou pasta(s) proibido(s)."
}

$windowsZip = Join-Path $windowsDir "UBS_Rapida-Windows-$version.zip"
Remove-GeneratedPath $windowsZip
Compress-Archive -Path (Join-Path $windowsPackage '*') `
    -DestinationPath $windowsZip -CompressionLevel Optimal
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $windowsZip).Hash

Write-Output 'WINDOWS_DISTRIBUTION=PASS'
Write-Output "ZIP=$windowsZip"
Write-Output "SHA256=$hash"
