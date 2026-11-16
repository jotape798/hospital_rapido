param(
    [string]$AndroidApiBaseUrl = 'http://10.0.2.2:8000',
    [string]$WebApiBaseUrl = 'http://127.0.0.1:8000',
    [switch]$Production,
    [switch]$Resume
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

$root = Split-Path -Parent $PSScriptRoot
$frontend = Join-Path $root 'frontend'
$dist = [IO.Path]::GetFullPath((Join-Path $root 'dist'))
$expectedDist = [IO.Path]::GetFullPath((Join-Path $root 'dist'))
if (-not $dist.Equals($expectedDist, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Destino de distribuição inválido.'
}

function Validar-UrlApi {
    param([string]$Nome, [string]$Valor, [bool]$ExigirHttps)
    $uri = $null
    if (-not [Uri]::TryCreate($Valor, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http', 'https') -or -not $uri.Host) {
        throw "$Nome deve ser uma URL HTTP ou HTTPS completa."
    }
    if ($ExigirHttps -and $uri.Scheme -ne 'https') {
        throw "$Nome deve usar HTTPS no build de produção."
    }
}

Validar-UrlApi 'AndroidApiBaseUrl' $AndroidApiBaseUrl $Production.IsPresent
Validar-UrlApi 'WebApiBaseUrl' $WebApiBaseUrl $Production.IsPresent
if ($AndroidApiBaseUrl -match '127\.0\.0\.1|localhost') {
    throw 'AndroidApiBaseUrl não pode apontar para 127.0.0.1 ou localhost.'
}

foreach ($comando in @('flutter', 'powershell.exe')) {
    if (-not (Get-Command $comando -ErrorAction SilentlyContinue)) {
        throw "Comando obrigatório não encontrado: $comando"
    }
}
$python = Join-Path $root 'backend\venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) { throw 'Ambiente Python do backend não encontrado.' }
& $python -m PyInstaller --version | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Instale backend/requirements-build.txt antes de empacotar.' }

$pubspec = Get-Content -LiteralPath (Join-Path $frontend 'pubspec.yaml') -Raw -Encoding UTF8
if ($pubspec -notmatch '(?m)^version:\s*(?<version>\d+\.\d+\.\d+)\+\d+\s*$') {
    throw 'Versão semântica não encontrada em frontend/pubspec.yaml.'
}
$version = $Matches['version']
$environment = if ($Production) { 'production' } else { 'development' }

if (Test-Path -LiteralPath $dist) {
    Remove-Item -LiteralPath $dist -Recurse -Force
}
New-Item -ItemType Directory -Path $dist -Force | Out-Null

& $python (Join-Path $root 'scripts\generate_brand_assets.py')
if ($LASTEXITCODE -ne 0) { throw 'Falha ao gerar os ativos da marca.' }

$keyProperties = Join-Path $frontend 'android\key.properties'
$keyStore = Join-Path $frontend 'android\app\ubs-rapida-release.jks'
if (-not (Test-Path -LiteralPath $keyProperties) -or -not (Test-Path -LiteralPath $keyStore)) {
    $keytool = Join-Path $env:ProgramFiles 'Android\Android Studio\jbr\bin\keytool.exe'
    if (-not (Test-Path -LiteralPath $keytool)) { throw 'keytool do Android Studio não encontrado.' }
    $random = New-Object byte[] 24
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($random) } finally { $rng.Dispose() }
    $password = -join ($random | ForEach-Object { $_.ToString('x2') })
    & $keytool -genkeypair -v -keystore $keyStore -storepass $password -keypass $password `
        -alias ubsrapida -keyalg RSA -keysize 3072 -validity 10000 `
        -dname 'CN=UBS Rapida Academica, OU=Aplicativo, O=UBS Rapida, L=Local, ST=Local, C=BR'
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar a chave Android local.' }
    $properties = "storePassword=$password`nkeyPassword=$password`nkeyAlias=ubsrapida`nstoreFile=ubs-rapida-release.jks`n"
    [IO.File]::WriteAllText($keyProperties, $properties, $utf8)
    $password = $null
}

Push-Location $frontend
try {
    if (-not $Resume) {
        flutter clean
        if ($LASTEXITCODE -ne 0) { throw 'flutter clean falhou.' }
    }
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get falhou.' }
    if (-not $Resume -or -not (Test-Path -LiteralPath 'build\windows\x64\runner\Release\UBS_Rapida.exe')) {
        flutter build windows --release --dart-define=API_BASE_URL=http://127.0.0.1:8000 --dart-define=APP_ENV=desktop
        if ($LASTEXITCODE -ne 0) { throw 'Build Windows falhou.' }
    }
    flutter build apk --release --dart-define="API_BASE_URL=$AndroidApiBaseUrl" --dart-define="APP_ENV=$environment"
    if ($LASTEXITCODE -ne 0) { throw 'Build APK falhou.' }
    flutter build appbundle --release --dart-define="API_BASE_URL=$AndroidApiBaseUrl" --dart-define="APP_ENV=$environment"
    if ($LASTEXITCODE -ne 0) { throw 'Build AAB falhou.' }
    flutter build web --release --pwa-strategy=none --base-href=/web/ `
        --dart-define="API_BASE_URL=$WebApiBaseUrl" --dart-define="APP_ENV=$environment"
    if ($LASTEXITCODE -ne 0) { throw 'Build Web falhou.' }
} finally { Pop-Location }

$pyBuild = Join-Path $root 'build\distribution-python'
$pyDist = Join-Path $pyBuild 'dist'
$pyWork = Join-Path $pyBuild 'work'
$pySpec = Join-Path $pyBuild 'spec'
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

$windowsDir = Join-Path $dist 'windows'
$windowsPackage = Join-Path $windowsDir 'UBS_Rapida'
New-Item -ItemType Directory -Path (Join-Path $windowsPackage 'app'),(Join-Path $windowsPackage 'backend') -Force | Out-Null
Copy-Item -Path (Join-Path $frontend 'build\windows\x64\runner\Release\*') -Destination (Join-Path $windowsPackage 'app') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $pyDist 'UBS_Rapida_Backend') -Destination (Join-Path $windowsPackage 'backend') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $pyDist 'Configurar_Administrador') -Destination (Join-Path $windowsPackage 'backend') -Recurse -Force
Copy-Item -Path (Join-Path $root 'packaging\windows\*') -Destination $windowsPackage -Recurse -Force
[IO.File]::WriteAllText((Join-Path $windowsPackage 'VERSION.txt'), "UBS Rápida $version`n", $utf8)
$windowsZip = Join-Path $windowsDir "UBS_Rapida-Windows-$version.zip"
Compress-Archive -Path (Join-Path $windowsPackage '*') -DestinationPath $windowsZip -CompressionLevel Optimal

$androidDir = Join-Path $dist 'android'
New-Item -ItemType Directory -Path $androidDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $frontend 'build\app\outputs\flutter-apk\app-release.apk') -Destination (Join-Path $androidDir "UBS_Rapida-Android-$version.apk")
Copy-Item -LiteralPath (Join-Path $frontend 'build\app\outputs\bundle\release\app-release.aab') -Destination (Join-Path $androidDir "UBS_Rapida-Android-$version.aab")

Copy-Item -LiteralPath (Join-Path $frontend 'build\web') -Destination (Join-Path $dist 'web') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'packaging\downloads') -Destination (Join-Path $dist 'downloads') -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root 'docs\09_distribuicao\INSTALACAO.md') -Destination (Join-Path $dist 'downloads\INSTALACAO.md') -Force

$checksums = Join-Path $dist 'checksums'
New-Item -ItemType Directory -Path $checksums -Force | Out-Null
$artifacts = @(
    $windowsZip,
    (Join-Path $androidDir "UBS_Rapida-Android-$version.apk"),
    (Join-Path $androidDir "UBS_Rapida-Android-$version.aab")
)
$hashLines = foreach ($artifact in $artifacts) {
    $hash = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $([IO.Path]::GetFileName($artifact))"
}
[IO.File]::WriteAllLines((Join-Path $checksums 'SHA256SUMS.txt'), $hashLines, $utf8)

& (Join-Path $root 'scripts\audit_distribution.ps1') -DistributionPath $dist
if ($LASTEXITCODE -ne 0) { throw 'Auditoria final da distribuição falhou.' }

Write-Host "Distribuição UBS Rápida $version concluída em $dist" -ForegroundColor Green
