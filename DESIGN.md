---
name: UBS Rápida
description: Um portal cívico direto e acessível para distribuir a demonstração acadêmica da UBS Rápida.
colors:
  civic-blue: "#005a9c"
  institutional-navy: "#003b66"
  service-green: "#176b3a"
  clinical-ink: "#17212b"
  slate-copy: "#4d5d6c"
  cool-paper: "#f4f7f9"
  white: "#ffffff"
  rule-line: "#ced9e2"
  focus-amber: "#f0b429"
  selection-blue: "#c9e7f7"
  code-surface: "#e5edf3"
  academic-mint: "#e4f0e8"
  academic-green: "#124f2c"
typography:
  display:
    fontFamily: "Atkinson Hyperlegible Next, Segoe UI, sans-serif"
    fontSize: "clamp(3rem, 7vw, 5.8rem)"
    fontWeight: 800
    lineHeight: 0.98
    letterSpacing: "-0.04em"
  headline:
    fontFamily: "Atkinson Hyperlegible Next, Segoe UI, sans-serif"
    fontSize: "clamp(2rem, 4vw, 3.4rem)"
    fontWeight: 800
    lineHeight: 1.05
    letterSpacing: "-0.03em"
  body:
    fontFamily: "Segoe UI, Arial, sans-serif"
    fontSize: "1.05rem"
    fontWeight: 400
    lineHeight: 1.65
  label:
    fontFamily: "Segoe UI, Arial, sans-serif"
    fontSize: "1rem"
    fontWeight: 750
    lineHeight: 1.2
rounded:
  code: "5px"
  control: "12px"
  surface: "16px"
  circle: "50%"
spacing:
  xs: "10px"
  sm: "14px"
  md: "18px"
  lg: "24px"
  xl: "28px"
  2xl: "38px"
  section: "84px"
components:
  button-primary:
    backgroundColor: "{colors.white}"
    textColor: "{colors.institutional-navy}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "0 22px"
    height: "50px"
  button-secondary:
    backgroundColor: "{colors.service-green}"
    textColor: "{colors.white}"
    typography: "{typography.label}"
    rounded: "{rounded.control}"
    padding: "0 22px"
    height: "50px"
  academic-note:
    backgroundColor: "{colors.academic-mint}"
    textColor: "{colors.academic-green}"
    rounded: "{rounded.surface}"
    padding: "clamp(28px, 6vw, 58px)"
---

# Design System: UBS Rápida

## Overview

**Creative North Star: "O Portal Cívico Hipernítido"**

A UBS Rápida se apresenta como uma porta institucional confiável: clara como um balcão de serviço bem sinalizado, direta como uma instrução operacional e humana sem recorrer à estética promocional de uma loja. Azul profundo estabelece autoridade, verde identifica a ação complementar e amplas superfícies claras preservam calma e legibilidade.

O sistema combina tipografia de alta legibilidade, contraste forte, linhas precisas e poucos volumes expressivos. A hierarquia vem de escala, peso e espaço; a ornamentação é rara e geométrica. A logo oficial permanece inteira, e o conteúdo nunca promete além do que a demonstração acadêmica sustenta.

**Key Characteristics:**

- Institucional, direto e acolhedor sem linguagem comercial.
- Hierarquia tipográfica grande e de alta legibilidade.
- Azul profundo como campo de confiança; verde reservado a ações e avisos acadêmicos.
- Superfícies planas, linhas finas e uma única elevação ambiente no hero.
- Responsividade de uma coluna, controles largos e foco de teclado inequívoco.

## Colors

A paleta parte das cores autorizadas da marca e as organiza em papéis cívicos claros: autoridade, ação, leitura, estrutura e orientação de foco.

### Primary

- **Azul Cívico:** conduz links, marcadores numerados e ações informativas.
- **Azul Institucional:** ancora o hero, títulos e textos de alta autoridade.

### Secondary

- **Verde de Serviço:** identifica a ação Android e reforça o vocabulário de saúde sem competir com o azul.
- **Verde Acadêmico:** colore o título do aviso que delimita o uso da demonstração.

### Neutral

- **Papel Frio:** é a superfície contínua da página e mantém baixo o ruído visual.
- **Branco Clínico:** dá contraste máximo ao hero e ao controle primário.
- **Tinta Clínica:** sustenta conteúdo principal sobre fundos claros.
- **Texto Ardósia:** reduz ênfase em descrições, requisitos e texto auxiliar.
- **Linha de Regra:** divide passos, requisitos e rodapé sem simular cartões.
- **Superfície de Código:** isola nomes de arquivo dentro das instruções.
- **Menta Acadêmica:** diferencia o aviso de uso fictício sem criar um alerta agressivo.

### Named Rules

**The Blue-Field Rule.** O azul institucional pode dominar um campo de abertura; fora dele, deve voltar a títulos, links e pequenos marcadores.

**The Meaningful Green Rule.** Verde sinaliza ação secundária de plataforma ou contexto acadêmico; não é decoração difusa.

**The Focus Is Never Subtle Rule.** O âmbar de foco é reservado ao contorno de teclado e precisa permanecer visível sobre fundos claros e escuros.

## Typography

**Display Font:** Atkinson Hyperlegible Next (com Segoe UI como fallback)
**Body Font:** Segoe UI (com Arial como fallback)
**Label/Mono Font:** Segoe UI para controles; Consolas para nomes de arquivo

