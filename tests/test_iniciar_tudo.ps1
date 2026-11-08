$ErrorActionPreference = 'Stop'

$raizProjeto = Split-Path -Parent $PSScriptRoot
$iniciador = Join-Path $raizProjeto 'INICIAR_TUDO.bat'
$scriptIniciador = Join-Path $raizProjeto 'scripts\iniciar.ps1'
$flutterFalso = Join-Path $PSScriptRoot 'fixtures\fake_flutter.ps1'
$backendFalso = Join-Path $PSScriptRoot 'fixtures\fake_backend.ps1'
$navegadorFalso = Join-Path $PSScriptRoot 'fixtures\fake_browser.ps1'
$arquivoPidBackend = Join-Path $env:TEMP ('.ubs-backend-test-{0}.pid' -f [guid]::NewGuid().ToString('N'))
$arquivoPidFrontend = Join-Path $env:TEMP ('.ubs-frontend-test-{0}.pid' -f [guid]::NewGuid().ToString('N'))

function Obter-PortaLivre {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try { return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port } finally { $listener.Stop() }
}

$portaBackendTeste = Obter-PortaLivre
$portaFrontendTeste = Obter-PortaLivre
while ($portaFrontendTeste -eq $portaBackendTeste) { $portaFrontendTeste = Obter-PortaLivre }

function Invocar-Iniciador {
    param([string]$Cenario = '', [string[]]$Argumentos = @())
    $cenarioAnterior = $env:UBS_LAUNCHER_TEST_SCENARIO
    $portaBackendAnterior = $env:UBS_LAUNCHER_TEST_BACKEND_PORT
    $portaFrontendAnterior = $env:UBS_LAUNCHER_TEST_FRONTEND_PORT
    $env:UBS_LAUNCHER_TEST_SCENARIO = $Cenario
    $env:UBS_LAUNCHER_TEST_BACKEND_PORT = "$portaBackendTeste"
    $env:UBS_LAUNCHER_TEST_FRONTEND_PORT = "$portaFrontendTeste"
    $preferenciaAnterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $saida = & $iniciador @Argumentos 2>&1 | Out-String
        $codigo = $LASTEXITCODE
        return [pscustomobject]@{ Codigo = $codigo; Saida = $saida }
    } finally {
        $ErrorActionPreference = $preferenciaAnterior
        $env:UBS_LAUNCHER_TEST_SCENARIO = $cenarioAnterior
        $env:UBS_LAUNCHER_TEST_BACKEND_PORT = $portaBackendAnterior
        $env:UBS_LAUNCHER_TEST_FRONTEND_PORT = $portaFrontendAnterior
    }
}

function Parar-OuvintesTeste {
    foreach ($arquivoPid in $arquivoPidBackend, $arquivoPidFrontend) {
        if (-not (Test-Path -LiteralPath $arquivoPid)) { continue }
        $idProcesso = [int](Get-Content -Raw -LiteralPath $arquivoPid)
        Stop-Process -Id $idProcesso -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $arquivoPid -Force -ErrorAction SilentlyContinue
    }
    foreach ($porta in $portaBackendTeste, $portaFrontendTeste) {
        $ids = Get-NetTCPConnection -LocalPort $porta -State Listen -ErrorAction SilentlyContinue |
            Where-Object OwningProcess -gt 0 |
            Select-Object -ExpandProperty OwningProcess -Unique
        foreach ($idProcesso in $ids) {
            Stop-Process -Id $idProcesso -Force -ErrorAction SilentlyContinue
        }
    }
}

function Verificar-FalhaControlada {
    param(
        [string]$Nome,
        [string]$Cenario,
        [string]$MensagemEsperada,
        [int]$TimeoutSegundos = 5
    )
    $resultado = Invocar-Iniciador -Cenario $Cenario -Argumentos @(
        '-Dispositivo', 'chrome', '-ModoTesteInterno',
        '-FlutterTesteInterno', $flutterFalso,
        '-BackendTesteInterno', $backendFalso,
        '-PortaBackendTesteInterno', "$portaBackendTeste",
        '-PortaFrontendTesteInterno', "$portaFrontendTeste",
        '-TimeoutInicializacaoSegundos', "$TimeoutSegundos",
        '-EstabilidadeFrontendSegundos', '1', '-SemPausa'
    )
    if ($resultado.Codigo -eq 0) {
        throw "$Nome deveria falhar, mas retornou sucesso.`n$($resultado.Saida)"
    }
    if ($resultado.Saida -match 'Sistema iniciado com sucesso') {
        throw "$Nome exibiu falso positivo de inicialização.`n$($resultado.Saida)"
    }
    if ($resultado.Saida -notmatch $MensagemEsperada) {
        throw "$Nome não exibiu o diagnóstico esperado ($MensagemEsperada).`n$($resultado.Saida)"
    }
    if ($resultado.Saida -notmatch 'Logs desta inicializa') {
        throw "$Nome não informou/exibiu os logs da inicialização.`n$($resultado.Saida)"
    }
    Start-Sleep -Milliseconds 300
    foreach ($porta in $portaBackendTeste, $portaFrontendTeste) {
        $listenerAtivo = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalPort -eq $porta -and $_.OwningProcess -gt 0 } |
            Select-Object -First 1
        if ($listenerAtivo) {
            throw "$Nome deixou um processo de teste criado pelo launcher ouvindo na porta $porta."
        }
    }
}

