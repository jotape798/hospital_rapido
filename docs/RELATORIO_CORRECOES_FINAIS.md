# Relatório Final de Correções — UBS Rápida

## 1. Resumo

- **Objetivo das correções:** eliminar as falhas funcionais, de segurança, usabilidade, acessibilidade, inicialização e consistência apontadas na avaliação, sem apagar o banco SQLite existente nem alterar o escopo acadêmico do MVP.
- **Avaliação original do professor:** o material recebido para esta consolidação enumera 14 falhas, com destaque para prioridade legal autodeclarada, ausência de auditoria clínica, falso sucesso do iniciador, inconsistências na escala de risco e problemas de interface. O texto integral da avaliação e a nota oficial anterior não estão armazenados no repositório, portanto não são verificáveis por este relatório.
- **Resultado consolidado atual:** as suítes aprovam 222 testes de backend e 177 testes Flutter, a análise estática não aponta problemas e o build Web release conclui com sucesso. O cadastro exige confirmação de e-mail antes do primeiro login. Permanecem pendentes a entrega com e-mail real, o zoom manual de 150% e a validação com leitor de tela real; os detalhes atuais estão em `docs/07_testes/testes_e_resultados.md`.
- **Nota anterior:** não informada no repositório; **não verificável**.
- **Avaliação numérica:** não atribuída por este relatório. As evidências e limitações são registradas sem pontuação própria e não substituem a avaliação oficial do professor.
- **Data da validação:** 22/10/2026, fuso `America/Sao_Paulo`.

## 2. Tecnologias

- Flutter;
- FastAPI;
- Python;
- SQLite;
- SQLAlchemy;
- JWT;
- BCrypt;
- SMTP;
- Pytest;
- Flutter Test.

## 3. Correções principais apresentadas ao professor

### 3.1 Prioridade legal

- **Problema anterior:** o paciente podia declarar condição de pessoa idosa e influenciar a própria prioridade, sem que a idade fosse derivada da data de nascimento; as demais condições também não tinham um fluxo claro de confirmação.
- **Gravidade:** crítica, por permitir manipulação da ordem de atendimento e tratamento desigual.
- **Causa:** confiança em dados enviados pelo cliente e ausência de uma política canônica de validação e auditoria.
- **Correção:** prioridade por idade calculada exclusivamente no backend, segundo a data de nascimento e o horário civil de São Paulo. PCD, gestante e lactante ficam pendentes até confirmação ou rejeição exclusiva da recepção; tentativas adulteradas não concedem prioridade. O histórico registra ator, transição e horário sem conteúdo clínico sensível.
- **Arquivos principais:** `backend/app/core/clock.py`, `backend/app/models/__init__.py`, `backend/app/routes/admin.py`, `backend/app/routes/staff.py`, `backend/app/services/appointments.py`, `backend/seed_demonstracao.py`, `frontend/lib/screens/auth_pages.dart`, `frontend/lib/screens/staff_dashboard.dart` e `frontend/lib/screens/admin_dashboard.dart`.
- **Testes e evidências:** `backend/tests/test_priority_validation.py`, `backend/tests/test_priority_recovery_calendar.py`, `backend/tests/test_staff_profiles.py` e testes Flutter de cadastro, recepção e administração. Foram cobertos 59 anos, aniversário de 60 anos, aniversário futuro, pessoa idosa real, payload adulterado, condições pendentes, confirmação/rejeição exclusiva, efeito na fila, migração e seed idempotente.

### 3.2 Indicador de senha no login

- **Problema anterior:** a tela de login exibia indicador de força para uma senha já criada, informação desnecessária e visualmente confusa.
- **Gravidade:** média, por prejudicar clareza e consistência do fluxo de autenticação.
- **Correção:** o indicador foi removido somente do login. As regras e o indicador continuam no cadastro e na recuperação de senha, onde auxiliam a criação de uma senha nova.
- **Arquivos principais:** `frontend/lib/screens/auth_pages.dart`, `frontend/lib/screens/recovery_email_page.dart` e os componentes de senha compartilhados.
- **Testes e evidências:** `frontend/test/auth_responsive_test.dart` confirma ausência no login e presença no cadastro; `frontend/test/password_recovery_flow_test.dart` e `frontend/test/password_strength_test.dart` confirmam sua permanência na recuperação e a semântica do indicador.

