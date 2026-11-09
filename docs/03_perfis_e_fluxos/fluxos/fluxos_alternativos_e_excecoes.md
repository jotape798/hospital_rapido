# Fluxos alternativos e exceções

Cada item informa código, nome, gatilho, passos e destino. Os códigos são documentais e não alteram as rotas da aplicação.

## Paciente

### ALT-PAC-01 — Cadastro de menor

- **Gatilho:** nascimento indica idade inferior a 18 anos.
- **Passos:** (1) o sistema calcula a idade completa; (2) inclui **Responsável legal**; (3) exige e valida nome, CPF, nascimento, parentesco, telefone e e-mail; (4) vincula ou reutiliza o responsável pela associação `pacientes_responsaveis`.
- **Retorno/encerramento:** retorna ao cadastro e segue para a confirmação obrigatória do e-mail.

### ALT-PAC-02 — Corrigir e-mail pendente

- **Gatilho:** o paciente identifica erro no e-mail antes da confirmação.
- **Passos:** (1) informa novo endereço e o token de correção recebido no cadastro; (2) a API valida cadastro pendente e unicidade; (3) invalida códigos anteriores; (4) o paciente solicita novo código.
- **Retorno/encerramento:** retorna à confirmação de e-mail.

### ALT-PAC-03 — Reenviar código

- **Gatilho:** código de confirmação ou recuperação não foi recebido e já passaram 60 segundos.
- **Passos:** (1) solicita reenvio; (2) o sistema mantém resposta pública genérica; (3) invalida o código anterior quando gera outro; (4) reinicia a espera de 60 segundos.
- **Retorno/encerramento:** retorna à entrada do código.

### ALT-PAC-04 — Alterar seleção de vaga

- **Gatilho:** o paciente muda especialidade, profissional, data ou horário antes de confirmar.
- **Passos:** (1) altera a seleção; (2) escolhas dependentes incompatíveis são limpas; (3) o sistema recarrega disponibilidade; (4) apresenta novo resumo.
- **Retorno/encerramento:** retorna à confirmação do agendamento.

### ALT-PAC-05 — Desistir de cancelar ou reagendar

- **Gatilho:** o paciente fecha a confirmação antes do envio.
- **Passos:** (1) escolhe voltar/fechar; (2) confirma o descarte quando houver nova seleção; (3) nenhuma mutação é enviada à API.
- **Retorno/encerramento:** encerra a tentativa e preserva a consulta original.

### EX-PAC-01 — Cadastro inválido ou duplicado

- **Gatilho:** campo obrigatório inválido, CPF/e-mail duplicado, responsável inconsistente ou data futura.
- **Passos:** (1) backend rejeita com validação ou conflito; (2) não confirma a transação; (3) frontend associa a mensagem ao campo quando disponível.
- **Retorno/encerramento:** retorna ao cadastro para correção.

### EX-PAC-02 — Falha no envio da confirmação

- **Gatilho:** serviço de e-mail indisponível durante o cadastro.
- **Passos:** (1) o envio falha; (2) o backend faz rollback; (3) registra somente motivo técnico sem código, senha ou endereço; (4) responde erro seguro.
- **Retorno/encerramento:** cadastro não é concluído; o paciente tenta novamente mais tarde.

### EX-PAC-03 — Confirmação inválida

- **Gatilho:** código incorreto, vencido, usado ou com cinco tentativas consumidas.
- **Passos:** (1) a API rejeita sem devolver o código/hash; (2) mantém o login bloqueado; (3) orienta solicitar novo código.
- **Retorno/encerramento:** retorna ao reenvio/entrada do código.

### EX-PAC-04 — Credenciais inválidas ou e-mail não confirmado

- **Gatilho:** CPF/senha incorretos, conta inativa ou paciente ainda não confirmado.
- **Passos:** (1) a API não emite JWT; (2) usa mensagem segura; (3) o paciente corrige dados, confirma o e-mail ou recupera a senha.
- **Retorno/encerramento:** retorna ao login.

### EX-PAC-05 — Recuperação inválida ou indisponível

- **Gatilho:** código/token vencido, usado ou incorreto, limite atingido ou falha do serviço de e-mail.
- **Passos:** (1) a API rejeita sem revelar existência da conta ou detalhes internos; (2) não altera a senha; (3) permite nova solicitação conforme limites.
- **Retorno/encerramento:** retorna à recuperação ou encerra até o serviço voltar.

### EX-PAC-06 — Vaga indisponível ou duplicada

- **Gatilho:** horário foi ocupado, não há vaga ou já existe consulta ativa da mesma especialidade no dia.
- **Passos:** (1) o backend revalida; (2) rejeita a criação; (3) o frontend recarrega disponibilidade.
- **Retorno/encerramento:** retorna à escolha de vaga.

### EX-PAC-07 — Cancelamento/reagendamento bloqueado

- **Gatilho:** antecedência menor que 24 horas para cancelar, menor que 12 horas para reagendar, estado terminal ou nova vaga inválida.
- **Passos:** (1) a API rejeita; (2) preserva a consulta original; (3) informa o motivo aplicável.
- **Retorno/encerramento:** encerra a tentativa mantendo o agendamento.

## Recepção

### ALT-REC-01 — Refazer pesquisa

