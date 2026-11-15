param([switch]$ConfigurarAdministrador)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8

$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
$dados = Join-Path $env:LOCALAPPDATA 'UBSRapida'
$banco = Join-Path $dados 'dados\ubs_rapida.db'
$segredoProtegido = Join-Path $dados 'config\jwt-secret.bin'
$pastaLogs = Join-Path $dados 'logs'
$backendExe = Join-Path $raiz 'backend\UBS_Rapida_Backend\UBS_Rapida_Backend.exe'
$adminExe = Join-Path $raiz 'backend\Configurar_Administrador\Configurar_Administrador.exe'
$frontendExe = Join-Path $raiz 'app\UBS_Rapida.exe'

function Obter-SegredoLocal {
    $pasta = Split-Path -Parent $segredoProtegido
    New-Item -ItemType Directory -Path $pasta -Force | Out-Null
    Add-Type -AssemblyName System.Security
    if (-not (Test-Path -LiteralPath $segredoProtegido)) {
        $bytes = New-Object byte[] 48
        $gerador = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        try { $gerador.GetBytes($bytes) } finally { $gerador.Dispose() }
        $texto = [Convert]::ToBase64String($bytes)
        $protegido = [System.Security.Cryptography.ProtectedData]::Protect(
            [Text.Encoding]::UTF8.GetBytes($texto),
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        [IO.File]::WriteAllBytes($segredoProtegido, $protegido)
    }
    $conteudo = [IO.File]::ReadAllBytes($segredoProtegido)
    $aberto = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $conteudo,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    return [Text.Encoding]::UTF8.GetString($aberto)
}

function Preparar-Ambiente {
    New-Item -ItemType Directory -Path (Split-Path -Parent $banco),$pastaLogs -Force | Out-Null
    $env:DATABASE_URL = 'sqlite:///' + ($banco -replace '\\', '/')
    $env:JWT_SECRET_KEY = Obter-SegredoLocal
    $env:SEED_DEMO_DATA = 'false'
    $env:SEED_FUTURE_SCHEDULE = 'false'
    $env:UBS_DISTRIBUTION_NO_DEMO_MODULES = 'true'
    $env:UBS_BACKEND_HOST = '127.0.0.1'
    $env:UBS_BACKEND_PORT = '8000'
    $env:APP_ENV = 'desktop'
    $env:ALLOWED_ORIGINS = 'http://localhost:8080,http://127.0.0.1:8080'
}

function Executar-ConfiguracaoAdministrador {
    if (-not (Test-Path -LiteralPath $adminExe)) {
        throw "O configurador do administrador não foi encontrado em $adminExe"
    }
    Write-Host ''
    Write-Host 'Configuração segura do primeiro administrador' -ForegroundColor Cyan
    Write-Host 'A senha digitada não será exibida nem gravada em texto.'
    & $adminExe
    if ($LASTEXITCODE -ne 0) {
        throw 'A configuração do administrador não foi concluída.'
    }
}

Preparar-Ambiente

if ($ConfigurarAdministrador) {
    Executar-ConfiguracaoAdministrador
    exit 0
}

if (-not (Test-Path -LiteralPath $backendExe)) {
    throw "O backend da UBS Rápida não foi encontrado em $backendExe"
}
if (-not (Test-Path -LiteralPath $frontendExe)) {
    throw "O aplicativo UBS Rápida não foi encontrado em $frontendExe"
}
if (-not (Test-Path -LiteralPath $banco)) {
    Write-Host 'Primeiro uso: crie o administrador desta instalação.' -ForegroundColor Yellow
    Executar-ConfiguracaoAdministrador
}

$portaOcupada = $false
$listener = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 8000)
try { $listener.Start() } catch { $portaOcupada = $true } finally { try { $listener.Stop() } catch { } }
if ($portaOcupada) {
    throw 'A porta local 8000 já está em uso. Feche a outra aplicação e tente novamente.'
}

$saidaBackend = Join-Path $pastaLogs 'backend.stdout.log'
$erroBackend = Join-Path $pastaLogs 'backend.stderr.log'
$backend = $null
try {
    Write-Host 'Iniciando a API local da UBS Rápida...' -ForegroundColor Cyan
    $backend = Start-Process -FilePath $backendExe -WorkingDirectory (Split-Path $backendExe) `
        -RedirectStandardOutput $saidaBackend -RedirectStandardError $erroBackend `
        -WindowStyle Hidden -PassThru

    $pronto = $false
    foreach ($tentativa in 1..60) {
        if ($backend.HasExited) { break }
        try {
            $resposta = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 1
            if ($resposta.status -eq 'ok') { $pronto = $true; break }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    if (-not $pronto) {
        $detalhe = if (Test-Path -LiteralPath $erroBackend) {
            (Get-Content -LiteralPath $erroBackend -Tail 12 -Encoding UTF8) -join [Environment]::NewLine
        } else { 'Nenhum detalhe adicional foi registrado.' }
        throw "A API local não iniciou no tempo esperado.`n$detalhe"
    }

    Write-Host 'API pronta. Abrindo o aplicativo...' -ForegroundColor Green
    $frontend = Start-Process -FilePath $frontendExe -WorkingDirectory (Split-Path $frontendExe) -PassThru
    $frontend.WaitForExit()
} finally {
    if ($backend -and -not $backend.HasExited) {
        Stop-Process -Id $backend.Id -Force -ErrorAction SilentlyContinue
        try { $null = $backend.WaitForExit(5000) } catch { }
    }
    $env:JWT_SECRET_KEY = $null
}
