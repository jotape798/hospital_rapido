# Auditoria de rotas funcionais

Levantamento realizado no backend, no Flutter, nos testes e na documentação antes da consolidação. “Removida” significa que a rota não integra mais o OpenAPI; os consumidores ativos usam a rota oficial indicada.

| Rota encontrada | Definição | Função | Uso encontrado | Situação | Decisão |
|---|---|---|---|---|---|
| `POST /auth/login` | `backend/app/main.py` | `login` | Flutter, testes e documentação | Oficial | Mantida |
| `POST /auth/register` | `backend/app/main.py` | `register` | Flutter, testes e documentação | Oficial | Mantida |
| `POST /patients/register` | `backend/app/main.py` | `register` | Testes e documentação antigos | Duplicada | Removida; consumidores usam `/auth/register` |
| `GET /auth/me` | `backend/app/main.py` | `me` | Testes e documentação | Oficial | Mantida |
| `GET /me` | `backend/app/main.py` | `me` | Sem uso no Flutter | Duplicada | Removida |
| `POST /auth/esqueci-senha` | `backend/app/routes/recovery.py` | `forgot_by_email` | Flutter e testes atuais | Oficial | Mantida |
| `POST /auth/validar-codigo-recuperacao` | `backend/app/routes/recovery.py` | `verify_email_recovery` | Flutter e testes atuais | Oficial | Mantida |
| `POST /auth/redefinir-senha` | `backend/app/routes/recovery.py` | `reset_email_password` | Flutter e testes atuais | Oficial | Mantida |
| `POST /auth/forgot-password` | `backend/app/routes/recovery.py` | `forgot` | Somente testes/documentação legados | Antiga | Removida com schemas exclusivos |
| `POST /auth/verify-recovery-code` e `/auth/recovery/verify` | `backend/app/routes/recovery.py` | `verify` | Somente testes/documentação legados | Duplicadas | Removidas |
| `POST /auth/reset-password` e `/auth/recovery/reset` | `backend/app/routes/recovery.py` | `reset` | Somente testes/documentação legados | Duplicadas | Removidas |
| `GET /availability/calendar-dates` | `backend/app/main.py` | `calendar_dates` | Flutter e testes atuais | Oficial | Mantida |
| `GET /availability/calendar-times` | `backend/app/main.py` | `calendar_times` | Flutter e testes atuais | Oficial | Mantida |
| `GET /available-slots` e `/appointments/available` | `backend/app/main.py` | `available` | Método Flutter sem tela ativa e testes antigos | Duplicadas | Removidas |
| `GET /availability/dates` e `/availability/times` | `backend/app/main.py` | `available_dates`, `available_times` | Documentação/testes antigos | Antigas | Removidas |
| `GET /appointments/me` | `backend/app/main.py` | `patient_appointments` | Dashboard Flutter e testes | Oficial | Mantida |
| `GET /appointments` | `backend/app/main.py` | `appointments` | Sem uso no Flutter atual | Duplicada | Removida; cada perfil usa sua fila oficial |
| `POST /appointments` | `backend/app/main.py` | `create_appointment` | Agendamento Flutter e testes | Oficial | Mantida |
| `POST /appointments/{id}/cancel` | `backend/app/main.py` | `cancel` | Flutter e testes | Oficial | Mantida; alias `PUT` removido |
| `POST /appointments/{id}/reschedule` | `backend/app/main.py` | `reschedule` | Flutter e testes | Oficial | Mantida; alias `PUT` removido |
| `PATCH /recepcao/agendamentos/{id}/check-in` | `backend/app/routes/staff.py` | `reception_check_in` | Painéis da recepção e administração, testes e documentação | Oficial | Mantida como rota única; alias administrativo removido |
| `PATCH /enfermagem/agendamentos/{id}/classificacao-risco` | `backend/app/routes/staff.py` | `classify_risk` | Painel da enfermagem e testes | Oficial | Mantida com escala única |
| `PUT /appointments/{id}/status` | `backend/app/routes/operations.py` | `change_status` | Apenas painel legado inacessível e testes antigos | Antiga | Removida; misturava transição e escala por cores |
| `GET /queue` | `backend/app/main.py` | `queue` | Painel administrativo e testes de prioridade | Oficial | Mantida para visão operacional geral |
| `GET /enfermagem/fila` | `backend/app/routes/staff.py` | `nursing_queue` | Painel da enfermagem | Oficial | Mantida para triagem |
| `GET /medico/fila` | `backend/app/routes/medical.py` | `medical_queue` | Painel médico e testes | Oficial | Mantida para atendimento médico |
| `GET/PATCH /profissional/*` | `backend/app/routes/staff.py` | fila, detalhes e transições legadas | Painel antigo inacessível pelo roteamento atual | Antigas | Removidas; consumidores usam `/medico/*` |
| `PATCH /medico/atendimentos/{id}/iniciar` | `backend/app/routes/medical.py` | `start_medical_care` | Painel médico e testes | Oficial | Mantida |
| `PATCH /medico/atendimentos/{id}/concluir` | `backend/app/routes/medical.py` | `complete_medical_care` | Painel médico e testes | Oficial | Mantida |

## Escala oficial

API e SQLite armazenam somente `muito_alto`, `alto`, `moderado` e `baixo`, nessa ordem de gravidade. Rótulos e cores são apresentação: vermelho, laranja, amarelo e verde, respectivamente. A definição canônica do backend fica em `backend/app/core/risk.py`; a definição da interface fica em `frontend/lib/config/risk_classification.dart`.
