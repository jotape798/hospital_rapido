param(
    [ValidateSet('windows', 'chrome', 'edge')]
    [string]$Dispositivo = 'windows',
    [switch]$AtualizarTudo,
    [switch]$Validar,
    [switch]$SemPausa,

    # Opcoes internas, usadas somente pelos testes automatizados do iniciador.
    [switch]$ModoTesteInterno,
    [string]$FlutterTesteInterno,
    [string]$BackendTesteInterno,
    [string]$NavegadorTesteInterno,
    [ValidateRange(1, 600)]
    [int]$TimeoutInicializacaoSegundos = 120,
    [ValidateRange(1, 300)]
    [int]$TimeoutBackendSegundos = 30,
    [ValidateRange(0, 30)]
    [int]$EstabilidadeFrontendSegundos = 3,
    [switch]$EncerrarAposValidacaoInterna,
    [ValidateRange(1, 65535)]
    [int]$PortaBackendTesteInterno = 8000,
    [ValidateRange(1, 65535)]
    [int]$PortaFrontendTesteInterno = 8080,

    # Opcoes internas para testar a descoberta do Python sem alterar PATH global.
    [switch]$ModoTestePythonInterno,
    [string]$PastaAmbienteTesteInterno,
    [string]$PythonSistemaTesteInterno,
    [string]$PySistemaTesteInterno,
    [switch]$SomentePrepararPythonTesteInterno,
    [switch]$PularDependenciasPythonTesteInterno,
    [switch]$SimularFalhaInstalacaoTesteInterno
)

$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [Console]::OutputEncoding

$pastaProjeto = Split-Path -Parent $PSScriptRoot
$pastaBackend = Join-Path $pastaProjeto 'backend'
$pastaFrontend = Join-Path $pastaProjeto 'frontend'
$pastaLogs = Join-Path $pastaProjeto 'logs\inicializacao'
$arquivoBackend = Join-Path $pastaBackend 'app\main.py'
$arquivoFlutter = Join-Path $pastaFrontend 'pubspec.yaml'
$scriptDemonstracao = Join-Path $pastaBackend 'seed_demonstracao.py'
$executavelWindows = Join-Path $pastaFrontend 'build\windows\x64\runner\Release\ubs_saude.exe'
$marcaBuildWindows = Join-Path (Split-Path $executavelWindows) '.ubs_build_stamp'
$pastaAmbiente = if ($ModoTestePythonInterno -and $PastaAmbienteTesteInterno) {
    [System.IO.Path]::GetFullPath($PastaAmbienteTesteInterno)
} else {
    Join-Path $pastaBackend 'venv'
}
$pythonPrincipal = Join-Path $pastaAmbiente 'Scripts\python.exe'
$requirements = Join-Path $pastaBackend 'requirements.txt'
$marcaRequirements = Join-Path $pastaAmbiente '.ubs_requirements_stamp'
$setupEnv = Join-Path $pastaBackend 'setup_env.py'
$script:processosCriados = @()
$script:arquivosLogAtivos = @()
$script:inicializacaoConcluida = $false
$script:idInicializacao = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmssfff'), $PID
$portaBackend = if ($ModoTesteInterno) { $PortaBackendTesteInterno } else { 8000 }
$portaFrontend = if ($ModoTesteInterno) { $PortaFrontendTesteInterno } else { 8080 }
$urlBackend = "http://127.0.0.1:$portaBackend"
$urlFrontend = "http://127.0.0.1:$portaFrontend"
$sufixoLogTeste = if ($ModoTesteInterno) { "-teste-$portaBackend-$portaFrontend" } else { '' }

function Escrever-Ok {
    param([string]$Mensagem)
    Write-Host "[OK] $Mensagem" -ForegroundColor Green
}

function Escrever-Aguarde {
    param([string]$Mensagem)
    Write-Host "[AGUARDE] $Mensagem" -ForegroundColor Cyan
}

function Escrever-Erro {
    param([string]$Mensagem)
    Write-Host "[ERRO] $Mensagem" -ForegroundColor Red
}

