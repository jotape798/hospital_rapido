$acao = $args -join ' '
$cenario = $env:UBS_LAUNCHER_TEST_SCENARIO
$porta = if ($env:UBS_LAUNCHER_TEST_FRONTEND_PORT) {
    [int]$env:UBS_LAUNCHER_TEST_FRONTEND_PORT
} else { 8080 }
if ($env:UBS_LAUNCHER_TEST_FRONTEND_PID_FILE) {
    Set-Content -LiteralPath $env:UBS_LAUNCHER_TEST_FRONTEND_PID_FILE -Value $PID -Encoding ASCII
}

if ($acao -eq 'pub get') {
    if ($cenario -eq 'pub-get-failure') {
        [Console]::Error.WriteLine('falha simulada no flutter pub get')
        exit 41
    }
    Write-Output 'flutter pub get simulado com sucesso'
    exit 0
}

if ($acao -notmatch '^run -d web-server --web-hostname 127\.0\.0\.1 --web-port \d+ ') {
    [Console]::Error.WriteLine("comando Flutter inválido: $acao")
    exit 44
}
if ($cenario -eq 'invalid-command') {
    [Console]::Error.WriteLine('dispositivo/comando Flutter inválido simulado')
    exit 45
}
if ($cenario -eq 'early-exit') {
    Write-Output 'frontend iniciou parcialmente'
    [Console]::Error.WriteLine('frontend encerrou antes da prontidão')
    exit 46
}
if ($cenario -eq 'timeout') {
    Write-Output 'frontend permanece vivo, mas nunca fica pronto'
    Start-Sleep -Seconds 60
    exit 0
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $porta)
$listener.Start()
try {
    Write-Output "frontend de teste pronto em 127.0.0.1:$porta"
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = [System.IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
            while ($reader.ReadLine()) { }
            $payload = [Text.Encoding]::UTF8.GetBytes('UBS Rapida')
            $header = "HTTP/1.1 200 OK`r`nContent-Type: text/plain`r`nContent-Length: $($payload.Length)`r`nConnection: close`r`n`r`n"
            $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            $stream.Write($payload, 0, $payload.Length)
        } catch [System.IO.IOException] {
            # Sondagens de prontidão podem encerrar a conexão antes de ler a
            # resposta completa. Um servidor web real continua atendendo; o
            # fixture deve reproduzir esse comportamento em vez de encerrar.
        } finally {
            $client.Dispose()
        }
    }
} finally {
    $listener.Stop()
}