$primeira = Invocar-Iniciador -Argumentos @('-Validar', '-SemPausa')
if ($primeira.Codigo -ne 0) { throw "A validação oficial falhou.`n$($primeira.Saida)" }
if ($primeira.Saida -match 'Atualizando as depend.ncias do backend') {
    throw "O iniciador padrão não deve atualizar dependências em toda abertura.`n$($primeira.Saida)"
}
$segunda = Invocar-Iniciador -Argumentos @('-Validar', '-SemPausa')
if ($segunda.Codigo -ne 0) { throw "A segunda validação oficial falhou.`n$($segunda.Saida)" }
if ($segunda.Saida -match 'Sincronizando as depend.ncias do backend') {
    throw "O iniciador não deve reinstalar dependências que já estão sincronizadas.`n$($segunda.Saida)"
}

$atualizacaoCompleta = Invocar-Iniciador -Argumentos @('-AtualizarTudo', '-Validar', '-SemPausa')
if ($atualizacaoCompleta.Codigo -ne 0) {
    throw "A validação com atualização completa falhou.`n$($atualizacaoCompleta.Saida)"
}
if ($atualizacaoCompleta.Saida -notmatch 'Sincronizando as depend') {
    throw "A atualização completa não sincronizou as dependências do backend.`n$($atualizacaoCompleta.Saida)"
}
if ($atualizacaoCompleta.Saida -match '(?s)Requirement already satisfied:.*reconhecido') {
    throw "A saída do pip foi confundida com o caminho do Python.`n$($atualizacaoCompleta.Saida)"
}

$normal = Invocar-Iniciador -Argumentos @(
    '-Dispositivo', 'chrome', '-ModoTesteInterno',
    '-FlutterTesteInterno', $flutterFalso,
    '-BackendTesteInterno', $backendFalso,
    '-PortaBackendTesteInterno', "$portaBackendTeste",
    '-PortaFrontendTesteInterno', "$portaFrontendTeste",
    '-TimeoutInicializacaoSegundos', '5',
    '-EstabilidadeFrontendSegundos', '1',
    '-EncerrarAposValidacaoInterna', '-SemPausa'
)
if ($normal.Codigo -ne 0 -or $normal.Saida -notmatch 'Sistema iniciado com sucesso') {
    throw "O fluxo normal pelo INICIAR_TUDO.bat falhou.`n$($normal.Saida)"
}

$conteudoPowerShell = Get-Content -Raw $scriptIniciador
foreach ($trechoServidorWeb in @(
    "'run', '-d', 'web-server'",
    "'--web-hostname', '127.0.0.1'",
    'Testar-Api',
    'Testar-FrontendWeb',
    'Abrir-FrontendNoNavegador',
    'Sistema encerrado e processos liberados.'
)) {
    if ($conteudoPowerShell -notmatch [regex]::Escape($trechoServidorWeb)) {
        throw "O iniciador não contém o modo Web independente esperado: $trechoServidorWeb"
    }
}
if ($conteudoPowerShell -match "'run', '-d', \`$Dispositivo") {
    throw 'O iniciador ainda vincula o servidor Web à janela do Chrome ou Edge.'
}

