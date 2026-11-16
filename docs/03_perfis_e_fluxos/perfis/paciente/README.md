# Perfil: Paciente

## Acesso e painel

O paciente conclui o cadastro confirmando o código enviado ao e-mail. Somente depois da confirmação entra pelo login único com CPF e senha. Após autenticação, o backend retorna `perfil = paciente` e o Flutter abre `PatientDashboard` (`frontend/lib/screens/dashboards.dart`). A recuperação de senha só é iniciada para conta ativa com e-mail confirmado.

O painel mostra saudação, próxima consulta, atalhos, lista de consultas e dados pessoais. Há atualização automática de status, acessibilidade, alteração/recuperação de senha e saída.

## Agendamento

Em `BookingPanel` (`frontend/lib/screens/booking.dart`), o paciente seleciona especialidade, profissional, data e horário livre, revisa o resumo e confirma. A API valida disponibilidade e propriedade. O resultado aparece na lista e no resumo do painel.

## Cancelamento e reagendamento

Nos detalhes da consulta, o paciente pode cancelar até 24 horas antes ou reagendar até 12 horas antes. A vaga anterior é liberada quando a operação é válida. Consultas em outro status não podem ser alteradas por esse fluxo.

## Acompanhamento

O paciente acompanha os estados agendada, check-in realizado, em triagem, em atendimento, concluída, cancelada ou falta. Ele não altera diretamente estados do fluxo presencial.

APIs principais: `/auth/login`, `/patients/me`, `/patients/me/summary`, `/appointments/me`, `/specialties`, `/professionals`, `/availability/*` e `/appointments`.