function Obter-Flutter {
    if ($ModoTesteInterno -and $FlutterTesteInterno) {
        return (Resolve-Path -LiteralPath $FlutterTesteInterno).Path
    }
    $candidatos = @()
    $comando = Get-Command flutter -ErrorAction SilentlyContinue
    if ($comando) { $candidatos += $comando.Source }
    if ($env:FLUTTER_ROOT) {
        $candidatos += (Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat')
    }
    $candidatos += @(
        'C:\src\flutter_windows_3.44.6-stable\flutter\bin\flutter.bat',
        'C:\src\flutter\bin\flutter.bat',
        'C:\flutter\bin\flutter.bat'
    )
    foreach ($candidato in ($candidatos | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidato) { return $candidato }
    }
    return $null
}

function Nova-EspecificacaoPython {
    param(
        [Parameter(Mandatory = $true)][string]$Executavel,
        [string[]]$ArgumentosFixos = @(),
        [Parameter(Mandatory = $true)][string]$Nome
    )
    return [pscustomobject]@{
        Executavel = $Executavel
        ArgumentosFixos = @($ArgumentosFixos)
        Nome = $Nome
        Versao = $null
    }
}

function Testar-PythonFuncional {
    param([Parameter(Mandatory = $true)]$Candidato)
    if (-not $Candidato.Executavel -or -not (Test-Path -LiteralPath $Candidato.Executavel)) {
        return $null
    }
    if ([string]$Candidato.Executavel -match '\\Microsoft\\WindowsApps\\python(?:3)?\.exe$') {
        return $null
    }
    try {
        $argumentos = @($Candidato.ArgumentosFixos) + @('--version')
        $saida = (& $Candidato.Executavel @argumentos 2>&1 | Out-String).Trim()
        $codigo = $LASTEXITCODE
        $correspondencia = [regex]::Match($saida, '(?im)^Python\s+3\.(\d+)(?:\.(\d+))?')
        if ($codigo -ne 0 -or -not $correspondencia.Success) { return $null }
        $versaoSecundaria = [int]$correspondencia.Groups[1].Value
        if ($versaoSecundaria -lt 10) { return $null }
        $Candidato.Versao = ($correspondencia.Value -replace '\s+', ' ').Trim()
        return $Candidato
    } catch {
        return $null
    }
}

function Obter-ComandoAplicacao {
    param([Parameter(Mandatory = $true)][string]$Nome)
    $comando = Get-Command $Nome -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $comando) { return $null }
    if ($comando.Source) { return $comando.Source }
    return $comando.Path
}

function Selecionar-PythonSistema {
    $arquivoPython = if ($ModoTestePythonInterno) {
        $PythonSistemaTesteInterno
    } else {
        Obter-ComandoAplicacao 'python'
    }
    if ($arquivoPython) {
        $python = Testar-PythonFuncional (Nova-EspecificacaoPython `
            -Executavel $arquivoPython -Nome 'python')
        if ($python) {
            Escrever-Ok 'Python encontrado pelo comando: python'
            Escrever-Ok "Versão: $($python.Versao)"
            return $python
        }
    }

    Write-Host '[AVISO] O comando python não está disponível ou não funciona.' -ForegroundColor Yellow
    Escrever-Aguarde 'Tentando o inicializador py -3...'
    $arquivoPy = if ($ModoTestePythonInterno) {
        $PySistemaTesteInterno
    } else {
        Obter-ComandoAplicacao 'py'
    }
    if ($arquivoPy) {
        $py = Testar-PythonFuncional (Nova-EspecificacaoPython `
            -Executavel $arquivoPy -ArgumentosFixos @('-3') -Nome 'py -3')
        if ($py) {
            Escrever-Ok 'Python encontrado pelo comando: py -3'
            Escrever-Ok "Versão: $($py.Versao)"
            return $py
        }
    }

    throw ('Nenhuma instalação válida do Python 3 foi encontrada. ' +
        'Instale o Python 3 e habilite o Python Launcher ou adicione o Python ao PATH.')
}

function Obter-HashArquivo {
    param([Parameter(Mandatory = $true)][string]$Caminho)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::OpenRead($Caminho)
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($stream))).Replace('-', '')
    } finally {
        $stream.Dispose()
        $sha256.Dispose()
    }
}

