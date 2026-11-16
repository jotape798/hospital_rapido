# Documentação do UBS Rápida

Esta pasta descreve somente o comportamento identificado no código e no banco atual.

1. [Consolidação da entrega](00_visao_geral/O_QUE_FOI_FEITO_NO_PROJETO.md): visão acadêmica completa do que foi desenvolvido;
2. [Visão geral técnica](01_visao_geral/visao_geral.md): objetivo e arquitetura do sistema;
3. [Requisitos](02_requisitos/): requisitos funcionais, não funcionais e regras de negócio;
4. [Perfis e fluxos](03_perfis_e_fluxos/): casos de uso, fluxos principais, alternativos e exceções dos cinco perfis;
5. [Diagrama de casos de uso](04_casos_de_uso/diagrama_casos_de_uso.mmd) e [telas](04_telas/): visão visual e detalhamento da interface;
6. [Banco de dados](05_banco_de_dados/estrutura_banco.md): tabelas, relacionamentos e [DER conceitual](05_banco_de_dados/DER_Conceitual_UBS_Rapida.mmd);
7. [API](06_api/endpoints.md): endpoints FastAPI e perfis autorizados;
8. [Testes](07_testes/testes_e_resultados.md): comandos e resultados verificados;
9. [Apresentação](08_apresentacao/roteiro_demonstracao.md): roteiro curto e [informações da entrega](08_apresentacao/informacoes_entrega.md);
10. [Distribuição](09_distribuicao/INSTALACAO.md): instruções e limites dos artefatos gerados.

- [Estrutura do projeto](ESTRUTURA_DO_PROJETO.md): finalidade de cada pasta e arquivos que não devem ser versionados;
- [O que foi feito](O_QUE_FOI_FEITO.md): registro da organização realizada;
- [Status da entrega final](STATUS_ENTREGA_FINAL.md): plataforma oficial, evidências, limitações e pendências;
- [Arquivo histórico](99_arquivo_historico/README.md): documentos antigos mantidos apenas para rastreabilidade.

Em caso de divergência, os documentos numerados acima e o código atual são a referência operacional.

Os fluxos detalhados incluem os [casos de uso](03_perfis_e_fluxos/fluxos/casos_de_uso.md) e os [fluxos alternativos e as exceções](03_perfis_e_fluxos/fluxos/fluxos_alternativos_e_excecoes.md), organizados por Paciente, Recepção, Enfermagem, Médico e Administrador.
