# Estrutura do banco de dados

## Banco ativo

- Caminho: `backend/ubs_rapida.db`;
- Tecnologia: SQLite acessado com SQLAlchemy;
- Integridade verificada em 06/10/2026: `PRAGMA integrity_check = ok`;
- A quantidade de tabelas evolui por migrações aditivas;
- Política: o banco local é ignorado pelo Git e não é apagado na inicialização.

As contagens variam com a demonstração. Nenhum valor de senha, token, código ou hash é reproduzido nesta documentação.

## Tabelas

### `usuarios`

Identidades de pacientes e equipe. PK `id`. Campos principais: `nome`, `cpf`, `cns`, `data_nascimento`, `email`, `email_verificado`, `telefone`, `senha_hash` — senha protegida com BCrypt, `perfil`, `ativo`, `token_version`, prioridade e dados legados de responsável. `criado_por` e `ultima_alteracao_por` referenciam logicamente usuários. Usada por todos os perfis.

`e_prioridade` é mantido por compatibilidade, mas não é fonte de verdade para pessoa idosa. A API calcula a idade completa a partir de `data_nascimento`.

Os campos legados de responsável em `usuarios` (`nome_responsavel`,
`cpf_responsavel`, `data_nascimento_responsavel`, `parentesco_responsavel`,
`outro_parentesco_responsavel`, `telefone_responsavel` e `email_responsavel`)
continuam preservados por compatibilidade. A fonte relacional é
`responsaveis` + `pacientes_responsaveis`. A remoção futura desses campos exige
migração específica, inventário dos bancos existentes, cópia de segurança e
validação de integridade.

### `condicoes_prioritarias`

Estado atual de PCD, gestante e lactante. Possui unicidade por paciente/condição, estado `pendente`, `confirmada`, `rejeitada` ou `retirada`, momento da declaração e, após validação presencial, usuário da recepção e data/hora. `retirada` preserva o histórico quando o paciente desmarca uma condição ainda pendente. Estados pendentes, rejeitados ou retirados não alteram a fila.

### `historico_condicoes_prioritarias`

Trilha imutável das declarações e decisões presenciais, com estado anterior/novo, responsável e data/hora. O administrador pode consultar; somente a recepção altera o estado atual pela rota protegida.

### `responsaveis`

Responsáveis legais reutilizáveis. PK `id`; campos `nome`, `cpf`, `telefone`, `email`. Usada no cadastro de pacientes menores.

### `pacientes_responsaveis`

Associação N:N. PK composta `paciente_id` + `responsavel_id`; FKs para `usuarios.id` e `responsaveis.id`; campo `parentesco`.

### `especialidades`

Catálogo administrável. PK `id`; `nome` único e `ativo`. Consultada por paciente, equipe e administrador.

### `perfis_profissionais`

Dados funcionais internos. PK `id`; FKs `usuario_id -> usuarios.id` e `especialidade_id -> especialidades.id`; `registro_profissional`, `autorizado_triagem`, `ativo`. Usada por administração, enfermagem e profissionais.

### `agendas_profissionais`

Slots disponíveis. PK `id`; FK `medico_id -> usuarios.id`; `data_horario`, `bloqueado`, `especialidade`. Há unicidade por profissional/horário. Usada em agendamento e administração.

### `consultas`

Agendamentos e estado presencial. PK `id`; FKs `paciente_id`, `medico_id` e `atendimento_medico_id` para `usuarios.id`; campos `especialidade`, `data_horario`, `status`, classificação, chegada, falta, triagem, chamada, início, conclusão e `resumo_atendimento`. `chegada_por` e `triagem_por` guardam usuários responsáveis, embora o SQLite atual não exponha FKs para todos os campos adicionados por migração. O índice parcial `uq_paciente_em_atendimento` impede dois atendimentos simultâneos do mesmo paciente quando os dados existentes permitem sua criação segura. Usada por todos os perfis.

### `historico_status_consultas`

Trilha de mudanças. PK `id`; FKs `consulta_id -> consultas.id` e `alterado_por -> usuarios.id`; `status_anterior`, `status_novo`, `criado_em`. Usada pelos fluxos operacionais e auditoria.

### `classificacoes_risco`

Triagem e classificação manual. PK `id`; FKs `consulta_id -> consultas.id` e `profissional_id -> usuarios.id`; `nivel_risco`, `queixa_principal`, `sinais_vitais`, `observacao`, `classificado_em`. Usada pela enfermagem e lida pelo Médico. `nivel_risco` e `consultas.classificacao_risco` armazenam exclusivamente `muito_alto`, `alto`, `moderado` ou `baixo`; cores são somente apresentação visual.

### `grades_atendimento`

Definição de períodos e geração de slots. PK `id`; FKs para profissional, especialidade e criador; data, início/fim, duração, capacidade, intervalo, situação e timestamps. Administrador.

### `bloqueios_agenda`

Bloqueios de períodos. PK `id`; FKs `profissional_id` e `criado_por` para `usuarios.id`; início, fim, motivo e criação. Administrador.

### `auditoria_administrativa`

Eventos administrativos. PK `id`; FK `usuario_id -> usuarios.id`; ação, tipo/id do registro, detalhes JSON e data. Administrador.

### `recuperacao_senha`

Solicitações temporárias. PK `id`; FK `usuario_id -> usuarios.id`; `codigo_hash`, validade, tentativas, indicadores de uso/verificação e criação. Usuário em recuperação; conteúdo sensível não deve ser exibido.

### `verificacoes_email`

Códigos de confirmação e correção segura do endereço. PK `id`; FK `usuario_id -> usuarios.id`; `codigo_hash`, `token_correcao_hash` opcional, validade, tentativas, uso e criação. Tanto o código quanto o token de correção são persistidos somente como hash.

### `limites_tentativas`

Controle de abuso. PK textual `key`; `attempts` e `expires_at`. Usada internamente pela API.

## Evolução

Não há Alembic. `backend/app/main.py` executa criação de tabelas e migrações aditivas/compatíveis no startup. Antes da primeira migração das validações prioritárias, o SQLite existente recebe uma cópia consistente em `backend/backups/`, diretório ignorado pelo Git. A rotina corrige falsos idosos, mantém quem tem 60 anos ou mais e converte PCD/gestante/lactante legados sem evidência em pendentes.

A migração da escala de risco também cria uma cópia única `ubs_rapida.pre-risk-scale.bak` antes de qualquer conversão. Ela converte `vermelho → muito_alto`, `laranja → alto`, `amarelo → moderado`, `verde → baixo` e o código intermediário `medio → moderado`, registra a quantidade atualizada e preserva códigos já oficiais. Ambas as rotinas são idempotentes e não recriam o banco.
