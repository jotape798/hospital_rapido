# UBS Rápida

Sistema acadêmico (MVP) criado para reduzir filas presenciais de agendamento em Unidades Básicas de Saúde. A aplicação oferece login único por CPF e senha, identifica o perfil no backend e abre automaticamente o painel correspondente.

Todos os dados de demonstração são fictícios. O projeto não substitui sistemas oficiais de saúde e não é um prontuário eletrônico.

- **Repositório:** https://github.com/Victoraquino135/hospital_rapido
- **Última revisão:** 13/11/2026
- **Protótipo externo:** nenhum link de protótipo foi localizado no projeto; a implementação Flutter é a referência visual atual.

## Tecnologias

- **Frontend:** Flutter (Windows e Web);
- **Backend:** FastAPI / Python;
- **Banco:** SQLite com SQLAlchemy;
- **Autenticação:** JWT e senhas protegidas com BCrypt;
- **Testes:** Pytest, Flutter Test e Flutter Analyze.

## Perfis

- Paciente;
- Recepção;
- Enfermagem;
- Médico;
- Dentista, usando o perfil de atendimento Médico com profissão e especialidade próprias;
- Administrador.

Não há seletores públicos de perfil. Após a autenticação, o backend informa o perfil e o Flutter redireciona o usuário.

O fluxo presencial é `Recepção/check-in → Enfermagem/triagem → Profissional de atendimento → Concluída`. Médicos e dentistas acessam somente pacientes atribuídos a eles com triagem concluída, registram um resumo simples e não possuem acesso administrativo, à triagem ou ao cadastro de vagas. Especialidade e profissão não criam novos perfis de permissão.

## Equipe fictícia de demonstração

A demonstração ampliada é opcional e separada da inicialização normal. Ela inclui:

- Recepção: Ana Paula Martins, Bruno Henrique Costa e Camila Rodrigues Silva;
- Enfermagem: Juliana Ferreira Lima, Rafael Oliveira Santos e Patrícia Almeida Souza;
- Dr. Lucas Mendes — Clínica Geral;
- Dra. Mariana Costa — Cardiologia;
- Dr. Pedro Henrique Alves — Pediatria;
- Dra. Beatriz Rodrigues — Ginecologia;
- Carolina Fernandes — Dentista, Odontologia;
- Gabriel Ribeiro — Dentista, Odontologia.

Os dados são fictícios. Para incluir ou conferir essa equipe de forma idempotente, execute na raiz:

```powershell
backend\venv\Scripts\python.exe backend\incluir_profissionais_demonstracao.py
```

CPFs e senhas temporárias ficam exclusivamente em `backend\profissionais_demo.env.local`, arquivo ignorado pelo Git. Não copie credenciais para README, logs, commits ou relatórios.

## Como executar

Para gerar os pacotes distribuíveis de Windows, Android e Web, consulte [as instruções de distribuição](docs/09_distribuicao/INSTALACAO.md). Os artefatos locais são criados em `dist/`, sem banco, `.env`, segredos ou logs do ambiente de desenvolvimento.

### Pré-requisitos no Windows

- Flutter instalado, com o comando `flutter` disponível no `PATH`;
- Python 3.10 ou superior instalado;
- Modo de desenvolvedor do Windows ativado.

O Modo de desenvolvedor é um requisito do ambiente Flutter quando plugins precisam criar links simbólicos; não é uma falha funcional do UBS Rápida. Para ativá-lo, abra **Configurações → Privacidade e segurança → Para desenvolvedores** e habilite **Modo de Desenvolvedor**. Em versões anteriores do Windows, a opção pode estar em **Configurações → Atualização e Segurança → Para desenvolvedores**.

Quando esse modo está desativado, o Flutter pode interromper a preparação com uma mensagem como `Building with plugins requires symlink support` ou solicitar a ativação das configurações para desenvolvedores. Depois de ativá-lo, execute `INICIAR_TUDO.bat` novamente. O iniciador cria o ambiente virtual do backend e instala as dependências quando necessário.

No Windows, execute o único iniciador oficial na raiz:

```text
INICIAR_TUDO.bat
```