$marcadorNavegador = Join-Path $env:TEMP ('.ubs-browser-test-{0}.txt' -f [guid]::NewGuid().ToString('N'))
$marcadorAnterior = $env:UBS_LAUNCHER_TEST_BROWSER_MARKER
$pidBackendAnterior = $env:UBS_LAUNCHER_TEST_BACKEND_PID_FILE
$pidFrontendAnterior = $env:UBS_LAUNCHER_TEST_FRONTEND_PID_FILE
$cenarioAnterior = $env:UBS_LAUNCHER_TEST_SCENARIO
$portaBackendAnterior = $env:UBS_LAUNCHER_TEST_BACKEND_PORT
$portaFrontendAnterior = $env:UBS_LAUNCHER_TEST_FRONTEND_PORT
$env:UBS_LAUNCHER_TEST_BROWSER_MARKER = $marcadorNavegador
$env:UBS_LAUNCHER_TEST_BACKEND_PID_FILE = $arquivoPidBackend
$env:UBS_LAUNCHER_TEST_FRONTEND_PID_FILE = $arquivoPidFrontend
$env:UBS_LAUNCHER_TEST_SCENARIO = ''
$env:UBS_LAUNCHER_TEST_BACKEND_PORT = "$portaBackendTeste"
$env:UBS_LAUNCHER_TEST_FRONTEND_PORT = "$portaFrontendTeste"
$saidaIndependente = Join-Path $env:TEMP ('.ubs-launcher-test-{0}.stdout' -f [guid]::NewGuid().ToString('N'))
$erroIndependente = Join-Path $env:TEMP ('.ubs-launcher-test-{0}.stderr' -f [guid]::NewGuid().ToString('N'))
try {
    $argumentosIndependente = @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptIniciador,
        '-Dispositivo', 'chrome', '-ModoTesteInterno',
        '-FlutterTesteInterno', $flutterFalso,
        '-BackendTesteInterno', $backendFalso,
        '-NavegadorTesteInterno', $navegadorFalso,
        '-PortaBackendTesteInterno', "$portaBackendTeste",
        '-PortaFrontendTesteInterno', "$portaFrontendTeste",
        '-TimeoutInicializacaoSegundos', '5',
        '-EstabilidadeFrontendSegundos', '1', '-SemPausa'
    )
    $processoIniciador = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList $argumentosIndependente -WorkingDirectory $raizProjeto `
        -RedirectStandardOutput $saidaIndependente -RedirectStandardError $erroIndependente `
        -WindowStyle Hidden -PassThru
    $null = $processoIniciador.Handle
    if (-not $processoIniciador.WaitForExit(15000)) {
        Stop-Process -Id $processoIniciador.Id -Force -ErrorAction SilentlyContinue
        throw 'O modo Web independente não concluiu o iniciador no tempo esperado.'
    }
    $processoIniciador.WaitForExit()
    $processoIniciador.Refresh()
    $saidaModoIndependente = (Get-Content -Raw -LiteralPath $saidaIndependente) +
        (Get-Content -Raw -LiteralPath $erroIndependente)
    if ($processoIniciador.ExitCode -ne 0 -or $saidaModoIndependente -notmatch 'Sistema iniciado com sucesso') {
        throw "O modo Web independente falhou.`n$saidaModoIndependente"
    }
    Start-Sleep -Milliseconds 700
    if (-not (Test-Path -LiteralPath $marcadorNavegador)) {
        throw 'O navegador separado não foi aberto pelo iniciador.'
    }
    if ((Get-Content -Raw -LiteralPath $marcadorNavegador).Trim() -ne "http://127.0.0.1:$portaFrontendTeste") {
        throw 'O navegador separado não recebeu o endereço local do frontend.'
    }
    foreach ($tentativa in 1..2) {
        $resposta = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$portaFrontendTeste" -TimeoutSec 2
        if ($resposta.StatusCode -ne 200) {
            throw "O frontend não respondeu ao abrir o endereço pela vez $tentativa."
        }
    }
} finally {
    $env:UBS_LAUNCHER_TEST_BROWSER_MARKER = $marcadorAnterior
    $env:UBS_LAUNCHER_TEST_BACKEND_PID_FILE = $pidBackendAnterior
    $env:UBS_LAUNCHER_TEST_FRONTEND_PID_FILE = $pidFrontendAnterior
    $env:UBS_LAUNCHER_TEST_SCENARIO = $cenarioAnterior
    $env:UBS_LAUNCHER_TEST_BACKEND_PORT = $portaBackendAnterior
    $env:UBS_LAUNCHER_TEST_FRONTEND_PORT = $portaFrontendAnterior
    Parar-OuvintesTeste
    Remove-Item -LiteralPath $marcadorNavegador -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $saidaIndependente,$erroIndependente -Force -ErrorAction SilentlyContinue
}