function Obter-AssinaturaFrontend {
    $arquivos = @(
        Get-ChildItem -LiteralPath (Join-Path $pastaFrontend 'lib') -Recurse -File
        Get-ChildItem -LiteralPath (Join-Path $pastaFrontend 'assets') -Recurse -File -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath (Join-Path $pastaFrontend 'windows') -Recurse -File |
            Where-Object {
                $_.FullName -notmatch '\\flutter\\ephemeral\\' -and
                $_.Name -notmatch '^generated_plugin'
            }
        Get-Item -LiteralPath $arquivoFlutter
        Get-Item -LiteralPath (Join-Path $pastaFrontend 'pubspec.lock') -ErrorAction SilentlyContinue
    ) | Where-Object { $null -ne $_ } | Sort-Object FullName -Unique

    $manifesto = foreach ($arquivo in $arquivos) {
        $caminhoRelativo = $arquivo.FullName.Substring($pastaFrontend.Length).Replace('\', '/')
        '{0}:{1}' -f $caminhoRelativo, (Obter-HashArquivo $arquivo.FullName)
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($manifesto -join "`n"))
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '')
    } finally {
        $sha256.Dispose()
    }
}

function Testar-AplicativoAtualizado {
    if (-not (Test-Path -LiteralPath $executavelWindows) -or
        -not (Test-Path -LiteralPath $marcaBuildWindows)) { return $false }
    return (Get-Content -LiteralPath $marcaBuildWindows -Raw).Trim() -eq (Obter-AssinaturaFrontend)
}

function Testar-DependenciasBackendAtualizadas {
    if (-not (Test-Path -LiteralPath $marcaRequirements)) { return $false }
    return (Get-Content -LiteralPath $marcaRequirements -Raw).Trim() -eq (Obter-HashArquivo $requirements)
}

function Preparar-Logs {
    New-Item -ItemType Directory -Path $pastaLogs -Force | Out-Null
    Get-ChildItem -LiteralPath $pastaLogs -File -Filter '*.log' -ErrorAction SilentlyContinue |
        Where-Object LastWriteTime -lt (Get-Date).AddDays(-7) |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Obter-CaminhosLog {
    param([Parameter(Mandatory = $true)][string]$Nome)
    $saida = Join-Path $pastaLogs "$Nome.$($script:idInicializacao).stdout.log"
    $erro = Join-Path $pastaLogs "$Nome.$($script:idInicializacao).stderr.log"
    Set-Content -LiteralPath $saida -Value '' -Encoding UTF8
    Set-Content -LiteralPath $erro -Value '' -Encoding UTF8
    $script:arquivosLogAtivos += @($saida, $erro)
    return [pscustomobject]@{ Saida = $saida; Erro = $erro }
}

function Iniciar-ProcessoMonitorado {
    param(
        [Parameter(Mandatory = $true)][string]$Arquivo,
        [string[]]$Argumentos = @(),
        [Parameter(Mandatory = $true)][string]$Diretorio,
        [Parameter(Mandatory = $true)][string]$NomeLog,
        [switch]$JanelaNormal,
        [switch]$NaoRegistrar
    )
    $logs = Obter-CaminhosLog $NomeLog
    $arquivoProcesso = $Arquivo
    $argumentosProcesso = $Argumentos
    if ([System.IO.Path]::GetExtension($Arquivo) -ieq '.ps1') {
        $arquivoProcesso = 'powershell.exe'
        $argumentosProcesso = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Arquivo) + $Argumentos
    }
    $estilo = if ($JanelaNormal) { 'Normal' } else { 'Hidden' }
    $parametrosProcesso = @{
        FilePath = $arquivoProcesso
        WorkingDirectory = $Diretorio
        WindowStyle = $estilo
        PassThru = $true
        RedirectStandardOutput = $logs.Saida
        RedirectStandardError = $logs.Erro
    }
    if ($argumentosProcesso -and $argumentosProcesso.Count -gt 0) {
        $parametrosProcesso.ArgumentList = $argumentosProcesso
    }
    $processo = Start-Process @parametrosProcesso
    # No Windows PowerShell 5.1, abrir o handle antes de o processo terminar
    # preserva o ExitCode para comandos muito rápidos (como flutter pub get).
    $null = $processo.Handle
    if (-not $NaoRegistrar) { $script:processosCriados += $processo }
    return [pscustomobject]@{ Processo = $processo; Saida = $logs.Saida; Erro = $logs.Erro }
}

function Testar-ProcessoAtivo {
    param([System.Diagnostics.Process]$Processo)
    try {
        $Processo.Refresh()
        if ($Processo.HasExited) { return $false }
        return $null -ne (Get-Process -Id $Processo.Id -ErrorAction SilentlyContinue)
    } catch { return $false }
}

