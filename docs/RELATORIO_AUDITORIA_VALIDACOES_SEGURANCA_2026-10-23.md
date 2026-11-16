# Relatório de auditoria de validações, regras de negócio e segurança

> **REGISTRO HISTÓRICO — 23/10/2026:** este relatório preserva os resultados obtidos naquela data e não representa a versão final atual. Os resultados vigentes estão em `docs/07_testes/testes_e_resultados.md`: 232 testes de backend, 190 testes Flutter e `flutter analyze` sem ocorrências para a versão desktop Windows 0.1.0.

Data: 23/10/2026  
Projeto: UBS Rápida  
Ambiente: código local, API de teste e SQLite temporário isolado

## Conclusão executiva

PCD, gestante e lactante podem ser marcadas simultaneamente. As condições não são incompatíveis por definição e podem coexistir em situações reais. Todas começam pendentes e somente uma confirmação presencial individual feita pela Recepção pode afetar a fila. A prioridade de pessoa idosa é calculada exclusivamente pela data de nascimento.

Condições pendentes, rejeitadas ou retiradas não concedem prioridade. A fila usa, nesta ordem: risco, pessoa idosa, PCD confirmada, gestante confirmada, lactante confirmada e ordem de chegada, com ID como último desempate estável.

Foram reproduzidas e corrigidas quatro brechas localizadas:

1. Gravidade média — a confirmação de senha do cadastro era validada apenas no Flutter. A API agora exige `password_confirmation` e rejeita divergência.
2. Gravidade média — desmarcar uma condição pendente não alterava o estado atual. A API agora registra `retirada`, oculta a condição do estado atual e preserva todo o histórico.
3. Gravidade baixa — repetir exatamente a mesma confirmação da Recepção criava histórico e auditoria duplicados. A operação agora é idempotente e a auditoria inclui o perfil responsável.
4. Gravidade média — um horário legado cadastrado diretamente em feriado podia ser exibido e reservado. Calendário e reserva agora revalidam feriados no backend.

Não foi reproduzida brecha crítica ou alta no estado auditado. Isso não equivale a afirmar segurança absoluta.

## Matriz de validações

A matriz completa, com tela/rota, campo ou ação, validação esperada, cobertura de frontend e backend, resultado, gravidade e correção, está no Canvas `auditoria-validacoes-seguranca-2026-10-23.canvas.tsx` criado para esta auditoria.

## Itens verificados sem falha reproduzida

- Cadastro público cria somente `paciente`; parâmetros de perfil, hash ou prioridade administrativa não elevam privilégios.
- Nascimento futuro e anterior a 1900 é rejeitado; a fronteira de 60 anos considera mês e dia.
- Lista múltipla de condições é aceita; valores desconhecidos e tipos incorretos são rejeitados; duplicados são normalizados sem duplicar registros.
- Paciente, Enfermagem, Médico e Administrador não confirmam condições pela rota da Recepção.
- Condição pendente ou rejeitada não altera a fila; múltiplas condições não duplicam o paciente.
- Login inválido ou conta desativada não autentica; a mensagem não revela qual credencial falhou.
- Tokens ausente, vazio, malformado, expirado, adulterado, revogado e `alg:none` retornam 401.
- Perfil autenticado sem autorização retorna 403.
- Paciente acessa somente as próprias consultas; Médico acessa somente consultas atribuídas e triadas.
- Respostas de API não expõem hash de senha ou token interno.
- Agendamento revalida profissional, especialidade, vínculo, horário futuro, grade, bloqueio e ocupação.
- Segunda consulta ativa da mesma especialidade no mesmo dia é recusada conforme a regra documentada; especialidades diferentes continuam permitidas.
- Disputa pela mesma vaga, duplo envio, cancelamento em menos de 24 horas e reagendamento em menos de 12 horas são protegidos.
- Fluxo clínico respeita `agendado → em_espera → em_triagem → em_atendimento → concluido`.
- Check-in em outro dia ou duplicado, triagem sem check-in, início sem triagem, Médico incorreto, conclusão sem resumo ou repetida e falta antes de 15 minutos são recusados sem evento de sucesso.
- Escala de risco aceita somente `baixo`, `moderado`, `alto` e `muito_alto`, exibidos como Baixo, Moderado, Alto e Muito alto.
- Rotas antigas de alteração direta de status não estão publicadas.
- Auditoria de ações clínicas não inclui queixa, sinais vitais, observação, resumo, senha, token, CPF ou e-mail.
- Seed de demonstração é idempotente e a compatibilidade entre cenários mínimo/completo está coberta pela suíte.

