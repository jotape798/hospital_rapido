# Fluxo de cadastro

```text
Login -> Criar conta
  -> dados do paciente
  -> se menor: dados do responsável legal
  -> POST /auth/register
  -> conta paciente ativa
  -> retorno à tela de login
  -> login com CPF e senha
  -> painel do paciente
```

O cadastro cria um registro de verificação, envia um código de seis dígitos e bloqueia o primeiro login até a confirmação. Código e token de correção são persistidos somente como hash, com expiração, tentativas limitadas e uso único. A recuperação de senha permanece separada, exige e-mail previamente confirmado e utiliza outro código temporário; endereços desconhecidos recebem resposta genérica e não geram registro.
