# Status da entrega final — UBS Rápida

**Data de consolidação:** 16/11/2026

**Versão oficial:** 0.1.0 (`pubspec` 0.1.0+2)

**Plataforma oficial:** Windows desktop

## Situação por plataforma

- **Windows:** versão oficial da entrega, validada para demonstração acadêmica. Não está declarado como publicado em produção.
- **Android:** APK e AAB foram gerados com package `br.com.ubsrapida.app`, mas não houve validação final em aparelho físico. O funcionamento no celular não está confirmado; Android está fora da entrega oficial e não está aprovado para publicação ou Play Store.
- **Web/PWA:** artefato gerado, sem hospedagem pública definitiva e sem backend HTTPS configurado. Está fora da entrega oficial.
- **iOS:** não implementado e sem compatibilidade declarada.

## Evidências conhecidas

A última execução validada registrou 232 testes backend e 190 testes Flutter aprovados, `flutter analyze` sem ocorrências, testes de segurança e do iniciador Windows aprovados, build Windows Release aprovado, pacote Windows testado fora da pasta do projeto, `/health`, Swagger e frontend aprovados e auditoria sem segredo real identificado.

As suítes backend e Flutter e a análise estática foram renovadas na validação final de 16/11/2026, antes dos commits e do push.

A auditoria final foi aprovada. Os commits finais e o push para o GitHub foram concluídos em 16/11/2026, com `main` sincronizada com `origin/main` no HEAD `c5dd69785fae3c671231184b86cdbbb7ed5d4803`.

## Correções do professor

As correções solicitadas foram consolidadas: prioridades legais e validação presencial, idade por data de nascimento, históricos e auditoria, classificação de risco separada, login, confirmação de e-mail, recuperação de senha, responsividade, iniciador e fallback do Python, rota única de check-in, Swagger, relógio central, filtros, avisos ao paciente, testes de segurança, documentação, scripts UTF-8, equipe fictícia ampliada, diferenciação de dentistas e isolamento de agendas.

## Limitações conhecidas

- O PDF final presente em `docs/entrega_final` possui 28 páginas e SHA-256 `08F8E95DB949DDDC7101F8D6CC55D9D0F60A903AB939436DA154B34A95DCC0D7`.
- O projeto é acadêmico, utiliza somente dados fictícios e não foi implantado em UBS real.
- Android não foi validado; Web não possui publicação definitiva; SMTP real, leitor de tela humano no Windows e assinatura comercial do pacote ficaram fora da validação final.
- SQLite atende ao MVP, não a uma implantação institucional ampla.

## Entrega concluída

A documentação final, a auditoria, os commits e o push foram concluídos. Não há pendência de commit ou push para a entrega oficial.
