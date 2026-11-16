# Regras de negócio

- O cadastro público sempre cria um paciente; perfis internos são criados pelo administrador.
- CPF e e-mail são únicos. O login aceita CPF válido, nunca CNS ou seleção manual de perfil.
- O cadastro cria o paciente com conta ativa, envia código temporário e bloqueia o primeiro login até a confirmação do e-mail.
- A recuperação de senha exige e-mail previamente confirmado e código temporário recebido por e-mail; endereço desconhecido não cria recuperação nem recebe confirmação de cadastro.
- Menor de idade deve possuir responsável legal válido e vinculado.
- Horários devem ser futuros, em dia útil não feriado e pertencer ao profissional/especialidade.
- Um horário não pode ser reservado simultaneamente por dois pacientes.
- Cancelamento é permitido até 24 horas antes; reagendamento, até 12 horas antes.
- Check-in e falta são registrados no dia da consulta.
- O fluxo presencial esperado é `agendado -> em_espera -> em_triagem -> em_atendimento -> concluido`; `cancelado` e `falta` encerram o fluxo.
- A enfermagem precisa de perfil profissional ativo e autorização de triagem.
- A triagem presencial registra manualmente queixa principal, sinais vitais e classificação de risco; não há IA ou diagnóstico automático.
- A fila é ordenada primeiro pelo risco, depois por pessoa idosa (60+), PCD, gestante e lactante, e por fim pela chegada mais antiga. O motivo da prioridade é exibido à equipe.
- O profissional acessa somente consultas atribuídas a ele e só inicia após check-in e classificação.
- A grade não pode se sobrepor e não é removida quando há consultas vinculadas; ela é desativada/bloqueada com preservação dos dados.
- Senhas nunca são armazenadas em texto aberto; `senha_hash` usa BCrypt.
