# Status da entrega final — UBS Rápida

- **Versão:** 0.1.0
- **Validação local:** 19/11/2026, 16:37 (America/Sao_Paulo)
- **Commit de código validado:** `b754e9ef8412781521cb9a6310a256d917b397af`
- **Commit documental final:** o commit que contém este documento; consultável no histórico Git, sem hash autorreferente
**Tag e commit da Release:** pendentes, pois o GitHub CLI não estava instalado no ambiente de validação

## Resultado da validação

| Verificação | Resultado real |
| --- | --- |
| Backend | 232 aprovados, 0 falhas, 1 aviso, 251,36 s (252,86 s total) |
| Flutter | 190 aprovados, 0 falhas, 69,74 s total |
| `flutter analyze` | `No issues found!`, 0 ocorrências |
| Iniciador principal | Aprovado em 43,11 s; aguarda backend e frontend e usa `UBS_Rapida.exe` |
| Fallback Python | Aprovado em 48,26 s |
| Launcher do pip | Aprovado em 2,33 s |
| Build Windows | Aprovado em 162,89 s |
| Teste externo do pacote | Backend, `/health`, Swagger 200, frontend e iniciador aprovados em 32,16 s |
| Auditoria da distribuição | Aprovada em 27,02 s; 4.692 arquivos inspecionados |

A primeira execução do backend terminou com 229 testes aprovados e 3 erros de setup porque o Windows negou acesso ao diretório global temporário do Pytest. Nenhuma lógica funcional falhou. A suíte completa foi repetida com `--basetemp` em diretório ignorado do projeto e aprovou os 232 testes. O banco real permaneceu inalterado, com SHA-256 `4EF0216EFDB4701C175C46607A1C4FA48C5ED74B4B7B5DFDB5B6DC5AAE1F2449` antes e depois.

O único aviso do backend é uma depreciação da dependência `starlette.testclient` sobre o alias `anyio.abc.BlockingPortal`.

## Comandos executados

```powershell
cd C:\ubs_Hospital_rapido\backend
.\venv\Scripts\python.exe -m pytest -q
.\venv\Scripts\python.exe -m pytest -q --basetemp .pytest_release_v010

cd C:\ubs_Hospital_rapido\frontend
flutter test
flutter analyze

cd C:\ubs_Hospital_rapido
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_iniciar_tudo.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_python_fallback.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_pip_launcher.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_windows_distribution.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\audit_distribution.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test_windows_package.ps1
git diff --check
```

## Pacote Windows

- Entrega oficial: Windows desktop.
- Arquivo: `UBS_Rapida-Windows-0.1.0.zip`.
- Tamanho: 65.870.055 bytes (62,82 MiB).
- SHA-256: `5ADBE31D3DA9EB59D3ED0939D8B5F5E4F7A4C0BAF9F2C988C2A136842B088335`.
- O pacote contém `UBS_Rapida.exe` e o backend empacotado, sem exigir Flutter ou Python instalados.
- Android e Web permanecem fora da entrega oficial. iOS não possui compatibilidade declarada.

O ZIP e seu arquivo `.sha256` permanecem fora da branch `main` e devem ser anexados à GitHub Release v0.1.0.

## Cadastro e SMTP

O cadastro de novo paciente exige confirmação por e-mail. O envio funciona quando o responsável configura localmente as variáveis SMTP em `backend/.env`. Esse arquivo é privado e ignorado pelo Git; nenhuma senha SMTP acompanha o GitHub ou o ZIP público.

Sem essa configuração privada, a avaliação deve usar as contas fictícias criadas pelo inicializador. Isso não é falha do fluxo de segurança: a confirmação de e-mail permanece ativa e não existe código fixo público.

## Segurança e limitações

A auditoria não encontrou `.env`, senha SMTP, token, banco SQLite real, backup, log, cache, testes ou ambiente virtual na distribuição. O teste do pacote criou seu banco exclusivamente em pasta temporária externa e removeu essa pasta ao terminar.

O projeto é acadêmico e utiliza somente dados fictícios. SQLite atende ao MVP, não a uma implantação institucional ampla. SMTP real, teste humano com leitor de tela no Windows e assinatura comercial do pacote estão fora desta validação.

## Situação da publicação

A validação local e o pacote foram aprovados. A publicação da tag e da GitHub Release não foi executada porque o comando `gh` não estava disponível. Após instalar o GitHub CLI e autenticar com `gh auth login`, é necessário validar novamente o commit final antes de criar a tag e a Release.