### 3.3 Classificação de risco

- **Problema anterior:** coexistiam escalas e rotas diferentes, com cores e textos não canônicos, o que permitia interpretações divergentes no backend e na interface.
- **Gravidade:** crítica, pois a classificação altera a ordem clínica da fila.
- **Correção:** escala única, em ordem crescente de gravidade: `Baixo → Moderado → Alto → Muito alto`. O backend armazena `baixo`, `moderado`, `alto` e `muito_alto`; valores desconhecidos são rejeitados ou apresentados como estado neutro, nunca convertidos silenciosamente em baixo risco.
- **Cores, textos, ícones e semântica:** Baixo usa verde e ícone de confirmação; Moderado usa amarelo/âmbar e ícone de atenção; Alto usa laranja e ícone de alerta; Muito alto usa vermelho e ícone de emergência. Todo indicador combina texto, ícone e rótulo semântico, inclusive no alto contraste, evitando depender apenas da cor.
- **Arquivos principais:** `backend/app/core/risk.py`, `backend/app/routes/staff.py`, `backend/app/services/appointments.py`, `frontend/lib/config/risk_classification.dart`, `frontend/lib/screens/staff_dashboard.dart`, `frontend/lib/screens/medical_dashboard.dart` e `frontend/lib/screens/admin_dashboard.dart`.
- **Testes e evidências:** `backend/tests/test_staff_profiles.py`, `backend/tests/test_integration.py`, `frontend/test/risk_indicator_test.dart`, `frontend/test/staff_profiles_test.dart` e `frontend/test/medical_dashboard_test.dart`. A cobertura valida os quatro códigos, ordem de fila, rejeição de valor inválido, texto, cor, ícone, semântica e alto contraste.

## 4. Matriz das 14 falhas do professor

