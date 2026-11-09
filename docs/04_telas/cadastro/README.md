# Telas de cadastro e confirmação de e-mail

## Cadastro do paciente

- **Finalidade:** criar exclusivamente uma conta de paciente.
- **Perfil:** público.
- **Campos obrigatórios:** nome completo, CPF, data de nascimento, e-mail, telefone, senha e confirmação da senha. A autodeclaração de PCD/gestante/lactante é opcional; CNS é opcional/legado e não serve para login.
- **Prioridade:** “Idoso 60+” não é selecionável; é calculado no backend pela data de nascimento. As demais condições aparecem como aguardando confirmação presencial.
- **Orientação:** “Você pode informar mais de uma condição. A prioridade somente será aplicada após confirmação presencial pela Recepção.”
- **Ações:** continuar, voltar e mostrar/ocultar senha.
- **Validações:** nome, CPF, data entre os limites aceitos, e-mail, telefone e senha forte; CPF/e-mail não podem se repetir.
- **Maior de idade:** dados de responsável eventualmente enviados são descartados pela API e não criam vínculo.
- **Frontend:** `frontend/lib/screens/auth_pages.dart` (`RegisterPage`).
- **API:** `POST /auth/register`.

## Responsável legal

- **Finalidade:** coletar e vincular responsável quando o paciente é menor.
- **Campos:** nome, CPF, nascimento, parentesco, telefone e e-mail do responsável.
- **Validações:** responsável maior de idade e dados diferentes dos dados do paciente; responsáveis já existentes podem ser compartilhados de forma consistente.
- **Obrigatoriedade:** para paciente menor de 18 anos, nome, CPF, data de nascimento, parentesco, telefone e e-mail do responsável são exigidos no cadastro.
- **Frontend:** `frontend/lib/screens/auth_pages.dart` (`RegisterPage`, etapa **Responsável legal**). `ResponsiblePage` permanece apenas como tela compatível com o fluxo legado.
- **Próxima:** confirmação obrigatória do e-mail antes do primeiro login.

## Confirmação obrigatória de e-mail

- **Finalidade:** comprovar a posse do endereço informado. A conta do paciente permanece indisponível e não recebe sessão antes da confirmação.
- **Campos:** código numérico de seis dígitos, válido por 10 minutos; opção segura de corrigir o e-mail.
- **Ações:** validar, reenviar depois de 60 segundos, corrigir o endereço e ir ao login após a confirmação.
- **Segurança:** cada código permite no máximo cinco tentativas, é armazenado somente como hash e deixa de valer quando utilizado ou substituído por reenvio.
- **Falha de envio:** se o serviço de e-mail estiver indisponível, a transação de cadastro é revertida e a API responde com erro seguro, sem deixar uma conta parcialmente criada nem expor detalhes internos.
- **Frontend:** `frontend/lib/screens/email_verification_page.dart`.
- **API:** `POST /auth/email/solicitar-codigo`, `/reenviar-codigo`, `/corrigir` e `/validar-codigo`.
