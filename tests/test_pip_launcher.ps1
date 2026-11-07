$ErrorActionPreference = 'Stop'

$raizProjeto = Split-Path -Parent $PSScriptRoot
$iniciador = Join-Path $raizProjeto 'INICIAR_TUDO.bat'
$scriptIniciador = Join-Path $raizProjeto 'scripts\iniciar.ps1'
$pythonReal = (Get-Command python -CommandType Application -ErrorAction Stop |
    Select-Object -First 1).Source
$pastaTeste = Join-Path $raizProjeto ('.test-tmp\pip-launcher-{0}' -f [guid]::NewGuid().ToString('N'))
$pastaTesteCompleta = [System.IO.Path]::GetFullPath($pastaTeste)
$raizCompleta = [System.IO.Path]::GetFullPath($raizProjeto).TrimEnd('\') + '\'
if (-not $pastaTesteCompleta.StartsWith($raizCompleta, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Pasta temporária fora do projeto: $pastaTesteCompleta"
}

function Invocar-CenarioPip {
    param([Parameter(Mandatory = $true)][string]$Cenario)
    $cenarioAnterior = $env:UBS_PIP_TEST_SCENARIO
    $env:UBS_PIP_TEST_SCENARIO = $Cenario
    $preferenciaAnterior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $saida = & $iniciador `
            -ModoTestePythonInterno `
            -PastaAmbienteTesteInterno $pastaTesteCompleta `
            -SomentePrepararPythonTesteInterno `
            -SemPausa 2>&1 | Out-String
        return [pscustomobject]@{ Codigo = $LASTEXITCODE; Saida = $saida }
    } finally {
        $ErrorActionPreference = $preferenciaAnterior
        $env:UBS_PIP_TEST_SCENARIO = $cenarioAnterior
    }
}

try {
    New-Item -ItemType Directory -Path $pastaTesteCompleta -Force | Out-Null
    & $pythonReal -m venv --without-pip $pastaTesteCompleta
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível criar o ambiente Python isolado do teste.' }

    $sitePackages = Join-Path $pastaTesteCompleta 'Lib\site-packages'
    foreach ($modulo in @('fastapi', 'uvicorn', 'sqlalchemy')) {
        $pastaModulo = Join-Path $sitePackages $modulo
        New-Item -ItemType Directory -Path $pastaModulo -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $pastaModulo '__init__.py') -Value '' -Encoding ASCII
    }
    $pastaPip = Join-Path $sitePackages 'pip'
    New-Item -ItemType Directory -Path $pastaPip -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $pastaPip '__init__.py') -Value '' -Encoding ASCII
    @'
import os
import sys

expected = ["--disable-pip-version-check", "install", "-r"]
if not all(argument in sys.argv for argument in expected):
    print("argumentos obrigatórios do pip ausentes: " + " ".join(sys.argv[1:]), file=sys.stderr)
    raise SystemExit(64)

scenario = os.environ.get("UBS_PIP_TEST_SCENARIO")
if scenario == "warning":
    print("aviso simulado no canal de erro", file=sys.stderr)
    raise SystemExit(0)
if scenario == "failure":
    print("falha simulada do pip", file=sys.stderr)
    raise SystemExit(23)
raise SystemExit(65)
'@ | Set-Content -LiteralPath (Join-Path $pastaPip '__main__.py') -Encoding UTF8

    $aviso = Invocar-CenarioPip -Cenario 'warning'
    if ($aviso.Codigo -ne 0) {
        throw "Um aviso do pip com saída 0 interrompeu o iniciador.`n$($aviso.Saida)"
    }
    if ($aviso.Saida -notmatch 'aviso simulado no canal de erro') {
        throw "O cenário de aviso não escreveu no canal de erro como esperado.`n$($aviso.Saida)"
    }

    Remove-Item -LiteralPath (Join-Path $pastaTesteCompleta '.ubs_requirements_stamp') `
        -Force -ErrorAction SilentlyContinue
    $falha = Invocar-CenarioPip -Cenario 'failure'
    if ($falha.Codigo -eq 0) {
        throw "Uma falha real do pip não interrompeu o iniciador.`n$($falha.Saida)"
    }
    foreach ($trecho in @(
        'falha simulada do pip',
        'instalação das dependências do backend falhou',
        'código de saída 23'
    )) {
        if ($falha.Saida -notmatch $trecho) {
            throw "A falha real não exibiu o diagnóstico esperado: $trecho.`n$($falha.Saida)"
        }
    }
    if ($falha.Saida -match '(?m)^\[ERRO\]\s*$') {
        throw "A falha real exibiu [ERRO] sem explicação.`n$($falha.Saida)"
    }

    $conteudo = Get-Content -Raw -LiteralPath $scriptIniciador
    if ($conteudo -notmatch [regex]::Escape('-m pip --disable-pip-version-check install')) {
        throw 'A chamada do pip não desabilita a verificação de versão.'
    }
    if ($conteudo -match '(?i)-m\s+pip\s+install\s+--upgrade\s+pip') {
        throw 'O iniciador não deve atualizar o pip automaticamente.'
    }

    Write-Host 'PASS: avisos do pip seguem o código de saída e falhas reais mantêm diagnóstico claro.' `
        -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $pastaTesteCompleta) {
        Remove-Item -LiteralPath $pastaTesteCompleta -Recurse -Force
    }
}