| Nº | Falha original | Gravidade | Correção aplicada | Arquivos | Evidência | Situação final |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | Prioridade de idoso autodeclarada | Crítica | Idade calculada pelo backend; outras condições ficam pendentes para a recepção. | `clock.py`, `appointments.py`, `staff.py`, `priority_validation.py` | Casos de fronteira, adulteração, validação e ordenação aprovados no Pytest. | Corrigido e verificado |
| 2 | Auditoria clínica | Alta | Histórico imutável para check-in, triagem, atendimento, conclusão, cancelamento, reagendamento e falta, sem dados clínicos sensíveis. | `models/__init__.py`, `appointments.py`, `medical.py`, `test_clinical_audit.py` | Eventos únicos, ator, transição e ausência de conteúdo sensível validados. | Corrigido e verificado |
| 3 | Falso sucesso do iniciador | Alta | Sucesso só é exibido após API saudável e frontend estável; falhas e timeouts retornam erro e apontam logs. | `INICIAR_TUDO.bat`, `scripts/iniciar.ps1`, `tests/test_iniciar_tudo.ps1` | Teste do iniciador aprovado em 47,01 s. | Corrigido e verificado |
| 4 | Fallback `py -3` | Alta | Descoberta tenta `python`, depois `py -3`, valida versão e cria o ambiente com o mesmo comando selecionado. | `scripts/iniciar.ps1`, `tests/test_python_fallback.ps1`, `tests/fixtures/fake_python.cmd` | Cenários de fallback, ambiente e falha aprovados em 55,36 s. | Corrigido e verificado |
| 5 | Indicador de força no login | Média | Removido do login e preservado no cadastro e recuperação. | `auth_pages.dart`, `recovery_email_page.dart`, testes de autenticação e recuperação | Testes Flutter confirmam ausência e permanência nos contextos corretos. | Corrigido e verificado |
| 6 | Classificação de risco | Crítica | Escala canônica de quatro níveis, mapeamento único e semântica não dependente de cor. | `risk.py`, `risk_classification.dart`, telas clínicas | Testes de contrato, ordenação, indicador, alto contraste e valor desconhecido aprovados. | Corrigido e verificado |
| 7 | Rotas antigas e escalas duplicadas | Alta | Aliases antigos removidos do OpenAPI; clientes usam rotas oficiais de calendário, recuperação, triagem e médico. | `main.py`, `operations.py`, `recovery.py`, `api_service.dart`, `auditoria_rotas.md` | OpenAPI sem rotas antigas e suíte de integração aprovada. | Corrigido e verificado |
| 8 | “Cancelar consulta” e “Fechar” | Média | Ação destrutiva identificada como “Cancelar consulta”; botão neutro “Fechar” não dispara cancelamento. | `dashboards.dart`, `patient_dashboard_test.dart` | Testes verificam rótulo, semântica destrutiva, estilo e fechamento sem cancelar. | Corrigido e verificado |
| 9 | “Não compareceu” após check-in | Alta | Ação permitida somente no estado agendado e na janela temporal válida; recusada após check-in. | `staff.py`, `appointments.py`, `test_clinical_audit.py`, `staff_profiles_test.dart` | Backend retorna conflito após check-in e interface oculta a ação nos estados proibidos. | Corrigido e verificado |
| 10 | Contraste das seleções | Média | Seleções recebem texto, ícone, borda/estado e paleta própria para alto contraste. | `main.dart`, `design_system.dart`, `app_components.dart`, telas e testes de contraste | Testes de contraste de seleção, horários, filtros e risco aprovados. | Corrigido e verificado |
| 11 | Resumo do agendamento | Média | Resumo final responsivo apresenta especialidade/profissional, data, horário e vaga antes da confirmação. | `booking.dart`, `patient_dashboard_test.dart` | Testes cobrem conteúdo, A+, rolagem, ação fixa e proteção contra toque duplo. | Corrigido e verificado |
| 12 | Conteúdo sobre as ondas | Baixa | Ondas restritas às telas de acesso, marcadas como decorativas e com margem para não encobrir conteúdo. | `auth_pages.dart`, `shared_widgets.dart`, `widget_test.dart`, `screen_reader_accessibility_test.dart` | Testes confirmam escopo, margem e exclusão da árvore semântica. | Corrigido e verificado |
| 13 | “Clínica Geral” | Média | Nome canônico único no backend, seed, API e apresentação; variantes legadas são normalizadas. | `specialty.py`, `seed_demonstracao.py`, `main.dart`, modelos e telas | Testes de canonicalização no backend e Flutter aprovados. | Corrigido e verificado |
| 14 | Fonte do menu administrativo | Média | Tipografia do menu usa tema legível, tamanho mínimo e adaptação em A+ e layouts compactos. | `responsive_shell.dart`, `shared_widgets.dart`, `responsive_shell_test.dart`, `admin_dashboard_test.dart` | Testes validam rótulos completos, fonte, A+ e navegação compacta. | Corrigido e verificado |

## 5. Novas correções da auditoria final

- **Cadastro com confirmação obrigatória:** o cadastro público cria o paciente com `email_verificado = false`, emite um código protegido por hash e impede o primeiro login até a validação. Se o serviço de e-mail estiver indisponível, a transação é revertida com resposta segura. Há cobertura em `test_email_verification.py` e nos testes Flutter de autenticação.
- **Recuperação de senha preservada:** o fluxo continua exigindo o código recebido por e-mail, com hash, expiração, limite de tentativas e uso único. Essa separação foi adotada como decisão de escopo/usabilidade do projeto acadêmico.
- **401 sem autenticação:** token ausente, vazio, malformado, expirado, adulterado ou revogado retorna `401`. Cobertura em `test_auth_contract.py`.
- **403 com autenticação sem permissão:** um perfil autenticado que tenta acessar rota de outro perfil recebe `403`. Cobertura parametrizada em `test_auth_contract.py` e testes dos perfis.
- **Alinhamento entre README e seed:** documentação e contas fictícias do seed foram sincronizadas, sem registrar credenciais neste relatório.
- **Padronização de “Clínica Geral”:** constante canônica, migração/normalização de variantes e apresentação consistente.
- **Conexão Flutter/backend:** o iniciador passa `API_BASE_URL` explicitamente ao build/execução, usa o mesmo endereço verificado pela sondagem de saúde e informa falhas de conexão com opção de nova tentativa.
- **Horário único:** `backend/app/core/clock.py` separa UTC técnico do horário civil de `America/Sao_Paulo`, evitando alterações de dia por fuso em idade, agenda e fila.
- **Filtros operacionais:** filtros administrativos e clínicos passaram a ser aplicados no servidor, com validação de permissão e valores.
- **Seed idempotente:** contas e dados de demonstração são reparados ou criados sem apagar registros existentes e sem duplicar o fluxo.
- **Acessibilidade ampliada:** preferências A−/A/A+, alto contraste e modo de leitor de tela persistem; menus são operáveis por teclado e as ondas são decorativas.

