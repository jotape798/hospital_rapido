param(
    [string]$DistributionPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'dist')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dist = [IO.Path]::GetFullPath($DistributionPath)
$allowedDist = [IO.Path]::GetFullPath((Join-Path $root 'dist'))
if (-not $dist.Equals($allowedDist, [StringComparison]::OrdinalIgnoreCase)) {
    throw "A auditoria só aceita a pasta de distribuição do projeto: $allowedDist"
}
if (-not (Test-Path -LiteralPath $dist)) { throw "Distribuição não encontrada: $dist" }

$proibidosPorNome = @(
    '.env', 'profissionais_demo.env.local', 'ubs_rapida.db',
    '*.db', '*.sqlite', '*.sqlite3', '*.bak', '*.backup', '*.log', '*.pyc'
)
$pastasProibidas = @('venv', '.venv', '__pycache__', '.pytest_cache', 'tests', 'test')
$falhas = New-Object System.Collections.Generic.List[string]

foreach ($arquivo in Get-ChildItem -LiteralPath $dist -File -Recurse -Force) {
    foreach ($padrao in $proibidosPorNome) {
        if ($arquivo.Name -like $padrao) {
            $falhas.Add("Arquivo proibido: $($arquivo.FullName)")
        }
    }
}
foreach ($pasta in Get-ChildItem -LiteralPath $dist -Directory -Recurse -Force) {
    if ($pastasProibidas -contains $pasta.Name.ToLowerInvariant()) {
        $falhas.Add("Pasta proibida: $($pasta.FullName)")
    }
}

function Obter-ValoresSensiveis {
    $valores = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::Ordinal)
    foreach ($arquivo in @(
        (Join-Path $root 'backend\.env'),
        (Join-Path $root 'backend\profissionais_demo.env.local')
    )) {
        if (-not (Test-Path -LiteralPath $arquivo)) { continue }
        foreach ($linha in Get-Content -LiteralPath $arquivo -Encoding UTF8) {
            if ($linha -match '^\s*(?:SMTP_USER|SMTP_PASSWORD|JWT_SECRET_KEY|[^#=]+PASSWORD[^=]*)\s*=\s*(.+?)\s*$') {
                $valor = $Matches[1].Trim('"', "'")
                if ($valor.Length -ge 6 -and $valor -notmatch '^COLOQUE_') { $null = $valores.Add($valor) }
            }
        }
    }
    $demo = Join-Path $root 'backend\app\core\demo_accounts.py'
    if (Test-Path -LiteralPath $demo) {
        $conteudo = Get-Content -LiteralPath $demo -Raw -Encoding UTF8
        foreach ($match in [regex]::Matches($conteudo, '"(?<valor>[A-Za-zÀ-ÿ]+@\d{3})"')) {
            $null = $valores.Add($match.Groups['valor'].Value)
        }
    }
    return @($valores)
}

if (-not ('UbsRapida.DistributionAudit' -as [type])) {
    Add-Type -TypeDefinition @'
namespace UbsRapida {
    public static class DistributionAudit {
        public static bool Contains(byte[] content, byte[] pattern) {
            if (pattern == null || pattern.Length == 0 || content.Length < pattern.Length) return false;
            int limit = content.Length - pattern.Length;
            for (int i = 0; i <= limit; i++) {
                if (content[i] != pattern[0]) continue;
                int j = 1;
                while (j < pattern.Length && content[i + j] == pattern[j]) j++;
                if (j == pattern.Length) return true;
            }
            return false;
        }
    }
}
'@
}

function Testar-BytesContem {
    param([byte[]]$Conteudo, [byte[]]$Padrao)
    return [UbsRapida.DistributionAudit]::Contains($Conteudo, $Padrao)
}

$valoresSensiveis = Obter-ValoresSensiveis
$alvosConteudo = @(
    Get-ChildItem -LiteralPath (Join-Path $dist 'windows') -File -Recurse -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath (Join-Path $dist 'web') -File -Recurse -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath (Join-Path $dist 'downloads') -File -Recurse -ErrorAction SilentlyContinue
)
foreach ($arquivo in $alvosConteudo) {
    if ($arquivo.Length -gt 300MB) { continue }
    $bytes = [IO.File]::ReadAllBytes($arquivo.FullName)
    foreach ($valor in $valoresSensiveis) {
        if (Testar-BytesContem $bytes ([Text.Encoding]::UTF8.GetBytes($valor))) {
            $falhas.Add("Valor sensível encontrado em: $($arquivo.FullName)")
        }
    }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archives = Get-ChildItem -LiteralPath (Join-Path $dist 'android') -File -ErrorAction SilentlyContinue |
    Where-Object Extension -in @('.apk', '.aab')
foreach ($archive in $archives) {
    $zip = [IO.Compression.ZipFile]::OpenRead($archive.FullName)
    try {
        foreach ($entry in $zip.Entries) {
            if (-not $entry.Name) { continue }
            foreach ($padrao in $proibidosPorNome) {
                if ($entry.Name -like $padrao) {
                    $falhas.Add("Arquivo proibido dentro de $($archive.Name): $($entry.FullName)")
                }
            }
            if ($entry.Length -gt 300MB) { continue }
            $stream = $entry.Open()
            $memory = New-Object IO.MemoryStream
            try {
                $stream.CopyTo($memory)
                $bytes = $memory.ToArray()
            } finally {
                $memory.Dispose()
                $stream.Dispose()
            }
            foreach ($valor in $valoresSensiveis) {
                if (Testar-BytesContem $bytes ([Text.Encoding]::UTF8.GetBytes($valor))) {
                    $falhas.Add("Valor sensível encontrado dentro de: $($archive.Name)")
                }
            }
        }
    } finally {
        $zip.Dispose()
    }
}

if ($falhas.Count -gt 0) {
    $falhas | ForEach-Object { Write-Error $_ }
    throw "A auditoria encontrou $($falhas.Count) item(ns) proibido(s)."
}

Write-Host 'AUDITORIA DE DISTRIBUIÇÃO: APROVADA' -ForegroundColor Green
Write-Host "Arquivos inspecionados: $(@(Get-ChildItem -LiteralPath $dist -File -Recurse).Count)"
Write-Host "Valores locais sensíveis verificados sem exposição: $($valoresSensiveis.Count)"
