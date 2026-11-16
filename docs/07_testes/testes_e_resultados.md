# Testes e resultados

## Linha de base técnica final

As suítes usam bancos SQLite temporários, dados fictícios e envio de e-mail
simulado. O banco local do projeto e endereços reais não participam dos testes.

### Backend

```powershell
cd backend
.\venv\Scripts\python.exe -m pytest tests -q --basetemp=<diretório temporário>
```

Resultado final da versão 0.1.0: **232 testes aprovados, 0 falhas**.

A cobertura inclui autenticação e autorização por perfil, rejeição de JWT com
algoritmo `none`, entradas semelhantes a injeção SQL, cadastro com confirmação
obrigatória de e-mail, indisponibilidade do serviço de e-mail com rollback,
recuperação de senha, responsáveis de menores, condições prioritárias
pendentes e validação presencial, concorrência de vagas, check-in, falta
automática após 15 minutos, triagem, escala de risco, fila médica, atendimento,
administração, auditoria, migrações e integridade do SQLite.

Os testes de consultas verificam a ausência de regressão N+1 nos cenários
direcionados, com contagens esperadas de **0, 1 e 8 consultas**, conforme o
volume e o caminho exercitado. A ordenação concorrente da prioridade também é
testada para preservar os critérios clínicos, legais e de chegada.

### Flutter

```powershell
cd frontend
flutter test
flutter analyze
flutter build web --release
```

Resultados finais:

- **190 testes aprovados, 0 falhas**;
- `flutter analyze`: **nenhuma ocorrência**;
- build Web `release`: **concluído com sucesso**. O diagnóstico de
  compatibilidade WebAssembly pode emitir avisos de dependências, sem impedir
  o build JavaScript de release.

A suíte cobre login e redirecionamento dos cinco perfis, cadastro e confirmação
de e-mail, recuperação de senha, responsividade nas larguras de 390, 768 e
1366 px, semântica e nomes acessíveis, navegação por teclado, foco, rolagem
independente das áreas extensas, textos ampliados, preferências de
acessibilidade e atualização periódica. Os testes de polling usam tempo falso,
sem depender de espera real ou de serviços externos.

## Validações manuais pendentes

As verificações abaixo **não estão comprovadas pela automação** e não devem ser
descritas como aprovadas até uma execução manual registrada:

1. usar a aplicação com zoom real de **150%** no navegador e inspecionar cortes,
   sobreposições, rolagem e foco nos cinco perfis;
2. percorrer os fluxos principais com um **leitor de tela real**, ouvindo os
   nomes, estados, erros, ordem de leitura e mudanças dinâmicas;
3. confirmar entrega, expiração, reenvio, correção de endereço e recuperação
   com um **serviço e uma caixa de e-mail reais**.
4. instalar o APK em um **aparelho Android físico** e registrar abertura,
   conexão, cadastro, confirmação, login, agendamento, cancelamento,
   responsividade e reabertura.

## Contratos e artefatos verificados

- API: **66 caminhos e 71 operações**, com rota única de check-in;
- banco: **17 tabelas e 28 relacionamentos de chave estrangeira**;
- `flutter analyze`: nenhuma ocorrência;
- versão desktop Windows 0.1.0 validada como entrega oficial para demonstração acadêmica;
- Android APK/AAB gerados, mas ainda não validados em aparelho físico e fora da entrega oficial atual;
- Web/PWA gerado, mas sem hospedagem pública e fora da entrega oficial atual.

## Limites da evidência

- Nenhuma mensagem real foi enviada durante as suítes; códigos, tokens e
  provedores foram simulados de forma isolada.
- Testes automatizados de semântica, teclado e layout reduzem risco, mas não
  substituem a experiência manual com navegador ampliado e tecnologia
  assistiva.
- Arquivos `.env`, bancos locais, ambientes virtuais, caches, logs e builds
  permanecem fora do controle de versão.
