# API UBS Rápida

FastAPI, SQLAlchemy, SQLite persistente, JWT e BCrypt. Consulte o [índice da API](../docs/06_api/endpoints.md), a [estrutura do banco](../docs/05_banco_de_dados/estrutura_banco.md) e os [resultados de testes](../docs/07_testes/testes_e_resultados.md).

As migrações são aditivas. Não apague `ubs_rapida.db`. Execute `setup_env.py` antes da primeira inicialização e mantenha a configuração local fora do controle de versão. O cadastro público é exclusivo para pacientes e exige a confirmação do endereço de e-mail antes do primeiro login. A recuperação de senha é liberada somente para contas com e-mail confirmado. Os códigos temporários são armazenados somente como hash, possuem expiração, limite de tentativas e uso único.

A documentação interativa fica em `http://127.0.0.1:8000/docs` quando a API está em execução.

## E-mail transacional

Use `backend/.env.example` apenas como referência para criar a configuração
local ignorada pelo Git. O transporte deve usar TLS e uma conta de teste
autorizada. Não coloque credenciais em código, documentação, logs ou arquivos
versionados.

Na validação manual, confirme separadamente o cadastro, a confirmação do
endereço, o primeiro login e a recuperação de senha. Os testes automatizados
simulam o serviço de e-mail e não enviam mensagens reais.

## Primeiro administrador

Execute somente quando ainda não existir administrador:

```powershell
cd C:\ubs_Hospital_rapido\backend
.\venv\Scripts\python.exe .\criar_admin_inicial.py
```

O cadastro público permanece exclusivo para pacientes. Recepcionistas, Enfermagem e Médicos são cadastrados pelo Painel Administrativo. Médicos usam as rotas `/medico/*`, acessam apenas a própria fila triada e concluem o atendimento com resumo obrigatório. O relatório original do painel foi preservado no [arquivo histórico](../docs/99_arquivo_historico/acervo_documentacao_projeto/PAINEL_ADMINISTRATIVO.md).

Os dados fictícios de demonstração são criados de forma idempotente. O seed preserva registros preexistentes e interrompe com erro claro se encontrar perfil ou credencial incompatível, sem substituir dados silenciosamente. As credenciais ficam restritas ao ambiente local de demonstração e não são documentadas aqui.

## Política de data e hora

O módulo `app/core/clock.py` é a única fonte de horário da aplicação. UTC
é a referência para autenticação, expirações, criação/atualização e
auditoria. Regras clínicas, idade, agendas e filas usam
`America/Sao_Paulo` independentemente do fuso do sistema operacional.

Por compatibilidade, o SQLite existente não é migrado: consultas, grades e
eventos clínicos continuam como horário civil de São Paulo sem `tzinfo`; campos
técnicos legados continuam como UTC sem `tzinfo`. A API mantém o contrato atual
e não acrescenta `Z` ou offset aos horários de agendamento. A dependência
`tzdata` fornece a base IANA no Windows.
