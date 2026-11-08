$cenario = $env:UBS_LAUNCHER_TEST_SCENARIO
$porta = if ($env:UBS_LAUNCHER_TEST_BACKEND_PORT) {
    [int]$env:UBS_LAUNCHER_TEST_BACKEND_PORT
} else { 8000 }
if ($env:UBS_LAUNCHER_TEST_BACKEND_PID_FILE) {
    Set-Content -LiteralPath $env:UBS_LAUNCHER_TEST_BACKEND_PID_FILE -Value $PID -Encoding ASCII
}
if ($cenario -eq 'backend-failure') {
    [Console]::Error.WriteLine('falha simulada do backend')
    exit 51
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $porta)
$listener.Start()
try {
    Write-Output "backend de teste pronto em 127.0.0.1:$porta"
    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $reader = [System.IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
            $primeiraLinha = $reader.ReadLine()
            while ($reader.ReadLine()) { }
            $corpo = if ($primeiraLinha -match ' /health ') { '{"status":"ok"}' } else { '<html>Swagger</html>' }
            $tipo = if ($primeiraLinha -match ' /health ') { 'application/json' } else { 'text/html' }
            $payload = [Text.Encoding]::UTF8.GetBytes($corpo)
            $cabecalho = "HTTP/1.1 200 OK`r`nContent-Type: $tipo`r`nContent-Length: $($payload.Length)`r`nConnection: close`r`n`r`n"
            $bytesCabecalho = [Text.Encoding]::ASCII.GetBytes($cabecalho)
            $stream.Write($bytesCabecalho, 0, $bytesCabecalho.Length)
            $stream.Write($payload, 0, $payload.Length)
        } catch [System.IO.IOException] {
            # O cliente de uma sondagem pode encerrar a conexão antecipadamente.
        } finally {
            $client.Dispose()
        }
    }
} finally {
    $listener.Stop()
}
