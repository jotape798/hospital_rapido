# Informações da entrega

- **Projeto:** UBS Rápida;
- **Versão documentada:** 0.1.0;
- **Repositório:** https://github.com/Victoraquino135/hospital_rapido;
- **Protótipo:** nenhum link externo foi localizado; o Flutter executável é a referência visual;
- **Entrega oficial atual:** versão desktop Windows 0.1.0 validada para demonstração acadêmica;
- **Artefatos fora da entrega oficial:** Android APK/AAB gerados, mas não validados em aparelho físico; Web/PWA gerado, mas sem hospedagem pública;
- **Banco:** SQLite local preservado, com dados fictícios;
- **Iniciador oficial:** `INICIAR_TUDO.bat`.

## Dados fictícios

A demonstração acadêmica usa exclusivamente dados fictícios. Credenciais, endereços de e-mail, códigos temporários e configurações locais não fazem parte desta documentação e não devem ser incluídos nos pacotes distribuíveis.

## Resultados alcançados

- login único e redirecionamento automático por perfil;
- agendamento com controle de duplicidade e concorrência;
- cancelamento/reagendamento com liberação de vaga;
- fluxo presencial completo, com triagem manual e fila priorizada;
- confirmação de e-mail obrigatória antes do primeiro login e recuperação restrita a e-mail confirmado;
- rota única de check-in e relógio central da UBS;
- filtros de auditoria e avisos de prioridade;
- médicos, dentistas e Painel de Atendimento;
- separação de permissões no backend;
- acessibilidade, responsividade e atualização automática;
- documentação, especificação da API, testes e pacote oficial Windows;
- artefatos Android e Web disponíveis apenas como resultados de build, sem aprovação para publicação.

## Limitações e melhorias futuras

- aplicação acadêmica local, sem integração SUS/e-SUS;
- SMTP depende de configuração local segura;
- instalação e fluxo completo do Android em aparelho físico ainda precisam de validação registrada;
- publicação com backend HTTPS e configuração de produção ainda está pendente;
- SQLite é adequado ao MVP, não a implantação multiunidade em produção;
- o relógio central da UBS substituiu os usos antigos de `datetime.utcnow()`; futuras evoluções devem preservar essa política temporal;
- painel público/TV, senha pública e chamador de fila ficam explicitamente fora do MVP e podem ser avaliados futuramente;
- não há prontuário, diagnóstico, medicamentos, exames, vacinação, pagamentos ou IA clínica.