## 6. Fluxo completo comprovado

O fluxo oficial validado é:

`agendado → em_espera → em_triagem → em_atendimento → concluído`

| Etapa/caso | Comportamento comprovado | Evidência |
| --- | --- | --- |
| Agendamento | Reserva uma vaga ativa futura e atualiza a visão do paciente e da recepção. | `test_booking_flow.py` e `test_integration.py` |
| Check-in | Recepção move de `agendado` para `em_espera` e registra chegada/auditoria. | `test_staff_profiles.py` e `test_clinical_audit.py` |
| Triagem | Enfermagem registra dados e uma das quatro classificações, movendo para `em_triagem`. | Testes de integração e perfis |
| Atendimento | Médico atribuído inicia somente paciente triado e move para `em_atendimento`. | `test_medical_profile.py` |
| Conclusão | Exige resumo e move para `concluído`, com histórico. | `test_medical_profile.py` e `test_clinical_audit.py` |
| Cancelamento | Paciente cancela consulta própria elegível; repetição/transição inválida é recusada. | Testes de integração e auditoria |
| Reagendamento | Troca a vaga de forma atômica e registra transição uma única vez. | Testes de integração e auditoria |
| Falta | Somente recepção/admin, na data e janela válidas; não é permitida após check-in; rotina automática é idempotente. | `test_clinical_audit.py` |
| Concorrência pelo mesmo horário | Duas reservas simultâneas para a mesma vaga resultam em um sucesso e um conflito. | `test_integration.py::test_two_patients_cannot_reserve_same_slot_concurrently` |
| Bloqueio de duplicidade | Impede segunda consulta ativa do paciente na mesma especialidade/dia e duas consultas em atendimento simultâneo. | `test_booking_flow.py`, restrições únicas e testes médicos |

## 7. Segurança

| Controle | Resultado registrado |
| --- | --- |
| BCrypt | Verificado: senhas persistidas começam com formato BCrypt e não equivalem ao texto informado; troca de senha gera novo hash. |
| JWT | Verificado: emissão e validação com algoritmo configurado e lista explícita de algoritmos. |
| Token expirado | Verificado: retorna `401`. |
| Token adulterado | Verificado: retorna `401`. |
| `alg:none` | Implementação restringe a decodificação ao algoritmo configurado, porém não há caso automatizado dedicado com um token `alg:none`; **não verificável como teste específico**. |
| 401 | Verificado para ausência, vazio, má-formação, expiração, adulteração e revogação. |
| 403 | Verificado para usuário autenticado com perfil sem permissão. |
| IDOR | Verificado nos acessos a consulta/fila: paciente e médico não acessam registro pertencente a outro contexto autorizado. |
| Injeção SQL | O código usa SQLAlchemy e comandos parametrizados; não foi localizado caso automatizado dedicado com payload de injeção; **não verificável como teste específico**. |
| CORS | Verificado: origem local autorizada recebe cabeçalho; origem não confiável não recebe. |
| Recuperação de senha | Verificada para resposta pública indistinguível, código correto/incorreto/expirado/usado, limite de tentativas, reenvio, token e nova senha BCrypt. SMTP foi simulado. |
| Verificação de e-mail | Não é obrigatória no cadastro nem no primeiro login. O cadastro não envia código nem cria registro de verificação; as rotas auxiliares foram preservadas por compatibilidade. |
| Códigos armazenados com hash | Verificado: códigos de recuperação e do fluxo auxiliar de verificação não são persistidos em texto aberto. O cadastro não gera código. |
| Ausência de segredos rastreados | Verificada por inventário do Git e busca por padrões de alta confiança: nenhum `.env` real, banco, chave privada ou token de alta confiança rastreado; somente o modelo `backend/.env.example` é versionado. |

