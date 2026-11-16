# Requisitos funcionais

- RF01 — cadastrar paciente com validação de identidade, contato, senha e responsável quando menor;
- RF02 — concluir o cadastro com conta ativa, confirmar o e-mail por código temporário e então permitir o primeiro login por CPF e senha;
- RF03 — autenticar por CPF e senha e direcionar conforme o perfil retornado;
- RF04 — permitir recuperação e alteração de senha com código temporário;
- RF05 — listar especialidades, profissionais, datas e horários disponíveis;
- RF06 — criar, consultar, cancelar e reagendar consultas do próprio paciente;
- RF07 — permitir à recepção pesquisar a agenda do dia, confirmar chegada e registrar ausência;
- RF08 — permitir à enfermagem autorizada visualizar a fila e registrar/revisar queixa, sinais vitais e classificação manual de risco;
- RF09 — permitir ao profissional chamar, iniciar e concluir somente atendimentos atribuídos a ele;
- RF10 — permitir ao administrador gerenciar usuários internos, especialidades, grades, bloqueios, agenda e auditoria;
- RF11 — registrar mudanças de status e ações administrativas relevantes;
- RF12 — manter contas fictícias de demonstração sem duplicá-las.

## Decisão de escopo sobre painel público

Uma versão histórica da documentação cita painel público/TV como RF10, mas também o declara fora do escopo. Para eliminar a inconsistência, prevalece a delimitação do MVP: **não há painel público, senha pública ou chamador de TV nesta entrega**. O item fica registrado somente como melhoria futura.
