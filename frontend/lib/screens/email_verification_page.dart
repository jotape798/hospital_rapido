part of '../main.dart';

class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({
    super.key,
    required this.email,
    this.sendOnOpen = true,
    this.initialResendSeconds = 0,
    this.verificationToken,
    this.api,
  });

  final String email;
  final bool sendOnOpen;
  final int initialResendSeconds;
  final String? verificationToken;
  final ApiService? api;

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final code = TextEditingController();
  final formKey = GlobalKey<FormState>();
  Timer? timer;
  int remaining = 0;
  bool sending = false, validating = false, verified = false;
  String? message;
  bool messageIsError = false;
  late String email;

  @override
  void initState() {
    super.initState();
    email = widget.email.trim().toLowerCase();
    if (widget.sendOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(initial: true));
    } else if (widget.initialResendSeconds > 0) {
      message = 'Código enviado. Confira sua caixa de entrada e o spam.';
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _startCountdown(widget.initialResendSeconds));
    }
  }

  void _startCountdown(int seconds) {
    timer?.cancel();
    setState(() => remaining = seconds);
    timer = Timer.periodic(const Duration(seconds: 1), (value) {
      if (!mounted) return value.cancel();
      if (remaining <= 1) {
        value.cancel();
        setState(() => remaining = 0);
      } else {
        setState(() => remaining--);
      }
    });
  }

  Future<void> _send({bool initial = false}) async {
    if (sending || (!initial && remaining > 0)) return;
    setState(() {
      sending = true;
      message = null;
    });
    try {
      final wait = initial
          ? await (widget.api ?? ApiService()).requestEmailVerification(email)
          : await (widget.api ?? ApiService()).resendEmailVerification(email);
      if (mounted) {
        _startCountdown(wait);
        setState(() {
          messageIsError = false;
          message = 'Código enviado. Confira sua caixa de entrada e o spam.';
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          messageIsError = true;
          message = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _validate() async {
    if (!validateAndFocus(formKey)) return;
    setState(() {
      validating = true;
      message = null;
    });
    try {
      final result = await (widget.api ?? ApiService())
          .validateEmailVerification(email, code.text.trim());
      if (mounted) {
        timer?.cancel();
        setState(() {
          verified = true;
          messageIsError = false;
          message = result;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          messageIsError = true;
          message = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => validating = false);
    }
  }

  Future<void> _correctEmail() async {
    if (widget.verificationToken == null) {
      Navigator.pop(context);
      return;
    }
    final controller = TextEditingController(text: email);
    final key = GlobalKey<FormState>();
    final updated = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Corrigir e-mail'),
              content: Form(
                  key: key,
                  child: TextFormField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    validator: emailRule,
                    decoration: const InputDecoration(labelText: 'Novo e-mail'),
                  )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Fechar')),
                FilledButton(
                    onPressed: () {
                      if (key.currentState?.validate() ?? false) {
                        Navigator.pop(dialogContext, controller.text.trim());
                      }
                    },
                    child: const Text('Salvar e reenviar')),
              ],
            ));
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (updated == null || !mounted) return;
    setState(() {
      sending = true;
      message = null;
    });
    try {
      await (widget.api ?? ApiService())
          .correctRegistrationEmail(widget.verificationToken!, updated);
      if (!mounted) return;
      setState(() {
        email = updated.toLowerCase();
        remaining = 0;
        code.clear();
        sending = false;
      });
      await _send(initial: true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          sending = false;
          messageIsError = true;
          message = error.message;
        });
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
      child: AuthLayout(
          child: Form(
              key: formKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandMark()),
                    const SizedBox(height: 22),
                    Text(
                        verified ? 'E-mail confirmado' : 'Verifique seu e-mail',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 27, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Text(
                        verified
                            ? 'Seu cadastro está pronto. Você já pode entrar com CPF e senha.'
                            : 'Enviamos um código de 6 dígitos para $email. Ele vale por 10 minutos.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    if (!verified)
                      Semantics(
                          textField: true,
                          label: 'Código de verificação de seis dígitos',
                          child: Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: TextFormField(
                                  key: const Key('email-verification-code'),
                                  controller: code,
                                  autofocus: true,
                                  keyboardType: TextInputType.number,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _validate(),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6)
                                  ],
                                  validator: (value) =>
                                      RegExp(r'^\d{6}$').hasMatch(value ?? '')
                                          ? null
                                          : 'Digite os 6 números do código.',
                                  decoration: const InputDecoration(
                                      labelText: 'Código de verificação',
                                      hintText: '000000',
                                      prefixIcon: Icon(
                                          Icons.verified_user_outlined))))),
                    if (message != null) ...[
                      Semantics(
                          liveRegion: true,
                          child: InfoPanel(
                              icon: messageIsError
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                              text: message!)),
                      const SizedBox(height: 16),
                    ],
                    if (verified)
                      AppActionButton(
                          label: 'Ir para o login',
                          icon: Icons.login,
                          expand: true,
                          onPressed: () => Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                  settings: const RouteSettings(name: '/login'),
                                  builder: (_) => LoginPage(api: widget.api)),
                              (_) => false))
                    else ...[
                      AppActionButton(
                          label: 'Validar código',
                          icon: Icons.verified_user_outlined,
                          onPressed: _validate,
                          busy: validating,
                          expand: true),
                      const SizedBox(height: 8),
                      OutlinedButton(
                          key: const Key('resend-email-code'),
                          onPressed:
                              sending || remaining > 0 ? null : () => _send(),
                          child: Text(sending
                              ? 'Enviando...'
                              : remaining > 0
                                  ? 'Reenviar código em ${remaining}s'
                                  : 'Reenviar código')),
                      TextButton.icon(
                          onPressed: _correctEmail,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Voltar e corrigir o e-mail'))
                    ]
                  ]))));
}