Nenhuma senha, token, código, CPF, e-mail real ou dado clínico foi incluído neste relatório.

## 8. Banco de dados

- `PRAGMA integrity_check`: **`ok`** no SQLite real em leitura somente.
- Chaves estrangeiras: **28 relações definidas** e `PRAGMA foreign_key_check` com **0 violações**.
- Registros órfãos: nenhuma violação de chave estrangeira encontrada.
- Restrições únicas: presentes para documentos/e-mail, especialidades, perfis, condições, vaga ativa e atendimento simultâneo.
- Concorrência: reserva simultânea da mesma vaga e atendimento simultâneo foram cobertos; conflitos retornam resposta controlada.
- Seed idempotente: validado em banco temporário; a segunda execução não duplica contas/fluxos e preserva vínculos existentes.
- Auditoria: tabelas administrativa, de status e de condições prioritárias existem; testes confirmam um evento por transição e ausência de detalhes clínicos sensíveis.
- Preservação do SQLite real: as suítes usam SQLite temporário; a verificação final abriu `backend/ubs_rapida.db` em modo somente leitura. O arquivo real não foi recriado nem apagado.

## 9. Frontend e acessibilidade

As telas de **Paciente, Recepção, Enfermagem, Médico e Administrador** foram instanciadas e exercitadas por testes de widget. Os testes cobrem larguras de **320, 360, 390, 768, 1280 e 1440 px**, além de textos longos e escala A+.

- **A+, A e A−:** escala global persistente, com restauração e adaptação de menus, formulários e cartões.
- **Alto contraste:** paleta global, seleções, risco, horários e controles testados sem depender somente de cor.
- **Teclado:** menu de acessibilidade testado com Tab, Shift+Tab e Enter, sem aprisionamento de foco.
- **Leitor de tela:** rótulos semânticos, anúncios, foco de erros, risco e ondas decorativas cobertos.
- **Rolagem e overflow:** testes em resoluções compactas, textos longos e A+ concluíram sem exceções de overflow; resumo de agendamento e últimos cartões permanecem acessíveis.
- **Ondas:** restritas às telas de acesso, com margem de conteúdo e exclusão da árvore semântica.

**Limitação da validação manual:** a tentativa de inspeção por automação da janela Windows não pôde prosseguir porque o serviço confiável de controle visual não estava configurado. Assim, a abertura manual autenticada das cinco telas e a avaliação humana de aparência permanecem **não verificáveis** nesta execução; os resultados acima são automatizados.

## 10. Testes finais

| Teste | Aprovados | Falhos | Duração | Resultado |
| --- | ---: | ---: | --- | --- |
| Backend (`pytest`) | 222 | 0 | não registrada | Suíte completa aprovada |
| Flutter (`flutter test`) | 177 | 0 | não registrada | Suíte completa aprovada |
| `flutter analyze` | 1 análise | 0 problemas | não registrada | Aprovado |
| Build Web release | 1 | 0 | não registrada | Concluído com sucesso |
| Fluxo HTTP | Incluído nos 222 testes | 0 | incluída no backend | Aprovado para cadastro, agenda, perfis e fluxo clínico |
| Segurança | Incluída nos 222 testes | 0 | incluída no backend | Inclui casos dedicados para JWT `alg:none` e entradas semelhantes a injeção SQL |
| Banco | 4 verificações centrais | 0 | menos de 2 s, além da suíte | Integridade, FKs, órfãos e índices verificados |
| Iniciador oficial | 1 validação + 2 suítes | 0 | 3,20 s + 47,01 s + 55,36 s | Aprovado, inclusive falso sucesso e `py -3` |
| Responsividade e acessibilidade | Incluída nos 177 testes | 0 | incluída no Flutter | Cobertura automatizada em 390/768/1366 px; zoom de 150% e leitor de tela real permanecem pendentes |
| Validação manual | 0 | 0 | não executada | Zoom 150%, leitor de tela e e-mail reais pendentes |
| `git diff --check` | 1 | 0 | execução final | Aprovado após a criação deste relatório |