function Obter-CodigoSaida {
    param([System.Diagnostics.Process]$Processo)
    try {
        $Processo.Refresh()
        if ($Processo.HasExited) { return $Processo.ExitCode }
    } catch { }
    return $null
}

function Esperar-ProcessoECondicao {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Processo,
        [Parameter(Mandatory = $true)][scriptblock]$Condicao,
        [Parameter(Mandatory = $true)][int]$TimeoutSegundos,
        [int]$EstabilidadeSegundos = 0
    )
    $limite = (Get-Date).AddSeconds($TimeoutSegundos)
    $inicioEstavel = $null
    while ((Get-Date) -lt $limite) {
        if (-not (Testar-ProcessoAtivo $Processo)) { return 'Encerrado' }
        $condicaoAtendida = $false
        try { $condicaoAtendida = [bool](& $Condicao) } catch { $condicaoAtendida = $false }
        if ($condicaoAtendida) {
            if ($null -eq $inicioEstavel) { $inicioEstavel = Get-Date }
            if (((Get-Date) - $inicioEstavel).TotalSeconds -ge $EstabilidadeSegundos) {
                return 'Pronto'
            }
        } else {
            $inicioEstavel = $null
        }
        Start-Sleep -Milliseconds 250
    }
    return 'TempoEsgotado'
}

function Mostrar-LogsFalha {
    param([string[]]$Arquivos = $script:arquivosLogAtivos)
    Write-Host ''
    Write-Host 'Logs desta inicialização (últimas linhas):' -ForegroundColor Yellow
    foreach ($arquivo in ($Arquivos | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $arquivo)) { continue }
        Write-Host "--- $arquivo ---" -ForegroundColor DarkYellow
        Get-Content -LiteralPath $arquivo -Tail 20 -ErrorAction SilentlyContinue |
            Where-Object { $_ -ne '' } | ForEach-Object { Write-Host $_ }
    }
    Write-Host "[ERRO] Consulte os logs em: $pastaLogs" -ForegroundColor Red
}

function Obter-Descendentes {
    param([int]$IdPai)
    $filhos = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$IdPai" -ErrorAction SilentlyContinue)
    foreach ($filho in $filhos) {
        Obter-Descendentes -IdPai $filho.ProcessId
        $filho.ProcessId
    }
}

function Parar-ProcessoCriado {
    param([System.Diagnostics.Process]$Processo)
    if (-not $Processo) { return }
    $ids = @(Obter-Descendentes -IdPai $Processo.Id) + @($Processo.Id)
    $idsUnicos = @($ids | Select-Object -Unique)
    $processos = @(
        foreach ($idProcesso in $idsUnicos) {
            Get-Process -Id $idProcesso -ErrorAction SilentlyContinue
        }
    )
    foreach ($processoCriado in $processos) {
        Stop-Process -InputObject $processoCriado -Force -ErrorAction SilentlyContinue
    }
    foreach ($processoCriado in $processos) {
        try { $null = $processoCriado.WaitForExit(3000) } catch { }
    }
}

function Parar-ProcessosCriados {
    for ($indice = $script:processosCriados.Count - 1; $indice -ge 0; $indice--) {
        Parar-ProcessoCriado $script:processosCriados[$indice]
    }
}

function Testar-Api {
    try {
        $resposta = Invoke-RestMethod -Uri "$urlBackend/health" -TimeoutSec 2
        return $resposta.status -eq 'ok'
    } catch { return $false }
}

function Testar-FrontendWeb {
    try {
        $resposta = Invoke-WebRequest -UseBasicParsing -Uri $urlFrontend -TimeoutSec 2
        return $resposta.StatusCode -ge 200 -and $resposta.StatusCode -lt 400
    } catch { return $false }
}

function Testar-JanelaWindows {
    param([System.Diagnostics.Process]$Processo)
    try {
        $Processo.Refresh()
        return (-not $Processo.HasExited) -and $Processo.MainWindowHandle -ne [IntPtr]::Zero
    } catch { return $false }
}

function Testar-PortaLocalLivre {
    param([Parameter(Mandatory = $true)][int]$Porta)
    $listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Loopback, $Porta
    )
    try {
        $listener.Start()
        return $true
    } catch [System.Net.Sockets.SocketException] {
        return $false
    } finally {
        try { $listener.Stop() } catch { }
    }
}

