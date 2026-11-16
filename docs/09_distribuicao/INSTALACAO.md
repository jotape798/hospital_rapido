# Instalação distribuível — UBS Rápida 0.1.0

> **Escopo da entrega:** a versão desktop Windows 0.1.0 é a entrega oficial validada para demonstração acadêmica. Android APK/AAB e Web/PWA são artefatos gerados, ainda fora da entrega oficial atual; Android não foi validado em aparelho físico e Web não possui hospedagem pública.

## Windows

1. Baixe `UBS_Rapida-Windows-0.1.0.zip`.
2. Extraia todo o conteúdo para uma pasta gravável.
3. Execute `Iniciar_UBS_Rapida.bat`.
4. No primeiro uso, informe os dados do primeiro administrador. A senha fica somente como hash no banco local.

O aplicativo cria uma base nova em `%LOCALAPPDATA%\UBSRapida\dados`. O segredo JWT é aleatório, protegido pelo Windows para o usuário atual e não aparece em arquivos de texto. Apagar o diretório do aplicativo não apaga os dados automaticamente.

O ZIP contém o frontend Flutter e o backend empacotado. Flutter e Python não precisam estar instalados.

## Android

Este artefato não foi aprovado para publicação nem validado em aparelho físico.

O APK local é `UBS_Rapida-Android-0.1.0.apk`. Ative temporariamente a permissão de instalação para o aplicativo usado para abrir o arquivo e confirme a instalação.

O endereço da API é definido no build:

```powershell
.\scripts\build_distribution.ps1 -AndroidApiBaseUrl 'http://IP-DO-COMPUTADOR:8000'
```

O celular e o computador precisam estar na mesma rede, o backend deve escutar em um endereço acessível e o firewall deve permitir a porta. `127.0.0.1` no Android aponta para o próprio aparelho e não deve ser usado.

Para publicação, use uma URL HTTPS e execute o build com `-Production`.

## Web/PWA

Este artefato não foi aprovado para publicação e não possui hospedagem pública.

Sirva o conteúdo de `dist/web` por HTTP ou HTTPS. A PWA pode ser instalada pelo menu do navegador. O cache offline guarda somente a página pública de indisponibilidade; chamadas da API, tokens e respostas privadas não são armazenados pelo service worker.

Em produção, publique o frontend e o backend em HTTPS e informe as origens exatas em `ALLOWED_ORIGINS`.

## Assinatura Android

A chave local fica em `frontend/android/app/ubs-rapida-release.jks`, e as propriedades em `frontend/android/key.properties`. Ambos são ignorados pelo Git. Preserve cópias seguras desses arquivos: perder a chave impede atualizar o mesmo aplicativo publicado.

Nunca envie a chave ou suas senhas junto com APK, AAB, código-fonte ou documentação pública.

## Limitações desta etapa

- Nenhum link público foi criado.
- O APK foi testado por build e inspeção; instalação em aparelho físico precisa ser validada separadamente.
- iOS não faz parte da entrega, pois requer macOS, assinatura Apple e distribuição específica.
- Não há instalador Windows porque Inno Setup, NSIS e MSIX não estavam disponíveis; o ZIP portátil é a distribuição Windows desta etapa.