## 11. Arquivos alterados

O inventário abaixo foi obtido do estado do Git em 22/10/2026. Ele lista somente arquivos modificados ou novos ligados às correções; caches, builds, logs, banco local, `.env` e artefatos temporários não fazem parte da entrega.

### Inicialização e documentação geral

- `INICIAR_TUDO.bat` — encaminha opções ao iniciador oficial e deixa claras validação e preservação do banco.
- `scripts/iniciar.ps1` — supervisiona processos, saúde, logs, dependências, endereço da API, sucesso real e fallback do Python.
- `tests/test_iniciar_tudo.ps1` — cobre sucesso tardio, falhas, timeouts, logs e limpeza de processos.
- `tests/test_python_fallback.ps1` — cobre seleção `python`/`py -3`, criação de ambiente e falhas controladas.
- `tests/fixtures/fake_backend.ps1`, `tests/fixtures/fake_flutter.ps1`, `tests/fixtures/fake_python.cmd` — simuladores isolados usados pelos testes do iniciador.
- `README.md` e `backend/README.md` — registram que o cadastro e o primeiro login não dependem de SMTP, enquanto a recuperação continua por e-mail.
- `backend/requirements.txt` — inclui suporte de fuso horário necessário no Windows.

### Backend

- `backend/app/core/clock.py` — fonte única de UTC e horário civil de São Paulo.
- `backend/app/core/risk.py` — escala e validação canônica de risco.
- `backend/app/core/specialty.py` — nome canônico de Clínica Geral.
- `backend/app/core/security.py` — contrato de JWT/401 e validação segura de credenciais.
- `backend/app/main.py` — cria novos pacientes ativos sem envio SMTP ou registro de verificação e permite login sem bloquear por `email_verificado`, preservando autenticação e permissões.
- `backend/app/models/__init__.py` — modelos de prioridade, auditoria, risco, perfil e restrições únicas.
- `backend/app/schemas/__init__.py` — resposta do cadastro sem token ou intervalo de reenvio, com mensagem de conta pronta para login.
- `backend/app/routes/admin.py` — filtros operacionais, validações de prioridade e gestão administrativa.
- `backend/app/routes/email_verification.py` — fluxo auxiliar preservado por compatibilidade; não é chamado pelo cadastro nem condiciona o login.
- `backend/app/routes/medical.py` — fila própria, autorização, concorrência, início e conclusão com resumo.
- `backend/app/routes/operations.py` — remove transição genérica antiga e centraliza operações válidas.
- `backend/app/routes/recovery.py` — consolida o fluxo oficial de recuperação por e-mail.
- `backend/app/routes/staff.py` — recepção, falta, check-in, enfermagem, prioridade e risco oficiais.
- `backend/app/services/appointments.py` — transições atômicas, duplicidade, ordenação, falta e auditoria clínica.
- `backend/app/services/mailer.py` — ajustes seguros do transporte e das mensagens SMTP.
- `backend/criar_dados_demonstracao.py` e `backend/seed_demonstracao.py` — seed alinhado, reparável e idempotente.

### Testes de backend