O iniciador localiza o projeto, usa ou cria `backend\venv`, sincroniza as dependências quando `requirements.txt` mudar, valida a configuração, garante de forma idempotente as contas fictícias que estiverem ausentes, inicia a API e abre o Flutter para Windows. O conteúdo do frontend é verificado por SHA-256; quando houver mudança, o aplicativo Windows será recompilado automaticamente. A mensagem de sucesso aparece somente depois que a API responde e o frontend permanece ativo e pronto; em caso de falha ou timeout, o iniciador mostra os logs e retorna erro. O banco existente não é recriado nem apagado.

Ao abrir `INICIAR_TUDO.bat` com duplo clique, o iniciador atualiza as dependências necessárias e recompila o aplicativo Windows antes de abrir, garantindo que a versão exibida contenha as alterações atuais.

Para abrir no navegador, use `INICIAR_TUDO.bat -Dispositivo chrome` ou `INICIAR_TUDO.bat -Dispositivo edge`. Nesses modos, o frontend permanece servido em `http://127.0.0.1:8080`, mesmo que a janela do navegador seja fechada, e o mesmo endereço pode ser aberto novamente enquanto o iniciador estiver em execução.

Para forçar a restauração das dependências e a recompilação da interface:

```powershell
.\INICIAR_TUDO.bat -AtualizarTudo
```

A API e o Swagger ficam disponíveis em:

```text
http://127.0.0.1:8000/docs
```

## Estrutura

- `frontend/`: interface Flutter, assets e testes de widgets;
- `backend/`: API FastAPI, regras de negócio, persistência SQLite e testes;
- `backend/ubs_rapida.db`: banco local preservado e ignorado pelo Git;
- `docs/`: visão do projeto, perfis, telas, fluxos, banco, API, testes e roteiro;
- `scripts/`: implementação interna do iniciador oficial;
- `tests/`: validações do iniciador e da estrutura na raiz;
- `INICIAR_TUDO.bat`: iniciador oficial;
- `scripts/iniciar-supervisionado.ps1`: script interno usado pelo iniciador oficial.

Consulte o [índice da documentação](docs/README.md) e a [estrutura detalhada](docs/ESTRUTURA_DO_PROJETO.md).

## Segurança e configuração local

Copie `backend/.env.example` para `backend/.env` quando precisar configurar SMTP. O `.env`, bancos locais, ambientes virtuais, caches e builds são ignorados pelo Git. Nunca publique senha SMTP, `JWT_SECRET_KEY`, tokens, hashes ou bancos com dados locais.

O cadastro público cria somente pacientes, envia um código temporário e exige a confirmação do e-mail antes do primeiro login. O código e o token de correção são armazenados somente como hash. A recuperação de senha também usa código temporário de uso único e só pode ser iniciada por contas com e-mail já confirmado; endereços desconhecidos recebem resposta genérica e não criam recuperação. A entrega real depende de SMTP configurado localmente.

Credenciais, `backend/.env`, `backend/profissionais_demo.env.local`, bancos SQLite e backups são exclusivamente locais e não devem ser versionados.

## Limitações conhecidas

- a entrega real de e-mail depende de uma conta SMTP de teste configurada localmente;
- na Web, o token permanece somente em memória e um recarregamento exige novo login;
- o escopo odontológico usa a agenda e o atendimento simples já existentes, sem prontuário odontológico;
- não há integração SUS/e-SUS, exames, prescrição, telemedicina, pagamentos ou painel público/TV.

As tabelas `historico_status_consultas`, `historico_condicoes_prioritarias` e `classificacoes_risco`, seus campos principais e finalidades estão descritas em `docs/05_banco_de_dados/estrutura_banco.md`.

## Escopo do MVP

O sistema implementa cadastro, autenticação, agendamento, cancelamento, reagendamento, check-in, fila, classificação manual de risco, atendimento Médico com resumo simples, administração de usuários internos e Médicos, especialidades e grades.

Não fazem parte do escopo: prontuário completo, medicamentos, vacinação, exames, telemedicina, pagamentos, integrações SUS/e-SUS, WhatsApp, SMS, IA clínica ou painel público/TV. O painel público é melhoria futura, não requisito do MVP entregue.

## Testes

Backend:

```powershell
cd backend
.\venv\Scripts\python.exe -m pytest -q
```

Frontend:

```powershell
cd frontend
flutter test
flutter analyze
```

Os resultados da última execução estão em [docs/07_testes/testes_e_resultados.md](docs/07_testes/testes_e_resultados.md).

## Licença

Projeto acadêmico distribuído sob a licença MIT. Consulte [LICENSE](LICENSE).