- **Gatilho:** consulta não aparece com os filtros atuais.
- **Passos:** (1) corrige nome/CPF, data, profissional, especialidade ou status; (2) aplica novamente; (3) a lista é substituída pelo resultado do backend.
- **Retorno/encerramento:** retorna à lista da Recepção.

### ALT-REC-02 — Rejeitar prioridade

- **Gatilho:** condição declarada não é confirmada presencialmente.
- **Passos:** (1) após check-in e ainda em espera, escolhe **Rejeitar**; (2) confirma; (3) backend altera somente condição `pendente`; (4) registra ator, consulta, resultado e histórico; (5) preserva a consulta.
- **Retorno/encerramento:** encerra a decisão e permanece nos detalhes.

### EX-REC-01 — Check-in ou falta incompatível

- **Gatilho:** consulta de outro dia/estado, chegada já registrada, falta duplicada ou menos de 15 minutos de atraso.
- **Passos:** (1) a API rejeita; (2) não altera horário/status; (3) mantém histórico sem evento duplicado.
- **Retorno/encerramento:** retorna à consulta para conferência ou espera.

### EX-REC-02 — Validação presencial bloqueada

- **Gatilho:** sem check-in, consulta fora de `em_espera`, condição inexistente ou não pendente.
- **Passos:** (1) frontend desabilita quando conhece o bloqueio; (2) chamada direta também recebe conflito; (3) nenhuma decisão é gravada.
- **Retorno/encerramento:** encerra preservando consulta e condição.

### EX-REC-03 — Decisões concorrentes

- **Gatilho:** duas validações tentam decidir a mesma condição pendente.
- **Passos:** (1) atualização condicional permite uma decisão; (2) a concorrente recebe conflito; (3) apenas um histórico e uma auditoria são criados.
- **Retorno/encerramento:** encerra com o estado do vencedor.

## Enfermagem

### ALT-ENF-01 — Reclassificar risco

- **Gatilho:** paciente permanece `em_triagem` e a avaliação precisa ser atualizada.
- **Passos:** (1) abre a triagem existente; (2) altera risco ou dados clínicos; (3) salva; (4) o registro único é atualizado com autoria/horário e auditoria.
- **Retorno/encerramento:** retorna à fila clínica atualizada.

### EX-ENF-01 — Triagem sem elegibilidade

- **Gatilho:** sem check-in, estado incompatível, perfil sem autorização ou outro paciente está primeiro na fila inicial.
- **Passos:** (1) a interface bloqueia quando possível; (2) a API revalida; (3) rejeita sem persistir triagem.
- **Retorno/encerramento:** retorna à etapa necessária ou aguarda o paciente anterior.

### EX-ENF-02 — Dados clínicos inválidos

- **Gatilho:** queixa/sinais vitais ausentes ou risco fora dos quatro códigos oficiais.
- **Passos:** (1) backend rejeita; (2) consulta não avança; (3) formulário mantém contexto para correção.
- **Retorno/encerramento:** retorna ao formulário de triagem.

## Médico

### EX-MED-01 — Paciente não elegível

- **Gatilho:** consulta não pertence ao médico, não foi triada ou não possui risco, queixa e sinais vitais completos.
- **Passos:** (1) item não entra na fila ou a rota rejeita; (2) atendimento não inicia; (3) fluxo volta à etapa clínica pendente.
- **Retorno/encerramento:** encerra sem alteração ou retorna à Enfermagem.

### EX-MED-02 — Atendimento concorrente ou resumo inválido

- **Gatilho:** paciente já está em outro atendimento ou resumo tem menos de três caracteres úteis.
- **Passos:** (1) backend aplica atualização condicional/validação; (2) rejeita conflito ou conclusão; (3) mantém o estado coerente.
- **Retorno/encerramento:** retorna à fila ou ao formulário do atendimento.

## Administrador

### ALT-ADM-01 — Filtrar operação e consultar auditoria

- **Gatilho:** administrador precisa restringir agenda/fila ou investigar uma ação.
- **Passos:** (1) escolhe módulo e filtros; (2) backend aplica os critérios; (3) consulta detalhes, validações e eventos; (4) pode limpar filtros sem alterar dados.
- **Retorno/encerramento:** permanece no módulo selecionado.

### EX-ADM-01 — Operação administrativa inválida

- **Gatilho:** identidade duplicada, especialidade/grade incompatível, usuário protegido ou período inválido.
- **Passos:** (1) backend valida permissões e integridade; (2) rejeita sem gravar parcialmente; (3) interface apresenta a mensagem segura.
- **Retorno/encerramento:** retorna ao formulário administrativo para correção.

## Falhas transversais

### EX-SIS-01 — Sessão inválida ou expirada

- **Gatilho:** JWT ausente, malformado, vencido, revogado, adulterado ou com algoritmo não permitido.
- **Passos:** (1) rota protegida responde 401 genérico; (2) não revela detalhes internos; (3) frontend encerra a sessão local.
- **Retorno/encerramento:** retorna ao login.

### EX-SIS-02 — Indisponibilidade temporária

- **Gatilho:** API, rede ou e-mail indisponível.
- **Passos:** (1) a ação mutável não é apresentada como concluída; (2) polling silencioso preserva o último estado válido; (3) operações de e-mail retornam mensagem segura; (4) usuário pode tentar novamente.
- **Retorno/encerramento:** retorna à tela atual ou encerra sem alteração.