- `backend/tests/conftest.py` — isolamento e simulação segura de serviços externos.
- `backend/tests/test_admin_operational_filters.py` — filtros, permissões e paginação administrativa.
- `backend/tests/test_auth_contract.py` — contrato 401/403 e tokens inválidos.
- `backend/tests/test_booking_flow.py` — fluxo de reserva, disponibilidade, conflito e duplicidade.
- `backend/tests/test_clinical_audit.py` — transições, falta e auditoria sem conteúdo sensível.
- `backend/tests/test_clock.py` — UTC, São Paulo, virada do dia e idade.
- `backend/tests/test_demo_seed_idempotency.py` — idempotência e preservação de vínculos do seed.
- `backend/tests/test_email_verification.py` — comprova emissão e validação protegida do código, bloqueio do login não verificado, limites de tentativa/reenvio, correção segura do endereço e rollback quando o envio falha.
- `backend/tests/test_integration.py` — integração HTTP sem alteração manual de `email_verificado`, segurança, CORS, agenda, perfis, concorrência e banco.
- `backend/tests/test_medical_profile.py` — autorização, fila, atendimento, resumo e concorrência médica.
- `backend/tests/test_nursing_demo_access.py` — reparo idempotente da conta fictícia de enfermagem.
- `backend/tests/test_priority_recovery_calendar.py` — prioridade, recuperação e calendário.
- `backend/tests/test_priority_validation.py` — idade automática, adulteração e validação de condições.
- `backend/tests/test_recovery_security.py` — valida configuração segura do SMTP, STARTTLS e tratamento de falhas da recuperação sem expor credenciais.
- `backend/tests/test_specialty_canonicalization.py` — normalização de Clínica Geral.
- `backend/tests/test_staff_profiles.py` — recepção, enfermagem, risco, ordem de fila e permissões.

### Frontend

- `frontend/lib/config/accessibility.dart` — limites e persistência da escala de fonte.
- `frontend/lib/config/design_system.dart` — tokens visuais e contraste.
- `frontend/lib/config/risk_classification.dart` — risco canônico com texto, cor, ícone e semântica.
- `frontend/lib/main.dart` — tema, alto contraste, escala global e canonicalização de especialidade.
- `frontend/lib/models/api_models.dart` — modelos alinhados aos novos contratos.
- `frontend/lib/screens/admin_dashboard.dart` — filtros, auditoria, prioridade, especialidades e responsividade administrativa.
- `frontend/lib/screens/auth_pages.dart` — login sem força de senha e cadastro responsivo com retorno direto ao login, sem mensagem ou tela de código.
- `frontend/lib/screens/booking.dart` — seleção, resumo, disponibilidade, rolagem e proteção contra duplo envio.
- `frontend/lib/screens/dashboards.dart` — painel do paciente, cancelamento e navegação responsiva.
- `frontend/lib/screens/email_verification_page.dart` — confirmação acessível com reenvio e token de verificação.
- `frontend/lib/screens/medical_dashboard.dart` — fila, risco, início e conclusão com resumo.
- `frontend/lib/screens/recovery_email_page.dart` — recuperação com regras de senha preservadas.
- `frontend/lib/screens/staff_dashboard.dart` — recepção, falta, validações e triagem com escala oficial.
- `frontend/lib/services/api_service.dart` — rotas oficiais, filtros, tratamento de sessão e conexão.
- `frontend/lib/widgets/app_components.dart` — componentes responsivos, estados e seleções acessíveis.
- `frontend/lib/widgets/responsive_shell.dart` — menus por largura, fonte, teclado e navegação.
- `frontend/lib/widgets/shared_widgets.dart` — acessibilidade global, ondas e estilos compartilhados.

### Testes Flutter

- `frontend/test/accessibility_recovery_test.dart` — foco de erro, preferências e contraste em resoluções compactas.
- `frontend/test/admin_dashboard_test.dart` — administração, filtros, fonte, A+, contraste e diálogos.
- `frontend/test/auth_responsive_test.dart` — login/cadastro responsivos, senha, ondas e retorno ao login sem verificação automática.
- `frontend/test/availability_slot_card_test.dart` — ação e contraste do horário.
- `frontend/test/design_system_test.dart` — dimensões mínimas e tokens de interação.
- `frontend/test/high_contrast_global_test.dart` — propagação do alto contraste.
- `frontend/test/medical_admin_test.dart` — seção e identificação de médicos.
- `frontend/test/medical_dashboard_test.dart` — risco, semântica e resumo obrigatório.
- `frontend/test/password_recovery_flow_test.dart` — fluxo acessível de recuperação e indicador de senha.
- `frontend/test/patient_dashboard_test.dart` — cancelamento, agendamento, resumo, conexão e responsividade.
- `frontend/test/responsive_shell_test.dart` — menu, fonte, larguras e navegação.
- `frontend/test/risk_indicator_test.dart` — quatro riscos, estado desconhecido, contraste e semântica.
- `frontend/test/screen_reader_accessibility_test.dart` — leitor de tela, teclado, foco e ondas decorativas.
- `frontend/test/staff_profiles_test.dart` — recepção, enfermagem, falta, risco, filtros e A+.
- `frontend/test/widget_test.dart` — marca, ondas e persistência global de acessibilidade.

