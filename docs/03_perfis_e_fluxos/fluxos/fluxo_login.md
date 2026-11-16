# Fluxo de login

```text
Login único
  -> CPF + senha
  -> POST /auth/login
  -> backend valida CPF, BCrypt, situação da conta e confirmação do e-mail
  -> paciente não confirmado retorna orientação para concluir a confirmação
  -> JWT + perfil
  -> sessão local protegida
  -> homeForRole()
  -> dashboard do paciente, equipe ou administrador
```

Não existe escolha pública de perfil. Credenciais inválidas retornam mensagem genérica. O cadastro cria o paciente com o endereço ainda não confirmado e conduz ao fluxo de confirmação; o primeiro login somente é liberado depois dessa validação. A recuperação de senha também exige e-mail previamente confirmado.
