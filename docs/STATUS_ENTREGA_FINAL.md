# Status da entrega final — UBS Rápida

**Data de consolidação:** 15/11/2026

**Versão oficial:** 0.1.0 (`pubspec` 0.1.0+2)

**Plataforma oficial:** Windows desktop

## Situação por plataforma

- **Windows:** versão oficial da entrega, anteriormente validada para demonstração acadêmica. O pacote será testado novamente na auditoria final. Não está declarado como publicado em produção.
- **Android:** APK e AAB foram gerados com package `br.com.ubsrapida.app`, mas não houve validação final em aparelho físico. O funcionamento no celular não está confirmado; Android está fora da entrega oficial e não está aprovado para publicação ou Play Store.
- **Web/PWA:** artefato gerado, sem hospedagem pública definitiva e sem backend HTTPS configurado. Está fora da entrega oficial.
- **iOS:** não implementado e sem compatibilidade declarada.

## Evidências conhecidas

A última execução validada registrou 232 testes backend e 190 testes Flutter aprovados, `flutter analyze` sem ocorrências, testes de segurança e do iniciador Windows aprovados, build Windows Release aprovado, pacote Windows testado fora da pasta do projeto, `/health`, Swagger e frontend aprovados e auditoria sem segredo real identificado.

Essas evidências serão renovadas na auditoria final antes do push.

## Correções do professor

As correções solicitadas foram consolidadas: prioridades legais e validação presencial, idade por data de nascimento, históricos e auditoria, classificação de risco separada, login, confirmação de e-mail, recuperação de senha, responsividade, iniciador e fallback do Python, rota única de check-in, Swagger, relógio central, filtros, avisos ao paciente, testes de segurança, documentação, scripts UTF-8, equipe fictícia ampliada, diferenciação de dentistas e isolamento de agendas.

## Pendências e limitações

- O PDF presente em `docs/entrega_final` está incorreto: possui 18 páginas e não deve ser commitado. Ele deve ser substituído antes da auditoria pelo PDF correto de 28 páginas, cujo SHA-256 esperado é `E9EC92CED863F907265F5F371210295F597C58540C6297B235F70235BDBF4CAB`.
- A auditoria final e o push ainda não foram realizados.
- O projeto é acadêmico, utiliza somente dados fictícios e não foi implantado em UBS real.
- Android não foi validado; Web não possui publicação definitiva; SMTP real, leitor de tela humano no Windows e assinatura comercial do pacote ficaram fora da validação final.
- SQLite atende ao MVP, não a uma implantação institucional ampla.

## Próximos passos

Substituir e validar o PDF, repetir as suítes e o `flutter analyze`, testar o pacote Windows, executar a auditoria de segurança e de segredos, revisar o Git e os commits, realizar o push, conferir o GitHub e preparar os links definitivos da entrega.