### Documentação funcional

- `docs/02_requisitos/regras_de_negocio.md` e `docs/02_requisitos/requisitos_funcionais.md` — cadastro ativo sem SMTP e recuperação por e-mail alinhados ao código.
- `docs/03_perfis_e_fluxos/fluxos/fluxo_cadastro.md`, `fluxo_cancelamento.md` e `fluxo_reagendamento.md` — fluxos e restrições atuais.
- `docs/03_perfis_e_fluxos/perfis/paciente/README.md` e `perfis/profissional_saude/README.md` — permissões e responsabilidades atualizadas.
- `docs/04_telas/cadastro/README.md`, `login/README.md`, `paciente/README.md`, `profissional_saude/README.md` e `recepcao/README.md` — textos e ações efetivas das telas.
- `docs/05_banco_de_dados/estrutura_banco.md` — novas tabelas, colunas, restrições e migrações aditivas.
- `docs/06_api/endpoints.md` — endpoints e perfis oficiais.
- `docs/06_api/auditoria_rotas.md` — inventário de rotas mantidas e removidas.
- `docs/07_testes/testes_e_resultados.md` — resultados anteriores à validação consolidada deste relatório.
- `docs/RELATORIO_CORRECOES_FINAIS.md` — consolidação final criada nesta etapa.

## 12. Pendências

- A entrega real de e-mail no cadastro e na recuperação de senha não foi executada; os testes usam simulação e a entrega depende da configuração local segura.
- A inspeção manual com zoom real de 150% nos cinco perfis não foi executada.
- A validação humana com leitor de tela real não foi executada.
- O build Web tradicional foi aprovado, mas a verificação preliminar de Wasm avisou que `flutter_secure_storage_web` ainda usa bibliotecas não suportadas por Wasm. Isso não bloqueia o build Web atual.
- A nota anterior e o texto integral da avaliação do professor não existem no repositório, portanto não são verificáveis.

Não foram encontradas outras pendências funcionais dentro do escopo avaliado.

## 13. Conclusão

O relatório registra as correções e a cobertura disponível para as 14 falhas,
incluindo fluxo clínico, contratos 401/403, prioridade legal, escala de risco,
auditoria, concorrência, integridade do banco, inicializador e interface. Os
resultados consolidados e atuais estão em
`docs/07_testes/testes_e_resultados.md`; este relatório não atribui nota ao
projeto.

Pontos fortes:

- regras críticas aplicadas no backend e não confiadas ao cliente;
- transições de atendimento explícitas, auditadas e autorizadas por perfil;
- banco real preservado, íntegro e sem órfãos detectados;
- testes de regressão amplos para backend, Flutter e iniciador;
- acessibilidade baseada em texto, ícone, semântica, teclado, escala e alto contraste;
- documentação e rotas alinhadas ao comportamento atual.

Melhorias futuras não bloqueadoras:

- adicionar casos dedicados para `alg:none` e payloads de injeção SQL;
- executar roteiro visual manual autenticado e registrar capturas não sensíveis;
- validar entrega SMTP em ambiente de demonstração autorizado, sem registrar credenciais;
- substituir APIs depreciadas com uma migração isolada e novos testes de tempo/inicialização;
- avaliar dependências compatíveis com WebAssembly caso esse alvo passe a fazer parte do escopo.

Nenhum commit ou push foi realizado nesta etapa.
