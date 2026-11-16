# Estrutura do projeto

Esta é a estrutura efetivamente usada pelo UBS Rápida. A organização preserva os caminhos exigidos pelo Flutter, FastAPI, testes e pelo iniciador oficial.

```text
ubs_Hospital_rapido/
├── backend/
│   ├── app/
│   │   ├── core/       # configuração, banco, identidade e segurança
│   │   ├── models/     # entidades SQLAlchemy
│   │   ├── routes/     # rotas FastAPI por domínio/perfil
│   │   ├── schemas/    # contratos de entrada e saída
│   │   └── services/   # regras compartilhadas e integrações
│   ├── tests/           # testes Pytest
│   ├── *.py             # utilitários operacionais compatíveis com o iniciador
│   ├── requirements.txt
│   ├── .env.example
│   └── README.md
├── frontend/
│   ├── assets/          # imagens versionadas
│   ├── lib/
│   │   ├── config/      # API, acessibilidade e design system
│   │   ├── models/      # modelos consumidos pela interface
│   │   ├── screens/     # telas por perfil e fluxo
│   │   ├── services/    # cliente da API
│   │   ├── widgets/     # componentes reutilizáveis
│   │   └── main.dart
│   ├── test/            # testes de widget e acessibilidade
│   ├── pubspec.yaml
│   └── README.md
├── docs/                # documentação atual, entrega final e acervo histórico
├── packaging/           # fontes dos pacotes e da página local de distribuição
├── scripts/             # iniciadores, build e auditoria de distribuição
├── tests/               # testes PowerShell do iniciador Windows
├── INICIAR_TUDO.bat     # único iniciador oficial
├── README.md
├── DESIGN.md            # direção visual da página de distribuição
├── PRODUCT.md           # escopo e princípios do produto acadêmico
├── .gitignore
└── LICENSE
```

## Decisões de organização

- `backend/app/` e `frontend/lib/` são as únicas árvores de código da aplicação em uso.
- Os utilitários Python continuam diretamente em `backend/` porque o iniciador e testes os carregam por esses caminhos. Movê-los exigiria alterar o carregamento de módulos sem benefício funcional.
- `scripts/iniciar.ps1` é interno; o usuário deve executar somente `INICIAR_TUDO.bat`.
- Documentos correntes usam pastas numeradas; a consolidação acadêmica fica em `docs/00_visao_geral/` e o status da entrega em `docs/STATUS_ENTREGA_FINAL.md`. Materiais substituídos, rascunhos e planos permanecem em `docs/99_arquivo_historico/` para preservar links e rastreabilidade.

## Conteúdo local não versionado

O `.gitignore` exclui `.env`, bancos SQLite e backups, ambientes virtuais, caches Python, `.dart_tool`, builds Flutter, logs, temporários e saídas locais. Esses itens podem existir no computador, mas não fazem parte do pacote enviado ao GitHub.

O banco local não foi movido, recriado ou apagado.