## Correções e arquivos alterados nesta auditoria

- `backend/app/schemas/__init__.py` — confirmação de senha obrigatória no cadastro.
- `backend/app/main.py` — comparação de senha, retirada de condição pendente, preservação de histórico/auditoria e bloqueio de feriado.
- `backend/app/routes/staff.py` — confirmação idempotente, auditoria com perfil e omissão de condição retirada no estado atual.
- `backend/app/routes/admin.py` — condição retirada não aparece como condição atual nos detalhes.
- `frontend/lib/screens/auth_pages.dart` — envio de confirmação de senha e orientação visual solicitada.
- `backend/tests/test_integration.py` — contrato de cadastro atualizado.
- `backend/tests/test_auth_contract.py` — regressões de confirmação de senha e `alg:none`.
- `backend/tests/test_priority_validation.py` — regressões de retirada, histórico, idempotência e perfil da auditoria.
- `backend/tests/test_booking_flow.py` — regressão de vaga legada em feriado.
- `frontend/test/auth_responsive_test.dart` — regressão do texto de orientação.
- `docs/04_telas/cadastro/README.md`, `docs/05_banco_de_dados/estrutura_banco.md` e `docs/06_api/endpoints.md` — contrato atualizado.

Esses arquivos já continham alterações locais anteriores. Somente os trechos relacionados às falhas reproduzidas foram acrescentados; nenhum trabalho existente foi revertido.

## Testes e validação final

- Testes críticos iniciais: 51 aprovados.
- Novas regressões isoladas: 4 aprovadas.
- Suíte completa do backend, executada uma vez: 185 aprovados, 0 falhas de asserção e 1 erro de infraestrutura antes da execução de um caso, causado por permissão na pasta temporária global do `pytest` no Windows.
- Caso afetado pela infraestrutura, repetido isoladamente com `basetemp` exclusivo: 1 aprovado.
- Total funcional da suíte do backend: 186 casos aprovados, sem falha funcional remanescente.
- Flutter diretamente relacionado: 14 aprovados.
- `flutter analyze`: nenhum problema.
- `compileall`: aprovado.
- `git diff --check`: aprovado; somente avisos de futura conversão LF/CRLF, sem erro de whitespace.

O teste HTTP completo confirmou cadastro, login, catálogo, agendamento, check-in, triagem, início do atendimento, recusa de conclusão sem resumo, conclusão válida e consulta do resultado pelo paciente. Cancelamento, reagendamento, falta, concorrência, prioridade, permissões, auditoria e os cinco perfis também passaram em testes dedicados.

## Integridade do SQLite temporário

- `PRAGMA integrity_check`: `ok`.
- Violações de chave estrangeira: 0.
- CPFs duplicados: 0.
- E-mails duplicados: 0.
- Vagas ativas duplicadas: 0.
- Grades/horários duplicados: 0.
- Auditorias exatamente duplicadas: 0.
- Códigos temporários sem hash: 0.
- Senhas fora do formato BCrypt: 0.
- Rollback: aprovado.
- Seed executado duas vezes: contagens preservadas.

## Preservação e limitações

O `.env` manteve o mesmo tamanho, data e SHA-256 antes e depois. O SQLite real manteve o mesmo tamanho e data; o hash não pôde ser calculado porque o arquivo estava aberto por outro processo. Todos os testes e verificações de banco usaram arquivos temporários. Nenhum e-mail real foi enviado.

Não foram executados: suíte Flutter completa (a alteração foi localizada e os testes diretamente relacionados passaram), teste manual em dispositivo físico, pentest de uma implantação externa e auditoria online de CVEs de dependências. A execução HTTP foi feita com `TestClient` e banco temporário, não contra o processo local que mantinha o SQLite real aberto.

Conclusão técnica: a base auditada apresenta separação de perfis, validação
server-side e trilha de auditoria, com as quatro inconsistências reproduzidas
corrigidas. As limitações acima permanecem registradas; este relatório não
atribui nota nem representa garantia de “100% seguro”.

Não houve commit nem push.
