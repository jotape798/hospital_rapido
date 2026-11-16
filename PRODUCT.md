# Produto

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Pacientes, recepcionistas, profissionais de enfermagem, médicos, dentistas e administradores de uma UBS acadêmica. Cada pessoa autentica-se com CPF e senha e é direcionada ao painel permitido pelo backend.

## Product Purpose

A UBS Rápida reduz filas presenciais de agendamento e organiza o fluxo de chegada, triagem e atendimento. O sucesso significa permitir que os perfis concluam suas tarefas sem ampliar permissões nem expor dados clínicos.

## Positioning

Um MVP acadêmico completo que demonstra, em um único fluxo responsivo, agendamento pelo paciente e operação presencial pela equipe da UBS, com separação de acesso por perfil.

## Operating Context

O frontend Flutter possui artefatos para Windows, Android e navegador. Somente o Windows desktop 0.1.0 integra a entrega oficial; Android não foi validado em aparelho físico e Web não possui hospedagem pública definitiva. O backend FastAPI pode operar localmente no Windows ou, em uma evolução futura, por hospedagem HTTPS para Android e Web. O projeto usa dados fictícios na demonstração e não substitui sistemas oficiais de saúde.

## Capabilities and Constraints

- Cadastro, login, recuperação de senha, agendamento, cancelamento e reagendamento.
- Check-in, fila, classificação de risco, atendimento simples e administração.
- SQLite local no pacote Windows e backend remoto para Android/Web.
- A URL da API é definida por ambiente; produção exige HTTPS.
- Pacotes distribuíveis nunca incluem banco real, arquivos `.env`, segredos, logs ou credenciais prontas.
- iOS não integra esta entrega porque exige macOS, assinatura Apple e canal próprio.

## Brand Commitments

O nome oficial é **UBS Rápida**. A logo existente em `frontend/assets/images/ubs_rapida_logo.jpg` é a única fonte visual autorizada; sua proporção deve ser preservada. A identidade já usa azul, verde, superfícies claras e linguagem direta em português do Brasil.

## Evidence on Hand

- Aplicação Flutter funcional e responsiva em `frontend/`.
- API FastAPI e testes em `backend/`.
- Logo oficial em `frontend/assets/images/ubs_rapida_logo.jpg`.
- Documentação de requisitos, perfis, fluxos e API em `docs/`.
- Não há depoimentos, métricas públicas, certificações nem URL pública de produção; esses elementos não devem ser inventados.

## Product Principles

- Preservar dados e fluxos clínicos acima de conveniência de distribuição.
- Explicar estados, falhas e próximos passos em linguagem simples.
- Conceder somente o acesso necessário a cada perfil.
- Separar configuração local, segredos e artefatos publicáveis.
- Tratar acessibilidade e responsividade como requisitos funcionais.

## Accessibility & Inclusion

A interface preserva suporte a teclado, leitor de tela, contraste elevado, escala de texto e áreas de toque adequadas. A página de downloads deve manter foco visível, contraste AA e instruções compreensíveis sem depender somente de cor.

## Direction contract — página de distribuição

**THESIS:** uma porta de entrada institucional e direta para instalar a demonstração acadêmica, recusando a aparência de loja comercial e qualquer promessa que o projeto não possa sustentar.

**OWN-WORLD:** campo claro, azul profundo e verde da identidade existente; superfícies planas, linhas nítidas, tipografia Segoe UI e a logo oficial sempre inteira. Os controles parecem utilitários de um serviço público digital, não cartões promocionais.

**STORY:** a pessoa identifica a UBS Rápida, reconhece o Windows como entrega oficial e distingue os artefatos não validados de Android e Web antes de encontrar requisitos, instalação e limites de uso acadêmico.

**FIRST VIEWPORT:** cabeçalho curto com a logo integral; abaixo, um hero azul de grande escala com a finalidade à esquerda, três ações reais imediatamente visíveis e versão/revisão à direita. Em telas estreitas, a leitura vira uma coluna e as ações ocupam a largura disponível. A assinatura interativa é a elevação discreta dos botões no hover, removida quando o sistema pede menos movimento.

**FORM:** direção fixada pelo briefing e pela identidade já existente, sem rodada de conceitos; seed de rastreabilidade `brief-pinned:ubs-rapida-distribution`. Build code-led, sem comp aprovada.

**FINISH:** unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
