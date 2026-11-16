# O que foi feito no projeto UBS Rápida

## 1. Identificação

- **Projeto:** UBS Rápida.
- **Tipo:** projeto acadêmico.
- **Curso:** Análise e Desenvolvimento de Sistemas.
- **Versão oficial da entrega:** Windows desktop 0.1.0.
- **Versão Flutter/pubspec:** 0.1.0+2.
- **Data de consolidação:** 15/11/2026.
- **Tecnologias:** Flutter, Dart, FastAPI, Python, SQLite, SQLAlchemy, JWT e BCrypt.
- **Dados:** exclusivamente fictícios, criados para demonstração e testes acadêmicos.

## 2. Objetivo

O UBS Rápida é um MVP acadêmico criado para simular o cadastro de pacientes, o agendamento de consultas, a confirmação de chegada, a classificação de risco, a organização da fila, o atendimento e a auditoria do fluxo de uma Unidade Básica de Saúde.

O sistema não substitui sistemas oficiais do SUS, não constitui prontuário oficial e não foi implantado nem validado em uma UBS real.

## 3. Perfis implementados

- **Paciente:** realiza cadastro, confirma o e-mail, autentica-se, consulta horários, agenda, cancela e reagenda consultas, acompanha seus próprios registros e recebe os avisos aplicáveis à sua jornada.
- **Recepção:** confirma chegada, registra ausência quando permitida, valida ou rejeita presencialmente condições prioritárias declaradas e acompanha o fluxo operacional sob sua responsabilidade.
- **Enfermagem:** consulta a fila elegível, realiza a triagem e registra a classificação de risco respeitando a ordem determinada pelas regras do sistema.
- **Médico ou profissional de atendimento:** acessa apenas a agenda e a fila vinculadas ao próprio profissional, atende pacientes triados e conclui a consulta. Médicos e dentistas utilizam esse perfil com profissão e especialidade próprias.
- **Administrador:** gerencia usuários, profissionais, especialidades, grades e horários, consulta filtros administrativos e acompanha registros de auditoria.

## 4. Funcionalidades implementadas

O projeto implementa:

- cadastro de paciente com validação de CPF;
- cadastro de menor de idade com responsável legal;
- confirmação obrigatória de e-mail;
- login por CPF e senha;
- redirecionamento automático conforme o perfil devolvido pelo backend;
- recuperação de senha para conta com e-mail confirmado;
- agendamento, cancelamento, reagendamento e consulta de horários;
- check-in e registro de ausência;
- confirmação ou rejeição presencial de condição prioritária;
- identificação automática de pessoa idosa pela data de nascimento;
- prioridade para PCD, gestante e lactante após validação;
- classificação de risco, fila de atendimento e triagem;
- atendimento e conclusão de consulta;
- histórico de status e auditoria das mudanças relevantes;
- filtros administrativos;
- gestão de usuários, profissionais, especialidades, grades e horários;
- médicos, dentistas, recepcionistas e profissionais de enfermagem fictícios;
- agendas isoladas por profissional;
- recursos de acessibilidade, incluindo alto contraste, aumento e redução de fonte, responsividade e navegação por teclado;
- iniciador Windows e servidor Web independente;
- documentação interativa Swagger/OpenAPI.

## 5. Regras de negócio

A ordenação do atendimento considera primeiro a classificação de risco, depois a prioridade legal validada e, na ausência de prioridade superior, a ordem de chegada. A condição de pessoa idosa é calculada pela data de nascimento. PCD, gestante e lactante dependem de validação presencial: somente a Recepção pode confirmar ou rejeitar a condição declarada, e uma condição pendente não concede prioridade.

A triagem deve respeitar o primeiro paciente elegível e tentativas fora da ordem são bloqueadas. Cada perfil possui permissões separadas, e pacientes não podem acessar dados de outros pacientes. Ações administrativas e mudanças importantes preservam o responsável, a data, o estado anterior e o novo estado.

O check-in possui uma única rota oficial. O registro de ausência é bloqueado depois do check-in quando essa transição é incompatível com o estado atual da consulta.

## 6. Banco de dados

O MVP utiliza SQLite. Na versão auditada foram contabilizadas 17 tabelas e 28 relacionamentos de chave estrangeira. A evolução do esquema é feita por migrações aditivas, preservando a integridade referencial.

