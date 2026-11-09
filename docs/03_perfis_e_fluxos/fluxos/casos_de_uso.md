# Casos de uso atuais

Este documento descreve o comportamento confirmado no backend, no Flutter e nos testes automatizados. As ramificações e falhas estão detalhadas em [Fluxos alternativos e exceções](fluxos_alternativos_e_excecoes.md).

## Perfis

- **Paciente:** cria e confirma a conta, declara condições prioritárias, agenda, acompanha, cancela ou reagenda consultas e recupera a senha.
- **Recepção:** pesquisa consultas, registra check-in ou ausência e decide presencialmente condições prioritárias pendentes.
- **Enfermagem:** consulta a fila clínica, registra triagem, classifica e reclassifica risco.
- **Médico:** acessa somente sua fila elegível, chama, inicia e conclui o atendimento com resumo.
- **Administrador:** acompanha indicadores, agenda e fila, gerencia contas, médicos, especialidades e grades e consulta auditoria.

## UC01 — Cadastrar e confirmar paciente

**Ator:** Paciente.

1. O paciente informa nome, CPF, nascimento, e-mail, telefone, senha e confirmação da senha.
2. Pode declarar PCD, gestação ou lactação; essas condições começam como `pendente`. A prioridade de pessoa idosa é calculada pela data de nascimento.
3. Para menor de 18 anos, o sistema inclui a etapa **Responsável legal** e exige nome, CPF, nascimento, parentesco, telefone e e-mail do responsável maior de idade.
4. Para adulto, dados de responsável eventualmente recebidos são descartados.
5. O backend valida e-mail/CPF únicos, grava hashes da senha e do código e envia um código de seis dígitos.
6. O paciente confirma o código em até 10 minutos, com no máximo cinco tentativas. O reenvio é permitido após 60 segundos.
7. Somente depois de `email_verificado=true` o login do paciente é liberado.

## UC02 — Autenticar usuário

**Ator:** qualquer perfil ativo.

1. O usuário informa CPF e senha.
2. O backend valida as credenciais e, para paciente, a confirmação do e-mail.
3. A API emite JWT assinado e permissões do perfil.
4. O Flutter abre o painel de Paciente, Recepção, Enfermagem, Médico ou Administrador.

## UC03 — Recuperar senha

**Ator:** usuário com e-mail cadastrado.

1. O usuário informa o e-mail; a resposta pública não revela se existe conta.
2. O sistema envia código de seis dígitos, armazenado como hash, válido por 10 minutos.
3. O código permite até cinco tentativas e o reenvio respeita 60 segundos.
4. Após a validação, a API emite token temporário específico para recuperação.
5. A nova senha é armazenada com BCrypt, o token é consumido e sessões anteriores são invalidadas.

## UC04 — Agendar consulta

**Ator:** Paciente com e-mail confirmado.

1. O paciente consulta especialidades, profissionais, datas e horários disponíveis.
2. Seleciona uma vaga e confirma.
3. O backend revalida disponibilidade e impede conflito de horário ou consulta ativa duplicada da mesma especialidade no dia.
4. A consulta é criada como `agendado` e aparece no acompanhamento do paciente.

## UC05 — Cancelar ou reagendar

**Ator:** Paciente proprietário da consulta.

- Cancelamento: exige consulta compatível e antecedência mínima de 24 horas; libera a vaga e muda o status para `cancelado`.
- Reagendamento: exige antecedência mínima de 12 horas na consulta original e na nova vaga; atualiza médico/horário e libera a vaga anterior.

## UC06 — Declarar e validar prioridade

**Atores:** Paciente e Recepção.

1. O paciente declara PCD, gestação ou lactação; a condição é gravada como `pendente` com histórico.
2. A Recepção realiza o check-in.
3. Enquanto a consulta está `em_espera`, a Recepção confirma ou rejeita uma única vez a condição pendente.
4. A decisão registra ator, data, consulta, resultado, histórico e auditoria.
5. Rejeitar a condição não cancela a consulta. Somente condições confirmadas alteram a prioridade legal; idade é calculada automaticamente.

## UC07 — Registrar check-in ou falta

**Ator:** Recepção; o Administrador também possui a rota oficial de ausência.

1. A equipe localiza uma consulta do dia em estado `agendado`.
2. No check-in, registra chegada e altera o estado para `em_espera`.
3. Sem chegada, após 15 minutos do horário, a falta pode ser registrada manualmente.
4. A verificação das filas/resumos também marca automaticamente faltas vencidas, de forma idempotente.
5. Mudanças ficam no histórico e na auditoria.

## UC08 — Triar e classificar risco

**Ator:** Enfermagem com perfil profissional ativo e autorização de triagem.

1. A Enfermagem consulta a fila ordenada por prioridade clínica/legal e chegada.
2. Somente o primeiro paciente ainda sem triagem pode iniciar a classificação.
3. Registra queixa, sinais vitais, observação opcional e um risco oficial: `muito_alto`, `alto`, `moderado` ou `baixo`.
4. A consulta passa para `em_triagem` e fica elegível à fila médica quando os dados obrigatórios estão completos.
5. Enquanto permanece em `em_triagem`, a Enfermagem pode reclassificar; autoria e horário são atualizados e a ação é auditada.

## UC09 — Atender paciente

**Ator:** Médico atribuído à consulta.

1. O Médico consulta sua fila com pacientes triados e dados clínicos obrigatórios.
2. Pode chamar o paciente e iniciar o atendimento, mudando o estado para `em_atendimento`.
3. Registra resumo com pelo menos três caracteres e conclui.
4. A conclusão grava médico responsável, resumo, horário e status `concluido`.

## UC10 — Acompanhar painéis

**Atores:** Paciente, Recepção, Enfermagem, Médico e Administrador.

- Paciente, Recepção, Enfermagem e Médico recebem atualização automática a cada cinco segundos enquanto a tela está montada.
- O Administrador atualiza periodicamente a fila quando essa seção está ativa.
- Atualizações silenciosas não apagam o último estado válido e não sobrepõem requisições em andamento.

## UC11 — Administrar a operação

**Ator:** Administrador.

1. Consulta resumo, agenda, fila, detalhes, validações prioritárias e auditoria.
2. Cria, altera, ativa ou desativa usuários internos e médicos; pode redefinir acesso sem expor hashes.
3. Gerencia especialidades, grades e bloqueios de agenda.
4. Pode registrar ausência pela rota autorizada.
5. Ações relevantes geram histórico ou evento de auditoria.
