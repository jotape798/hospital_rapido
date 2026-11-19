# Roteiro de demonstração — UBS Rápida v0.1.0

## Preparação

1. Baixe `UBS_Rapida-Windows-0.1.0.zip` na GitHub Release v0.1.0.
2. Extraia todo o conteúdo do ZIP antes de executar qualquer arquivo.
3. Execute `Iniciar_UBS_Rapida.bat`, o iniciador oficial da distribuição.
4. Aguarde a confirmação de que o backend e o aplicativo estão disponíveis.
5. Use somente os dados fictícios fornecidos para a demonstração.

O pacote Windows inclui o aplicativo e o backend necessários; não exige Flutter nem Python instalados.

## Contas fictícias oficiais

As contas abaixo são definidas nos scripts oficiais do projeto e criadas pelo inicializador.

| Perfil | Nome fictício | CPF fictício | Senha fictícia padrão | Finalidade |
| --- | --- | --- | --- | --- |
| Paciente | Paciente Demonstração | `52998224725` | `Paciente@123` | Consultar o painel e agendar, cancelar ou reagendar consultas. |
| Recepção | Rita Recepção Fictícia | `98765432100` | `Recepcao@123` | Localizar agendamentos, validar prioridade e fazer check-in. |
| Enfermagem | Enf. Helena Triagem Fictícia | `11144477735` | `Profissional@123` | Consultar a fila e registrar a triagem. |
| Médico/profissional | Dr. Victor Almeida | `39053344705` | `Medico@123` | Iniciar e concluir o atendimento atribuído. |
| Administrador | Ana Administração Fictícia | `12345678909` | `Admin@123` | Consultar filtros, auditoria e cadastros administrativos. |

> As contas são exclusivamente fictícias e destinadas à demonstração local. Não devem ser utilizadas se o sistema for publicado em rede ou adaptado para uso real.

## Demonstração sugerida — aproximadamente cinco minutos

1. **Paciente:** entre com a conta fictícia, mostre o painel e consulte ou faça um agendamento disponível.
2. **Recepção:** localize o paciente, confirme ou rejeite uma condição prioritária pendente, quando houver, e registre o check-in.
3. **Enfermagem:** abra o primeiro paciente elegível da fila, registre a triagem e selecione a classificação de risco apropriada para os dados fictícios.
4. **Médico/profissional:** abra o atendimento atribuído, inicie-o e conclua-o com um resumo exclusivamente fictício.
5. **Administrador:** mostre os filtros operacionais e o histórico/auditoria das transições realizadas.

Se não houver uma consulta preparada para o mesmo dia, mostre os painéis e as ações disponíveis sem criar dados reais nem alterar o relógio do computador.

## Alternativa reduzida — aproximadamente três minutos

1. Entre como **Paciente** e mostre a próxima consulta ou o fluxo de agendamento.
2. Entre como **Recepção** e mostre localização, validação de prioridade e check-in.
3. Entre como **Enfermagem** e mostre a fila e a triagem.
4. Entre como **Médico/profissional** e mostre o atendimento atribuído.
5. Entre como **Administrador** e encerre mostrando filtros e auditoria.

Na versão reduzida, apenas apresente as ações principais quando não for possível concluir todas as transições no tempo disponível.

## Cadastro e SMTP

O cadastro de um novo paciente exige confirmação por e-mail. O envio depende da configuração SMTP local em `backend/.env`; esse arquivo é privado, ignorado pelo Git e não acompanha o GitHub nem o ZIP público. Nenhuma senha SMTP é publicada.

Em uma instalação sem SMTP, use as contas fictícias acima. Isso preserva o fluxo de segurança: a confirmação de e-mail não foi removida e não existe código fixo público.
