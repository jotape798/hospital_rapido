# O que foi feito

Organização executada em 09/10/2026, sem alterar telas, APIs, regras de negócio ou dados do SQLite.

## Organização

- Separação da visão geral, requisitos, perfis/fluxos e telas em pastas numeradas.
- Consolidação da documentação antiga, referências visuais, cópia histórica de código e planos de desenvolvimento em `99_arquivo_historico`.
- Transferência do script PowerShell interno para `scripts/`, mantendo `INICIAR_TUDO.bat` como único iniciador oficial.
- Atualização dos links do README principal e dos READMEs do backend, frontend e documentação.
- Registro da estrutura real do projeto neste conjunto de documentos.

## Tratamento consciente dos arquivos anteriores

- `ATUALIZAR_E_INICIAR_TUDO.bat` e `INICIAR_UBS.bat` eram iniciadores antigos. Não possuem referências ativas e permanecem removidos em favor de `INICIAR_TUDO.bat`.
- Documentos antigos não foram descartados: foram movidos para o arquivo histórico.
- Duplicatas presentes no acervo histórico foram mantidas, pois podem representar evidência acadêmica do processo. Elas não participam da execução.
- Arquivos gerados e locais continuam apenas no computador e ignorados pelo Git.

## Preservação

- Código do backend e frontend: preservado.
- Banco SQLite e dados existentes: preservados e não versionados.
- `.env` local: preservado e não versionado.
- Funcionalidades, integrações, testes, identidade visual e regras de negócio: preservadas.
- Commit e push: não realizados.

## Validação após a organização

> **Registro histórico — resultado substituído pela auditoria final.** Os números de 101 testes backend e 93 testes Flutter correspondem à verificação intermediária de 09/10/2026. Na auditoria final, após a ampliação das suítes, os resultados passaram para 232 testes backend e 190 testes Flutter aprovados, com `flutter analyze` sem ocorrências.

- Iniciador oficial: teste automatizado aprovado após a mudança do script interno.
- Backend naquela verificação intermediária: 101 testes aprovados usando diretório temporário isolado dentro da área ignorada do projeto.
- Flutter naquela verificação intermediária: 93 testes aprovados.
- `flutter analyze` naquela verificação intermediária: nenhum problema encontrado.
- Links relativos da documentação atual: todos resolvidos.
- `git diff --check`: nenhuma diferença inválida; apenas avisos normais de conversão de fim de linha no Windows.
- Arquivos publicáveis: nenhum `.env`, banco, ambiente virtual, cache, build ou log identificado.

A primeira execução do Pytest encontrou uma restrição de permissão na pasta temporária global do Windows. A suíte foi repetida integralmente com `--basetemp` local e terminou sem falhas; não houve correção de código relacionada a esse evento ambiental.