**Character:** Atkinson Hyperlegible Next dá aos títulos uma voz firme, pública e excepcionalmente legível. Segoe UI mantém instruções familiares a usuários de Windows e oferece leitura neutra em todos os ambientes.

### Hierarchy

- **Display** (peso 800, escala fluida, entrelinha compacta): reservado ao enunciado principal, com largura curta e quebra balanceada.
- **Headline** (peso 800, escala fluida, entrelinha compacta): abre seções e mantém continuidade com a presença do hero.
- **Body** (peso 400, tamanho confortável, entrelinha generosa): explica instalação e limites em linhas de até aproximadamente 65 caracteres.
- **Label** (peso 750): sustenta botões, nomes de plataforma, versão e pequenos pontos de navegação.
- **Mono** (Consolas): aparece somente em nomes de arquivo ou comandos literais.

### Named Rules

**The Legibility Before Branding Rule.** A personalidade vive nos títulos; instruções, requisitos e controles permanecem em uma fonte de interface familiar.

**The Short Display Rule.** Texto display deve ser curto e balanceado; explicações longas descem para corpo, nunca encolhem o título.

## Layout

O conteúdo vive em um contêiner central de no máximo 1160px, com 20px de respiro lateral mínimo. O hero usa duas colunas assimétricas em telas amplas: narrativa e ações à esquerda, metadados de versão à direita. Seções operacionais alternam uma introdução estreita com conteúdo detalhado, e requisitos usam três colunas divididas apenas por linhas.

Em larguras de até 820px, toda a página vira uma coluna. O hero perde a altura mínima, cada ação ocupa a largura disponível, instruções empilham-se e requisitos passam a divisões horizontais. A cadência ampla entre blocos preserva leitura; o conteúdo nunca é comprimido em cartões concorrentes.

**The One-Column Integrity Rule.** No modo estreito, ordem, significado e todas as ações permanecem intactos; apenas a composição muda.

## Elevation & Depth

O sistema é plano por padrão. Profundidade surge por contraste tonal, bordas de um pixel e espaço. O hero é a única superfície com elevação ambiente constante; botões respondem com uma elevação física mínima no hover, removida quando o usuário prefere menos movimento.

### Shadow Vocabulary

- **Hero ambiente** (`0 24px 55px rgba(0, 46, 80, .22)`): separa a grande abertura azul do papel frio sem transformar a página em uma pilha de cartões.

### Named Rules

**The One Ambient Shadow Rule.** Somente o grande campo de abertura recebe sombra permanente; seções de conteúdo permanecem planas.

## Shapes

Grandes superfícies usam cantos suavemente arredondados; controles usam um raio um pouco menor; trechos de código recebem arredondamento compacto. Marcadores numerados são círculos verdadeiros. A curva serve à leitura e ao toque, nunca cria pílulas decorativas ou uma linguagem excessivamente macia.

**The Radius Has a Job Rule.** Use curva para conter uma superfície ou ampliar a affordance de um controle; divisões informativas continuam sendo linhas retas.

## Components

### Buttons

- **Shape:** retângulo tátil com cantos suavemente arredondados e altura mínima confortável.
- **Primary:** fundo branco e texto azul institucional sobre o hero; é a primeira ação de download.
- **Secondary:** fundo verde de serviço e texto branco; tem o mesmo peso e as mesmas dimensões do primário.
- **Text:** link branco sublinhado, sem cápsula ou preenchimento.
- **Hover / Focus:** elevação de 2px com transição curta no hover; contorno âmbar espesso e afastado no foco visível; toda transição é removida com preferência de movimento reduzido.

### Cards / Containers

- **Hero:** grande campo azul institucional, raio de superfície, sombra ambiente e um arco geométrico translúcido como único gesto decorativo.
- **Requirements:** estrutura sem cartões; três áreas separadas por linhas finas.
- **Academic Note:** superfície menta, título verde acadêmico e padding fluido; funciona como limite de uso, não como chamada promocional.

### Navigation

- **Header:** logo oficial integral à esquerda e contexto de distribuição à direita; sem menu supérfluo.
- **Footer:** nome do produto e link para instruções completas, separados do conteúdo por uma única linha.
- **Skip link:** fica fora da tela até receber foco e então surge com alto contraste no canto superior.

### Installation Steps

Cada passo combina um marcador circular azul, um rótulo de plataforma em negrito e uma instrução contínua. Linhas horizontais separam os passos; nomes de arquivo recebem superfície de código e fonte monoespaçada.

## Do's and Don'ts

### Do:

- **Do** preserve a proporção e a imagem completa da logo oficial.
- **Do** usar campos de azul profundo para momentos de autoridade e superfícies claras para conteúdo operacional.
- **Do** manter instruções em português direto, com plataforma e próximo passo visíveis no início da frase.
- **Do** conservar o foco âmbar, a navegação por teclado e controles de toque largos.
- **Do** reorganizar o layout em uma coluna abaixo do breakpoint estabelecido, sem remover conteúdo.

### Don't:

- **Don't** transformar downloads, requisitos ou instruções em uma grade de cartões promocionais.
- **Don't** inventar selos, métricas, depoimentos, certificações ou promessas de produção.
- **Don't** recortar, distorcer ou recolorir a logo.
- **Don't** espalhar sombras por superfícies de conteúdo ou usar vidro, gradientes e brilho como decoração.
- **Don't** depender somente de cor, hover ou animação para comunicar ação e estado.
