param([Parameter(Mandatory = $true)][string]$Url)

if ($env:UBS_LAUNCHER_TEST_BROWSER_MARKER) {
    Set-Content -LiteralPath $env:UBS_LAUNCHER_TEST_BROWSER_MARKER -Value $Url -Encoding UTF8
}

# Simula uma janela que o usuário fecha sem afetar o servidor Web.
Start-Sleep -Milliseconds 300