$ocupanteFrontend = [System.Net.Sockets.TcpListener]::new(
    [System.Net.IPAddress]::Loopback, $portaFrontendTeste
)
$ocupanteFrontend.Start()
try {
    $portaOcupada = Invocar-Iniciador -Argumentos @(
        '-Dispositivo', 'chrome', '-ModoTesteInterno',
        '-FlutterTesteInterno', $flutterFalso,
        '-BackendTesteInterno', $backendFalso,
        '-PortaBackendTesteInterno', "$portaBackendTeste",
        '-PortaFrontendTesteInterno', "$portaFrontendTeste",
        '-TimeoutInicializacaoSegundos', '5', '-SemPausa'
    )
    if ($portaOcupada.Codigo -eq 0 -or
        $portaOcupada.Saida -notmatch "porta $portaFrontendTeste do frontend está ocupada") {
        throw "A porta Web ocupada não produziu diagnóstico claro.`n$($portaOcupada.Saida)"
    }
    if ($portaOcupada.Saida -match 'Sistema iniciado com sucesso') {
        throw 'A porta Web ocupada produziu falso sucesso.'
    }
} finally {
    $ocupanteFrontend.Stop()
    Parar-OuvintesTeste
}

Verificar-FalhaControlada -Nome 'Falha no flutter pub get' -Cenario 'pub-get-failure' -MensagemEsperada 'flutter pub get falhou'
Verificar-FalhaControlada -Nome 'Comando/dispositivo Flutter inválido' -Cenario 'invalid-command' -MensagemEsperada 'encerrado durante a inicializa'
Verificar-FalhaControlada -Nome 'Encerramento precoce do frontend' -Cenario 'early-exit' -MensagemEsperada 'encerrado durante a inicializa'
Verificar-FalhaControlada -Nome 'Timeout do frontend' -Cenario 'timeout' -MensagemEsperada 'Tempo limite de 2 segundos' -TimeoutSegundos 2
Verificar-FalhaControlada -Nome 'Falha do backend' -Cenario 'backend-failure' -MensagemEsperada 'backend FastAPI foi encerrado'

$dispositivoInvalido = Invocar-Iniciador -Argumentos @('-Dispositivo', 'inexistente', '-SemPausa')
if ($dispositivoInvalido.Codigo -eq 0 -or $dispositivoInvalido.Saida -match 'iniciado com sucesso') {
    throw "Um dispositivo inválido não foi rejeitado corretamente.`n$($dispositivoInvalido.Saida)"
}

$conteudoBatch = Get-Content -Raw $iniciador
foreach ($trecho in @(
    'if "%~1"==""',
    'scripts\iniciar.ps1" -AtualizarTudo',
    'passe -AtualizarTudo para obter o mesmo comportamento',
    'Atualizacao completa automatica',
    'if not exist "%~dp0scripts\iniciar.ps1"',
    'Inicializacao concluida pelo botao INICIAR_TUDO'
)) {
    if ($conteudoBatch -notmatch [regex]::Escape($trecho)) {
        throw "O botão não garante a atualização completa no duplo clique: $trecho"
    }
}

$conteudoSeed = Get-Content -Raw (Join-Path $raizProjeto 'backend\app\core\demo_accounts.py')
$contasSeed = [regex]::Matches(
    $conteudoSeed,
    'DemoAccount\(\s*"(?<perfil>[^"]+)",\s*"[^"]+",\s*"(?<cpf>\d{11})",\s*"(?<senha>[^"]+)"'
)
$credenciaisOficiais = foreach ($perfil in @('admin', 'recepcao', 'enfermagem', 'medico', 'paciente')) {
    $conta = $contasSeed | Where-Object { $_.Groups['perfil'].Value -eq $perfil } | Select-Object -First 1
    if (-not $conta) {
        throw "Não foi possível consultar a conta fictícia oficial do perfil $perfil."
    }
    'CPF: {0}  Senha: {1}' -f $conta.Groups['cpf'].Value, $conta.Groups['senha'].Value
}
$trechosEsperados = @($credenciaisOficiais) + @(
    '.ubs_build_stamp', 'Testar-AplicativoAtualizado',
    '.ubs_requirements_stamp', 'Testar-DependenciasBackendAtualizadas',
    'RedirectStandardOutput', 'RedirectStandardError', 'Esperar-ProcessoECondicao'
)
foreach ($trecho in $trechosEsperados) {
    if ($conteudoPowerShell -notmatch [regex]::Escape($trecho)) {
        throw "O iniciador não contém o comportamento esperado: $trecho"
    }
}

Write-Host 'PASS: o launcher só anuncia sucesso após backend e frontend ficarem prontos.' -ForegroundColor Green