function Verificar-PortaFrontendDisponivel {
    if (-not (Testar-PortaLocalLivre -Porta $portaFrontend)) {
        throw "A porta $portaFrontend do frontend está ocupada. Encerre o processo que usa essa porta e tente novamente."
    }
}

function Obter-ExecutavelNavegador {
    if ($ModoTesteInterno -and $NavegadorTesteInterno) {
        return (Resolve-Path -LiteralPath $NavegadorTesteInterno).Path
    }

    $nomeExecutavel = if ($Dispositivo -eq 'chrome') { 'chrome.exe' } else { 'msedge.exe' }
    $comando = Get-Command $nomeExecutavel -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($comando) { return $comando.Source }

    $candidatos = if ($Dispositivo -eq 'chrome') {
        @(
            (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
            (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
        )
    } else {
        @(
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
        )
    }
    foreach ($candidato in $candidatos) {
        if ($candidato -and (Test-Path -LiteralPath $candidato)) { return $candidato }
    }
    throw "O navegador $Dispositivo não foi encontrado. Instale-o ou use outro dispositivo."
}

function Abrir-FrontendNoNavegador {
    if ($ModoTesteInterno -and -not $NavegadorTesteInterno) {
        Escrever-Ok "Abertura do navegador $Dispositivo simulada no teste."
        return
    }
    $navegador = Obter-ExecutavelNavegador
    $parametros = @{
        FilePath = $navegador
        ArgumentList = @($urlFrontend)
        WorkingDirectory = $pastaFrontend
    }
    if ([System.IO.Path]::GetExtension($navegador) -ieq '.ps1') {
        $parametros.FilePath = 'powershell.exe'
        $parametros.ArgumentList = @(
            '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            $navegador, $urlFrontend
        )
        $parametros.WindowStyle = 'Hidden'
    }
    Start-Process @parametros | Out-Null
    Escrever-Ok "Navegador $Dispositivo aberto separadamente."
}

function Verificar-PortaBackendDisponivel {
    if (Testar-PortaLocalLivre -Porta $portaBackend) { return 'Livre' }
    if (Testar-Api) { return 'BackendSaudavel' }
    throw "A porta $portaBackend está ocupada por um processo que não responde como o backend da UBS Rápida."
}

function Preparar-AmbienteBackend {
    $especificacaoAmbiente = Nova-EspecificacaoPython `
        -Executavel $pythonPrincipal -Nome $pythonPrincipal
    $pythonAmbienteValido = Testar-PythonFuncional $especificacaoAmbiente
    if ($pythonAmbienteValido) {
        Escrever-Ok 'Ambiente virtual encontrado e validado.'
        Escrever-Ok "Usando: $pythonPrincipal"
    } else {
        $ambienteCorrompido = $null
        if (Test-Path -LiteralPath $pastaAmbiente) {
            $nomeBackup = 'venv_corrompido_{0}' -f (Get-Date -Format 'yyyyMMdd_HHmmssfff')
            $ambienteCorrompido = Join-Path (Split-Path $pastaAmbiente -Parent) $nomeBackup
            Write-Host '[AVISO] O ambiente virtual existente não está funcional e será recriado com segurança.' -ForegroundColor Yellow
            Move-Item -LiteralPath $pastaAmbiente -Destination $ambienteCorrompido
        }

        try {
            $pythonSistema = Selecionar-PythonSistema
            Escrever-Aguarde 'Criando o ambiente virtual do backend...'
            $argumentosVenv = @($pythonSistema.ArgumentosFixos) + @('-m', 'venv', $pastaAmbiente)
            & $pythonSistema.Executavel @argumentosVenv
            if ($LASTEXITCODE -ne 0) {
                throw "A criação do ambiente virtual falhou usando $($pythonSistema.Nome)."
            }
            if (-not (Test-Path -LiteralPath $pythonPrincipal)) {
                throw "A criação do ambiente virtual não gerou o executável esperado: $pythonPrincipal"
            }
            $pythonAmbienteValido = Testar-PythonFuncional $especificacaoAmbiente
            if (-not $pythonAmbienteValido) {
                throw 'O ambiente virtual foi criado, mas seu Python interno não passou na validação.'
            }
            Escrever-Ok 'Ambiente virtual criado e validado.'
            Escrever-Ok "Usando: $pythonPrincipal"

            if ($ambienteCorrompido -and (Test-Path -LiteralPath $ambienteCorrompido)) {
                $paiEsperado = [System.IO.Path]::GetFullPath((Split-Path $pastaAmbiente -Parent)).TrimEnd('\')
                $paiBackup = [System.IO.Path]::GetFullPath((Split-Path $ambienteCorrompido -Parent)).TrimEnd('\')
                if ($paiBackup -ne $paiEsperado -or
                    (Split-Path $ambienteCorrompido -Leaf) -notlike 'venv_corrompido_*') {
                    throw "Caminho inesperado ao remover o ambiente corrompido: $ambienteCorrompido"
                }
                Remove-Item -LiteralPath $ambienteCorrompido -Recurse -Force
                $ambienteCorrompido = $null
            }
        } catch {
            if (Test-Path -LiteralPath $pastaAmbiente) {
                $pastaCriada = [System.IO.Path]::GetFullPath($pastaAmbiente)
                $paiCriado = [System.IO.Path]::GetFullPath((Split-Path $pastaCriada -Parent)).TrimEnd('\')
                $paiEsperado = [System.IO.Path]::GetFullPath((Split-Path $pastaAmbiente -Parent)).TrimEnd('\')
                if ($paiCriado -eq $paiEsperado) {
                    Remove-Item -LiteralPath $pastaCriada -Recurse -Force
                }
            }
            if ($ambienteCorrompido -and (Test-Path -LiteralPath $ambienteCorrompido)) {
                Move-Item -LiteralPath $ambienteCorrompido -Destination $pastaAmbiente
            }
            throw
        }
    }

    $pythonAmbiente = $pythonPrincipal

    if ($PularDependenciasPythonTesteInterno) {
        Escrever-Ok 'Preparação isolada do Python concluída.'
        return $pythonAmbiente
    }

    if ($AtualizarTudo -or -not (Testar-DependenciasBackendAtualizadas)) {
        Escrever-Aguarde 'Sincronizando as dependências do backend...'
        if ($SimularFalhaInstalacaoTesteInterno) {
            throw 'A instalação das dependências do backend falhou (simulação controlada).'
        }
        $preferenciaErroAnterior = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $pythonAmbiente -m pip --disable-pip-version-check install -r $requirements 2>&1 | Out-Host
            $codigoInstalacao = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $preferenciaErroAnterior
        }
        if ($codigoInstalacao -ne 0) {
            throw "A instalação das dependências do backend falhou (código de saída $codigoInstalacao): python -m pip --disable-pip-version-check install -r requirements.txt."
        }
        Set-Content -LiteralPath $marcaRequirements -Value (Obter-HashArquivo $requirements) -Encoding ASCII
    }
    & $pythonAmbiente -c 'import fastapi, uvicorn, sqlalchemy' *> $null
    if ($LASTEXITCODE -ne 0) { throw 'As dependências necessárias do backend não estão disponíveis.' }
    Escrever-Ok 'Ambiente Python e dependências preparados.'
    return $pythonAmbiente
}

function Executar-FlutterSincrono {
    param(
        [Parameter(Mandatory = $true)][string]$Flutter,
        [Parameter(Mandatory = $true)][string[]]$Argumentos,
        [Parameter(Mandatory = $true)][string]$NomeLog
    )
    $execucao = @(Iniciar-ProcessoMonitorado -Arquivo $Flutter -Argumentos $Argumentos `
        -Diretorio $pastaFrontend -NomeLog $NomeLog -NaoRegistrar)[-1]
    try {
        $execucao.Processo.WaitForExit()
        $execucao.Processo.Refresh()
        $resultado = [pscustomobject]@{
            Codigo = [int]$execucao.Processo.ExitCode
            Saida = $execucao.Saida
            Erro = $execucao.Erro
        }
    } finally {
        $execucao.Processo.Dispose()
    }
    Write-Output -NoEnumerate $resultado
}

try {
    Preparar-Logs
    foreach ($arquivo in @($arquivoBackend, $arquivoFlutter, $scriptDemonstracao, $requirements, $setupEnv)) {
        if (-not (Test-Path -LiteralPath $arquivo)) {
            throw "Arquivo obrigatório não encontrado: $arquivo"
        }
    }

    if ($ModoTesteInterno -and -not $ModoTestePythonInterno) {
        $pythonAmbiente = $pythonPrincipal
    } else {
        $pythonAmbiente = Preparar-AmbienteBackend
        if ($SomentePrepararPythonTesteInterno) {
            Escrever-Ok 'Teste isolado da preparação do Python concluído.'
            exit 0
        }
    }

    $flutter = Obter-Flutter
    if (-not $flutter) { throw 'O comando flutter não foi encontrado.' }

    if (-not $ModoTesteInterno) {
        Escrever-Aguarde 'Validando a configuração segura de e-mail...'
        & $pythonAmbiente $setupEnv
        if ($LASTEXITCODE -ne 0) { throw 'Não foi possível verificar a configuração local do backend.' }
    }

    if ($Validar) {
        Escrever-Ok 'INICIAR_TUDO validado com sucesso.'
        Write-Host "Python: $pythonAmbiente"
        Write-Host "Flutter: $flutter"
        Write-Host "Aplicativo Windows atualizado: $(if (Testar-AplicativoAtualizado) { 'sim' } else { 'não; será recompilado no próximo início' })"
        exit 0
    }

    if (-not $ModoTesteInterno) {
        Escrever-Aguarde 'Verificando contas fictícias de demonstração...'
        Push-Location $pastaBackend
        try {
            & $pythonAmbiente $scriptDemonstracao
            if ($LASTEXITCODE -ne 0) { throw 'A preparação das contas de demonstração falhou.' }
        } finally { Pop-Location }

        Write-Host ''
        Write-Host 'CONTAS FICTÍCIAS DE ACESSO' -ForegroundColor Green
        Write-Host 'Administrador  CPF: 12345678909  Senha: Admin@123'
        Write-Host 'Recepção      CPF: 98765432100  Senha: Recepcao@123'
        Write-Host 'Enfermagem    CPF: 11144477735  Senha: Profissional@123'
        Write-Host 'Médico        CPF: 39053344705  Senha: Medico@123'
        Write-Host 'Paciente      CPF: 52998224725  Senha: Paciente@123'
    }

    $estadoPorta = Verificar-PortaBackendDisponivel
    $backend = $null
    if ($estadoPorta -eq 'BackendSaudavel') {
        Escrever-Ok 'Backend já estava iniciado e respondendo.'
    } else {
        Escrever-Aguarde 'Iniciando o backend FastAPI...'
        if ($ModoTesteInterno) {
            if (-not $BackendTesteInterno) { throw 'Backend de teste não informado.' }
            $backend = Iniciar-ProcessoMonitorado -Arquivo $BackendTesteInterno -Argumentos @() `
                -Diretorio $pastaBackend -NomeLog "backend$sufixoLogTeste"
        } else {
            $backend = Iniciar-ProcessoMonitorado -Arquivo $pythonAmbiente `
                -Argumentos @('-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', "$portaBackend") `
                -Diretorio $pastaBackend -NomeLog "backend$sufixoLogTeste"
        }
        $resultadoBackend = Esperar-ProcessoECondicao -Processo $backend.Processo `
            -Condicao { Testar-Api } -TimeoutSegundos $TimeoutBackendSegundos
        if ($resultadoBackend -eq 'Encerrado') {
            $codigo = Obter-CodigoSaida $backend.Processo
            throw "O backend FastAPI foi encerrado durante a inicialização. Código de saída: $codigo"
        }
        if ($resultadoBackend -eq 'TempoEsgotado') {
            throw "O backend não respondeu dentro do tempo limite de $TimeoutBackendSegundos segundos."
        }
        Escrever-Ok 'Backend iniciado e respondendo.'
    }

    if ($backend -and -not (Testar-ProcessoAtivo $backend.Processo)) {
        throw 'O processo do backend encerrou após responder ao endpoint de saúde.'
    }
    $swagger = Invoke-WebRequest -UseBasicParsing -Uri "$urlBackend/docs" -TimeoutSec 5
    if ($swagger.StatusCode -ne 200) { throw 'A documentação Swagger não ficou disponível.' }

    Escrever-Aguarde 'Executando flutter pub get...'
    $pubGet = Executar-FlutterSincrono -Flutter $flutter -Argumentos @('pub', 'get') -NomeLog 'flutter-pub-get'
    if ($pubGet.Codigo -ne 0) {
        Escrever-Erro 'O comando falhou: flutter pub get'
        throw "flutter pub get falhou. Código de saída: $($pubGet.Codigo)"
    }
    Escrever-Ok 'Dependências do Flutter verificadas.'

    $frontend = $null
    if ($Dispositivo -eq 'windows') {
        if ($AtualizarTudo -or -not (Testar-AplicativoAtualizado)) {
            Escrever-Aguarde 'Compilando a interface Flutter para Windows...'
            $build = Executar-FlutterSincrono -Flutter $flutter `
                -Argumentos @('build', 'windows', '--release', "--dart-define=API_BASE_URL=$urlBackend") `
                -NomeLog 'flutter-build-windows'
            if ($build.Codigo -ne 0 -or -not (Test-Path -LiteralPath $executavelWindows)) {
                throw "A compilação do Flutter para Windows falhou. Código de saída: $($build.Codigo)"
            }
            Set-Content -LiteralPath $marcaBuildWindows -Value (Obter-AssinaturaFrontend) -Encoding ASCII
        }
        Escrever-Aguarde 'Iniciando o frontend Flutter para Windows...'
        $frontend = Iniciar-ProcessoMonitorado -Arquivo $executavelWindows -Argumentos @() `
            -Diretorio (Split-Path $executavelWindows) -NomeLog "frontend-windows$sufixoLogTeste" -JanelaNormal
        $resultadoFrontend = Esperar-ProcessoECondicao -Processo $frontend.Processo `
            -Condicao { Testar-JanelaWindows $frontend.Processo } `
            -TimeoutSegundos $TimeoutInicializacaoSegundos `
            -EstabilidadeSegundos $EstabilidadeFrontendSegundos
    } else {
        Verificar-PortaFrontendDisponivel
        Escrever-Aguarde 'Iniciando o servidor Web do frontend Flutter...'
        $argumentosFlutter = @(
            'run', '-d', 'web-server', '--web-hostname', '127.0.0.1',
            '--web-port', "$portaFrontend",
            "--dart-define=API_BASE_URL=$urlBackend"
        )
        $frontend = Iniciar-ProcessoMonitorado -Arquivo $flutter -Argumentos $argumentosFlutter `
            -Diretorio $pastaFrontend -NomeLog "frontend-web-server$sufixoLogTeste"
        $resultadoFrontend = Esperar-ProcessoECondicao -Processo $frontend.Processo `
            -Condicao { Testar-FrontendWeb } `
            -TimeoutSegundos $TimeoutInicializacaoSegundos `
            -EstabilidadeSegundos $EstabilidadeFrontendSegundos
    }

    if ($resultadoFrontend -eq 'Encerrado') {
        $codigo = Obter-CodigoSaida $frontend.Processo
        Escrever-Erro 'O frontend Flutter foi encerrado durante a inicialização.'
        Escrever-Erro "Código de saída: $codigo"
        throw 'O frontend Flutter encerrou antes de ficar disponível.'
    }
    if ($resultadoFrontend -eq 'TempoEsgotado') {
        throw "O frontend não ficou disponível. Tempo limite de $TimeoutInicializacaoSegundos segundos excedido."
    }
    if (-not (Testar-ProcessoAtivo $frontend.Processo)) {
        throw 'O frontend Flutter encerrou imediatamente após a verificação de prontidão.'
    }
    if (-not (Testar-Api)) {
        throw 'A API deixou de responder antes da conclusão da inicialização.'
    }
    if ($Dispositivo -ne 'windows' -and -not (Testar-FrontendWeb)) {
        throw 'O frontend Web deixou de responder antes da conclusão da inicialização.'
    }

    Escrever-Ok 'Frontend Flutter disponível.'
    if ($Dispositivo -ne 'windows') {
        Abrir-FrontendNoNavegador
    }
    Escrever-Ok 'Sistema iniciado com sucesso.'
    Write-Host "Backend: $urlBackend/docs"
    if ($Dispositivo -eq 'windows') {
        Write-Host 'Frontend Flutter: aplicativo Windows iniciado'
    } else {
        Write-Host "Frontend Flutter: $urlFrontend (servidor Web; navegador $Dispositivo separado)"
    }
    $script:inicializacaoConcluida = $true

    if ($EncerrarAposValidacaoInterna) {
        Parar-ProcessosCriados
    } elseif (-not $SemPausa) {
        Write-Host ''
        Read-Host 'O sistema está em execução. Pressione ENTER para encerrar backend e frontend'
        Parar-ProcessosCriados
        Escrever-Ok 'Sistema encerrado e processos liberados.'
    }
    exit 0
} catch {
    Escrever-Erro $_.Exception.Message
    Mostrar-LogsFalha
    Parar-ProcessosCriados
    exit 1
}
