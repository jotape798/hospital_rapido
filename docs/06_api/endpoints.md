# Endpoints da API

Base local: `http://127.0.0.1:8000`. Rotas protegidas usam `Authorization: Bearer <JWT>`. A especificação executável permanece em `/docs`; este arquivo é um índice funcional do código atual.

## Saúde

- `GET /health` — confirma disponibilidade da API; público.

## Autenticação, cadastro e e-mail

- `POST /auth/login` — autentica CPF/senha e devolve JWT/perfil; público.
- `POST /auth/register` — cria somente paciente com conta ativa; público e independente de SMTP. Exige senha e confirmação coincidentes. Pessoa idosa é calculada exclusivamente pela data de nascimento; PCD, gestante e lactante entram como pendentes.
- `PATCH /patients/me/priority-conditions` — permite ao paciente declarar PCD, gestante ou lactante, sempre pendentes, e retirar autodeclarações ainda pendentes sem apagar o histórico; não aceita conceder prioridade de idoso ou definir estado de validação.
- `GET /auth/me` — dados da sessão; autenticado.
- `POST /auth/change-password` — troca a senha atual; autenticado.
- `POST /auth/email/solicitar-codigo` — envia código no fluxo auxiliar de confirmação.
- `POST /auth/email/reenviar-codigo` — invalida o anterior e reenvia no fluxo auxiliar.
- `POST /auth/email/corrigir` — troca o e-mail usando token temporário do fluxo auxiliar.
- `POST /auth/email/validar-codigo` — valida o código no fluxo auxiliar; não condiciona o cadastro nem o login.

## Recuperação de senha

- `POST /auth/esqueci-senha` — solicita código pelo e-mail sem revelar existência da conta; público.
- `POST /auth/validar-codigo-recuperacao` — valida código e emite token; público com código.
- `POST /auth/redefinir-senha` — define nova senha; público com token de recuperação.

## Paciente e agendamento

- `GET /patients/me` — perfil completo do próprio paciente; paciente.
- `GET /patients/me/summary` — próxima consulta e resumo; paciente.
- `GET /appointments/me` — consultas do próprio paciente; paciente.
- `GET /appointments/{id}` — detalhes da própria consulta; paciente.
- `POST /appointments` — agenda um slot livre; paciente.
- `POST /appointments/{id}/cancel` — cancela conforme prazo; paciente proprietário.
- `POST /appointments/{id}/reschedule` — troca horário conforme prazo; paciente proprietário.
- `GET /availability/calendar-dates` — datas do calendário com disponibilidade; paciente.
- `GET /availability/calendar-times` — estados/horários do calendário; paciente.

## Catálogo e agenda compartilhada

- `GET /specialties` — especialidades ativas; autenticado.
- `GET /professionals` — profissionais ativos, opcionalmente por especialidade; autenticado.
- `GET /queue` — fila presencial ordenada; recepção, enfermagem, profissional ou administrador.
- `GET /schedules` — todos os slots; administrador.
- `POST /schedules` — cria slot validado; administrador.
- `PUT /schedules/{id}` — altera slot desocupado; administrador.
- `PATCH /schedules/{id}/block` — bloqueia/desbloqueia slot; administrador.

## Recepção

- `GET /recepcao/resumo` — indicadores da data; recepção.
- `GET /recepcao/agendamentos` — agenda filtrada; recepção.
- `GET /recepcao/agendamentos/{id}` — detalhes com CPF mascarado; recepção.
- `PATCH /recepcao/agendamentos/{id}/check-in` — confirma chegada; recepção ou administrador.
- `PATCH /recepcao/agendamentos/{id}/nao-compareceu` — registra ausência; recepção.
- `PATCH /recepcao/agendamentos/{id}/condicoes/{condicao}/validacao` — confirma ou rejeita presencialmente PCD, gestante ou lactante e registra responsável/data; somente recepção.

Rotas compartilhadas administrativas:

- `GET /admin/appointments` — agenda diária; administrador, recepção ou profissional (profissional vê apenas as próprias).
- `POST /admin/appointments/{id}/absence` — registra falta; administrador ou recepção.
- `GET /admin/appointments/{id}` — detalhes; administrador, recepção ou profissional atribuído.

## Enfermagem

- `GET /enfermagem/resumo` — totais e riscos da data; enfermagem autorizada.
- `GET /enfermagem/fila` — fila filtrada e priorizada; enfermagem autorizada.
- `GET /enfermagem/agendamentos/{id}` — detalhes após check-in; enfermagem autorizada.
- `PATCH /enfermagem/agendamentos/{id}/classificacao-risco` — registra/revisa `level`, `complaint`, `vital_signs` e observação opcional; enfermagem autorizada.
- `level` aceita exclusivamente `muito_alto`, `alto`, `moderado` ou `baixo`.

## Profissional de saúde

- `GET /medico/fila` — consultas atribuídas com check-in e triagem concluídos; Médico.
- `GET /medico/atendimentos/{id}` — dados mínimos da própria consulta; Médico atribuído.
- `PATCH /medico/atendimentos/{id}/chamar` — registra a chamada do paciente triado; Médico atribuído.
- `PATCH /medico/atendimentos/{id}/iniciar` — inicia atendimento após validar triagem e exclusividade; Médico atribuído.
- `PATCH /medico/atendimentos/{id}/concluir` — exige resumo simples e conclui; mesmo Médico que iniciou.

## Administração

- `GET /admin/summary` — resumo da data; administrador.
- `GET /admin/users` — lista usuários internos com filtros; administrador.
- `GET/POST /admin/medicos` — lista/pesquisa e cria Médicos; administrador.
- `PUT /admin/medicos/{id}` — edita nome, CPF e situação; administrador.
- `POST /admin/medicos/{id}/activate|deactivate` — ativa ou desativa Médico; administrador.
- `PUT /admin/users/{id}` — edita usuário interno; administrador.
- `POST /admin/users/{id}/activate` — ativa; administrador.
- `POST /admin/users/{id}/deactivate` — desativa; administrador.
- `POST /admin/users/{id}/reset-access` — redefine senha e invalida tokens; administrador.
- `POST /admin/admins` — cria outro administrador com salvaguardas; administrador.
- `GET /admin/specialties` — lista inclusive inativas; administrador.
- `POST /admin/specialties` — cria; administrador.
- `PUT /admin/specialties/{id}` — renomeia; administrador.
- `POST /admin/specialties/{id}/{activate|deactivate}` — muda situação; administrador.
- `GET /admin/grids` — lista grades; administrador.
- `POST /admin/grids` — cria grade e slots; administrador.
- `DELETE /admin/grids/{id}` — desativa grade e bloqueia slots quando não há consulta vinculada; administrador.
- `POST /admin/blocks` — bloqueia período desocupado; administrador.
- `GET /admin/audit` — histórico administrativo; administrador.

## Implementação

- Aplicação e rotas centrais: `backend/app/main.py`;
- Rotas operacionais: `backend/app/routes/staff.py` e `operations.py`;
- Administração: `backend/app/routes/admin.py`;
- Recuperação e confirmação: `backend/app/routes/recovery.py` e `email_verification.py`.