Há tabela própria para o histórico de status das consultas e tabela própria para o histórico de condições prioritárias. A classificação de risco é separada do agendamento. Todos os dados de demonstração são fictícios, e nenhum banco com dados de execução deve ser versionado.

## 7. Segurança

As senhas são protegidas com BCrypt. A autenticação usa JWT e a autorização é aplicada por perfil, com isolamento entre pacientes. O backend bloqueia token ausente, expirado, adulterado ou revogado e rejeita JWT com `alg:none`. O login possui testes contra SQL injection.

O arquivo `.env`, bancos, backups, chaves e credenciais locais permanecem fora do Git. Nenhum segredo real deve ser versionado. CPFs, e-mails e senhas eventualmente usados em contas de demonstração são dados sintéticos destinados exclusivamente ao ambiente acadêmico.

## 8. Correções solicitadas pelo professor

Foram implementadas ou corrigidas as seguintes solicitações:

- regra de prioridade legal e confirmação presencial de PCD, gestante e lactante;
- idade calculada pela data de nascimento;
- histórico das mudanças da consulta e histórico de condições prioritárias;
- classificação de risco separada do agendamento;
- correções no login e remoção do medidor de força de senha dessa tela;
- responsividade e iniciador Windows;
- tratamento correto de avisos do `pip`, uso de `--disable-pip-version-check` e fallback de Python no Windows;
- servidor Web independente;
- rota única de check-in;
- documentação dos perfis no Swagger;
- relógio central da UBS nos testes e remoção dos usos antigos de `datetime.utcnow()`;
- confirmação de e-mail obrigatória e recuperação somente para conta com e-mail confirmado;
- filtros de histórico e auditoria;
- avisos de prioridade ao paciente;
- testes de SQL injection e de JWT com `alg:none`;
- atualização do README e das contagens de testes;
- retirada da autoavaliação “9,2/10”;
- correção dos scripts PowerShell em UTF-8;
- inclusão de mais profissionais fictícios, diferenciação dos dentistas e isolamento das agendas.

## 9. Testes conhecidos

A última evidência conhecida registra:

- 232 testes backend aprovados;
- 190 testes Flutter aprovados;
- `flutter analyze` sem ocorrências;
- testes de segurança aprovados;
- testes do iniciador Windows aprovados;
- build Windows Release aprovado;
- pacote Windows testado fora da pasta do projeto;
- endpoint backend `/health` aprovado;
- Swagger aprovado;
- frontend aprovado;
- auditoria de segredos sem segredo real identificado.

> Esses resultados correspondem à auditoria final aprovada em 16/11/2026.

## 10. Situação das plataformas

### Windows desktop

- É a versão oficial da entrega.
- O pacote oficial é a versão 0.1.0.
- Foi validado para demonstração acadêmica na auditoria final.
- Não há declaração de publicação em produção.

### Android

- APK e AAB foram gerados.
- O package atual é `br.com.ubsrapida.app`.
- A migração da `MainActivity` foi realizada.
- Não houve validação final em aparelho físico.
- O aplicativo de celular não funciona de forma confirmada.
- Está fora da entrega oficial.
- Não está aprovado para publicação nem para a Play Store.

### Web/PWA

- O artefato foi gerado.
- Não existe hospedagem pública definitiva.
- O backend HTTPS não foi configurado.
- Está fora da entrega oficial.

### iOS

- Não implementado.
- Nenhuma compatibilidade é declarada.

## 11. Limitações

- Trata-se de projeto acadêmico, sem dados reais e sem implantação em UBS real.
- Não houve validação formal com pacientes reais.
- A versão Android não foi concluída nem validada.
- A versão Web não possui hospedagem pública definitiva.
- SMTP real ficou fora da validação final.
- A validação humana com leitor de tela no Windows permanece como teste manual desejável.
- O pacote Windows não possui assinatura de código comercial.
- SQLite é adequado ao MVP, não a uma implantação institucional ampla.

## 12. Entrega concluída

- Auditoria final aprovada com 232 testes backend e 190 testes Flutter aprovados e `flutter analyze` sem ocorrências.
- PDF final de 28 páginas validado e enviado ao GitHub.
- Commits finais e push concluídos em 16/11/2026.
- `main` e `origin/main` estavam sincronizadas após o push.
- Android permanece não validado em aparelho físico e fora da entrega oficial.
- Web/PWA permanece sem hospedagem pública e fora da entrega oficial.
