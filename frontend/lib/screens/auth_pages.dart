part of '../main.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.api});
  final ApiService? api;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final document = TextEditingController(), password = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool busy = false, hide = true;

  @override
  void initState() {
    super.initState();
    password.addListener(_passwordChanged);
  }

  void _passwordChanged() {
    if (mounted) setState(() {});
  }

  Future<void> login() async {
    if (busy) return;
    if (!validateAndFocus(formKey)) {
      announceImportant(context, 'Corrija os campos obrigatórios.');
      return;
    }
    setState(() => busy = true);
    try {
      await (widget.api ?? ApiService()).login(document.text, password.text);
      if (mounted) {
        announceImportant(context, 'Login realizado');
        Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => homeForRole()), (_) => false);
      }
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    document.dispose();
    password.removeListener(_passwordChanged);
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
      showDecorativeWaves: true,
      child: AuthLayout(
          topAligned: true,
          cardKey: const Key('login-card'),
          child: Form(
              key: formKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandMark()),
                    const SizedBox(height: 28),
                    const Text('Acesse sua conta',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 28, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                        'Faça login para continuar com sua saúde sempre em dia.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    field(document, 'CPF', Icons.badge_outlined,
                        number: true,
                        autofillHints: const [AutofillHints.username],
                        semanticLabel: 'CPF, obrigatório',
                        validator: requiredCpf,
                        inputFormatters: [CpfFormatter()]),
                    field(password, 'Senha', Icons.lock_outline,
                        secret: hide,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => login(),
                        semanticLabel: 'Senha, obrigatória',
                        validator: (v) =>
                            (v ?? '').isEmpty ? 'Informe a senha.' : null,
                        suffix: IconButton(
                            tooltip: hide ? 'Mostrar senha' : 'Ocultar senha',
                            onPressed: () => setState(() => hide = !hide),
                            icon: Icon(hide
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined))),
                    AppActionButton(
                        label: 'Entrar →',
                        semanticLabel: 'Entrar no sistema',
                        icon: Icons.login,
                        onPressed: login,
                        busy: busy,
                        expand: true),
                    TextButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RecoveryPage())),
                        child: const Text('Esqueceu a senha?')),
                    const Divider(height: 32),
                    const Text('Ainda não tem uma conta?',
                        textAlign: TextAlign.center),
                    OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                settings:
                                    const RouteSettings(name: '/register'),
                                builder: (_) => const RegisterPage())),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: Semantics(
                            label: 'Criar cadastro',
                            excludeSemantics: true,
                            child: const Text('Cadastrar-se')))
                  ]))));
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, this.api});
  final ApiService? api;
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  Map<String, String> serverErrors = {};
  final personalKey = GlobalKey<FormState>();
  final contactKey = GlobalKey<FormState>();
  final guardianKey = GlobalKey<FormState>();
  final accountKey = GlobalKey<FormState>();
  final name = TextEditingController(),
      cpf = TextEditingController(),
      birth = TextEditingController(),
      email = TextEditingController(),
      phone = TextEditingController(),
      password = TextEditingController(),
      confirmation = TextEditingController(),
      guardianName = TextEditingController(),
      guardianCpf = TextEditingController(),
      guardianBirth = TextEditingController(),
      guardianPhone = TextEditingController(),
      guardianEmail = TextEditingController(),
      guardianOtherRelationship = TextEditingController();
  String relationship = 'Mãe';
  bool busy = false, hide = true, minor = false, allowPop = false;
  int currentStep = 0;
  String birthIso = '';
  final priorityConditions = <String>{};

  int get totalSteps => minor ? 4 : 3;

  List<String> get stepTitles => [
        'Dados pessoais',
        'Contato',
        if (minor) 'Responsável legal',
        'Acesso à conta',
      ];

  bool get hasDraft =>
      priorityConditions.isNotEmpty ||
      [
        name,
        cpf,
        birth,
        email,
        phone,
        password,
        confirmation,
        guardianName,
        guardianCpf,
        guardianBirth,
        guardianPhone,
        guardianEmail,
        guardianOtherRelationship,
      ].any((controller) => controller.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    password.addListener(_passwordChanged);
  }

  void _passwordChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _requestExit() async {
    if (busy) return;
    var discard = !hasDraft;
    if (!discard) {
      discard = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Sair do cadastro?'),
              content: const Text(
                  'Os dados preenchidos neste cadastro serão descartados.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Continuar cadastro')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Descartar dados')),
              ],
            ),
          ) ??
          false;
    }
    if (!discard || !mounted) return;
    setState(() => allowPop = true);
    Navigator.pop(context);
  }

  GlobalKey<FormState> get _currentFormKey => switch (stepTitles[currentStep]) {
        'Dados pessoais' => personalKey,
        'Contato' => contactKey,
        'Responsável legal' => guardianKey,
        _ => accountKey,
      };

  bool _validateCurrentStep() => validateAndFocus(_currentFormKey);

  Future<void> _continueRegistration() async {
    FocusScope.of(context).unfocus();
    if (!_validateCurrentStep()) {
      announceImportant(context, 'Corrija os campos indicados.');
      return;
    }
    if (currentStep == totalSteps - 1) {
      await register();
      return;
    }
    setState(() => currentStep++);
    announceImportant(context,
        'Etapa ${currentStep + 1} de $totalSteps: ${stepTitles[currentStep]}');
  }

  void _previousStep() {
    if (currentStep == 0 || busy) return;
    setState(() => currentStep--);
  }

  int _stepForServerField(String? field) => switch (field) {
        'cpf' || 'name' || 'birth_date' || 'priority_conditions' => 0,
        'email' || 'phone' => 1,
        'guardian_name' ||
        'guardian_cpf' ||
        'guardian_birth_date' ||
        'guardian_phone' ||
        'guardian_email' ||
        'guardian_relationship' ||
        'guardian_other_relationship' =>
          minor ? 2 : 1,
        _ => totalSteps - 1,
      };

  Future<void> chooseBirth() async {
    final picked = await showDatePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime.now(),
        initialDate: DateTime(2000));
    if (picked != null) {
      setState(() {
        birth.text =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
        birthIso =
            '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
        final now = DateTime.now();
        final isMinor = now.year -
                picked.year -
                ((now.month < picked.month ||
                        (now.month == picked.month && now.day < picked.day))
                    ? 1
                    : 0) <
            18;
        if (minor && !isMinor) {
          guardianName.clear();
          guardianCpf.clear();
          guardianBirth.clear();
          guardianPhone.clear();
          guardianEmail.clear();
          guardianOtherRelationship.clear();
          relationship = 'Mãe';
          serverErrors.removeWhere((field, _) => field.startsWith('guardian_'));
        }
        minor = isMinor;
      });
    }
  }

  Future<void> chooseGuardianBirth() async {
    final picked = await showDatePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime.now(),
        initialDate: DateTime(1980));
    if (picked != null) {
      setState(() => guardianBirth.text =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> register() async {
    if (busy) return;
    setState(() => serverErrors = {});
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (!_validateCurrentStep()) {
      notice(context, 'Corrija os campos indicados.');
      return;
    }
    final data = {
      'name': name.text.trim(),
      'cpf': digits(cpf.text),
      'birth_date': birthIso,
      'email': email.text.trim(),
      'phone': digits(phone.text),
      'password': password.text,
      'password_confirmation': confirmation.text,
      'priority_conditions': priorityConditions.toList(),
      if (minor) ...{
        'guardian_name': guardianName.text.trim(),
        'guardian_cpf': digits(guardianCpf.text),
        'guardian_birth_date': guardianBirth.text,
        'guardian_phone': digits(guardianPhone.text),
        'guardian_email': guardianEmail.text.trim(),
        'guardian_relationship': relationship,
        'guardian_other_relationship': relationship == 'Outro responsável legal'
            ? guardianOtherRelationship.text.trim()
            : null,
      }
    };
    setState(() => busy = true);
    try {
      final result = await (widget.api ?? ApiService()).register(data);
      if (mounted) {
        setState(() => allowPop = true);
        announceImportant(
            context, 'Cadastro iniciado. Confirme o código enviado ao seu e-mail.');
        Navigator.push(
            context,
            MaterialPageRoute(
                settings: const RouteSettings(name: '/email-verification'),
                builder: (_) => EmailVerificationPage(
                      email: result['email']?.toString() ?? email.text.trim(),
                      sendOnOpen: false,
                      initialResendSeconds:
                          (result['resend_after_seconds'] as num?)?.toInt() ?? 60,
                      verificationToken:
                          result['verification_token']?.toString(),
                      api: widget.api,
                    )));
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          serverErrors = {if (e.field != null) e.field!: e.message};
          currentStep = _stepForServerField(e.field);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) validateAndFocus(_currentFormKey);
        });
        notice(context, e.message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    password.removeListener(_passwordChanged);
    for (final c in [
      name,
      cpf,
      birth,
      email,
      phone,
      password,
      confirmation,
      guardianName,
      guardianCpf,
      guardianBirth,
      guardianPhone,
      guardianEmail,
      guardianOtherRelationship
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: allowPop || !hasDraft,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestExit();
      },
      child: AppPage(
          showDecorativeWaves: true,
          child: AuthLayout(
              topAligned: true,
              cardKey: const Key('registration-card'),
              child: FormTypography(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Center(
                        child: BrandMark(
                            compact: MediaQuery.sizeOf(context).width < 380)),
                    const SizedBox(height: 12),
                    Semantics(
                        header: true,
                        child: const Text('Criar conta',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 27, fontWeight: FontWeight.w800))),
                    const SizedBox(height: AppSpacing.sm),
                    Semantics(
                      container: true,
                      label:
                          'Etapa ${currentStep + 1} de $totalSteps: ${stepTitles[currentStep]}',
                      value: '${currentStep + 1} de $totalSteps',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              'Etapa ${currentStep + 1} de $totalSteps · ${stepTitles[currentStep]}',
                              key: const Key('registration-progress-label'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                          const SizedBox(height: AppSpacing.sm),
                          LinearProgressIndicator(
                              key: const Key('registration-progress'),
                              value: (currentStep + 1) / totalSteps),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AutofillGroup(child: _registrationStep()),
                    const SizedBox(height: AppSpacing.sm),
                    Row(children: [
                      if (currentStep > 0) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                              key: const Key('registration-back'),
                              onPressed: busy ? null : _previousStep,
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Voltar')),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      Expanded(
                        flex: currentStep > 0 ? 1 : 2,
                        child: AppActionButton(
                            key: const Key('registration-next'),
                            label: currentStep == totalSteps - 1
                                ? 'Cadastrar'
                                : 'Continuar',
                            semanticLabel: currentStep == totalSteps - 1
                                ? 'Criar cadastro'
                                : 'Continuar para ${stepTitles[currentStep + 1]}',
                            icon: currentStep == totalSteps - 1
                                ? Icons.person_add_alt_1
                                : Icons.arrow_forward,
                            onPressed: _continueRegistration,
                            busy: busy,
                            expand: true),
                      ),
                    ]),
                    TextButton(
                        onPressed: busy ? null : _requestExit,
                        child: const Text('Já tem uma conta? Fazer login'))
                  ])))));

  Widget _registrationStep() => switch (stepTitles[currentStep]) {
        'Dados pessoais' => Form(
            key: personalKey,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field(name, 'Nome completo', Icons.person_outline,
                      autofillHints: const [AutofillHints.name],
                      validator: requiredName,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ -]')),
                        LengthLimitingTextInputFormatter(80)
                      ]),
                  field(cpf, 'CPF', Icons.badge_outlined,
                      number: true,
                      semanticLabel: 'CPF, obrigatório',
                      hint: '000.000.000-00',
                      errorText: serverErrors['cpf'],
                      validator: requiredCpf,
                      inputFormatters: [CpfFormatter()]),
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Semantics(
                          label: 'Data de nascimento',
                          button: true,
                          child: TextFormField(
                              controller: birth,
                              readOnly: true,
                              onTap: chooseBirth,
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Selecione a data de nascimento.'
                                  : null,
                              decoration: const InputDecoration(
                                  labelText: 'Data de nascimento',
                                  prefixIcon:
                                      Icon(Icons.calendar_today_outlined),
                                  hintText: 'dd/MM/aaaa')))),
                  const InfoPanel(
                      icon: Icons.info_outline,
                      text:
                          'A prioridade para pessoa idosa é calculada automaticamente pela data de nascimento.'),
                  const SizedBox(height: 12),
                  Text('Condições prioritárias',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const Text(
                      'Você pode informar mais de uma condição. A prioridade somente será aplicada após confirmação presencial pela Recepção.'),
                  ...const {
                    'pcd': 'PCD',
                    'gestante': 'Gestante',
                    'lactante': 'Lactante'
                  }.entries.map((entry) => Semantics(
                      label:
                          '${entry.value}. Ao marcar, ficará aguardando confirmação presencial.',
                      child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(entry.value),
                          subtitle: priorityConditions.contains(entry.key)
                              ? const Text('Aguardando confirmação presencial')
                              : null,
                          value: priorityConditions.contains(entry.key),
                          onChanged: busy
                              ? null
                              : (selected) => setState(() => selected == true
                                  ? priorityConditions.add(entry.key)
                                  : priorityConditions.remove(entry.key))))),
                ])),
        'Contato' => Form(
            key: contactKey,
            child: Column(children: [
              field(email, 'E-mail', Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  errorText: serverErrors['email'],
                  validator: emailRule),
              field(phone, 'Telefone / celular', Icons.phone_outlined,
                  number: true,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  hint: '(00) 00000-0000',
                  validator: phoneRule,
                  inputFormatters: [PhoneFormatter()]),
              const InfoPanel(
                  icon: Icons.contact_phone_outlined,
                  text:
                      'Esses contatos serão usados para comunicações sobre consultas e acesso à conta.'),
            ])),
        'Responsável legal' => Form(
            key: guardianKey,
            child: Column(children: [
              const InfoPanel(
                  icon: Icons.family_restroom,
                  text:
                      'Os dados do responsável são obrigatórios para menores de 18 anos.'),
              const SizedBox(height: AppSpacing.md),
              field(guardianName, 'Nome completo do responsável',
                  Icons.person_outline,
                  autofillHints: const [AutofillHints.name],
                  errorText: serverErrors['guardian_name'],
                  validator: (v) => guardianNameRule(v, name.text),
                  inputFormatters: [LengthLimitingTextInputFormatter(80)]),
              field(guardianCpf, 'CPF do responsável', Icons.badge_outlined,
                  number: true,
                  errorText: serverErrors['guardian_cpf'],
                  validator: (v) => guardianCpfRule(v, cpf.text),
                  inputFormatters: [CpfFormatter()]),
              Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: TextFormField(
                      controller: guardianBirth,
                      readOnly: true,
                      onTap: chooseGuardianBirth,
                      validator: guardianBirthRule,
                      forceErrorText: serverErrors['guardian_birth_date'],
                      decoration: const InputDecoration(
                          labelText: 'Data de nascimento do responsável',
                          prefixIcon: Icon(Icons.calendar_today_outlined)))),
              field(guardianPhone, 'Telefone do responsável',
                  Icons.phone_outlined,
                  number: true,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  errorText: serverErrors['guardian_phone'],
                  validator: (v) => guardianPhoneRule(v, phone.text),
                  inputFormatters: [PhoneFormatter()]),
              field(
                  guardianEmail, 'E-mail do responsável', Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  errorText: serverErrors['guardian_email'],
                  validator: (v) => guardianEmailRule(v, email.text)),
              DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: relationship,
                  decoration: const InputDecoration(
                      labelText: 'Grau de parentesco do responsável'),
                  items: [
                    'Mãe',
                    'Pai',
                    'Avó/Avô',
                    'Tutor(a) legal',
                    'Outro responsável legal'
                  ]
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged:
                      busy ? null : (v) => setState(() => relationship = v!)),
              const SizedBox(height: AppSpacing.sm),
              if (relationship == 'Outro responsável legal')
                field(guardianOtherRelationship,
                    'Descrição do vínculo do responsável', Icons.edit_outlined,
                    errorText: serverErrors['guardian_other_relationship'],
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Descreva o parentesco do responsável legal.'
                        : null,
                    inputFormatters: [LengthLimitingTextInputFormatter(80)]),
              const SizedBox(height: AppSpacing.md),
            ])),
        _ => Form(
            key: accountKey,
            child: Column(children: [
              InfoPanel(
                  icon: Icons.fact_check_outlined,
                  text:
                      'Revise seus dados: ${name.text.trim()} · ${email.text.trim()}'),
              const SizedBox(height: AppSpacing.md),
              field(password, 'Senha', Icons.lock_outline,
                  secret: hide,
                  autofillHints: const [AutofillHints.newPassword],
                  semanticLabel: 'Senha, obrigatória',
                  validator: passwordRule,
                  suffix: IconButton(
                      tooltip: hide ? 'Mostrar senha' : 'Ocultar senha',
                      onPressed: () => setState(() => hide = !hide),
                      icon: Icon(hide
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined))),
              PasswordRules(password: password.text),
              field(confirmation, 'Confirmar senha', Icons.lock_outline,
                  secret: hide,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _continueRegistration(),
                  validator: (v) =>
                      v == password.text ? null : 'As senhas não conferem.'),
            ])),
      };
}

class ResponsiblePage extends StatefulWidget {
  const ResponsiblePage({super.key, required this.patientData, this.api});
  final Map<String, dynamic> patientData;
  final ApiService? api;
  @override
  State<ResponsiblePage> createState() => _ResponsiblePageState();
}

class _ResponsiblePageState extends State<ResponsiblePage> {
  final name = TextEditingController(),
      cpf = TextEditingController(),
      birth = TextEditingController(),
      phone = TextEditingController(),
      email = TextEditingController(),
      other = TextEditingController();
  final formKey = GlobalKey<FormState>();
  Map<String, String> serverErrors = {};
  String relationship = 'Mãe';
  bool busy = false;
  Future<void> pickBirth() async {
    final d = await showDatePicker(
        context: context,
        firstDate: DateTime(1900),
        lastDate: DateTime.now(),
        initialDate: DateTime(1980));
    if (d != null) {
      setState(() => birth.text =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> save() async {
    setState(() => serverErrors = {});
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (!validateAndFocus(formKey)) return;
    setState(() => busy = true);
    try {
      await (widget.api ?? ApiService()).register({
        ...widget.patientData,
        'guardian_name': name.text.trim(),
        'guardian_cpf': digits(cpf.text),
        'guardian_birth_date': birth.text,
        'guardian_relationship': relationship,
        'guardian_other_relationship': relationship == 'Outro responsável legal'
            ? other.text.trim()
            : null,
        'guardian_phone': digits(phone.text),
        'guardian_email': email.text.trim().isEmpty ? null : email.text.trim()
      });
      if (mounted) {
        announceImportant(
            context, 'Cadastro concluído. Faça login para entrar.');
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
                settings: const RouteSettings(name: '/login'),
                builder: (_) => LoginPage(api: widget.api)),
            (_) => false);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(
            () => serverErrors = {if (e.field != null) e.field!: e.message});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) validateAndFocus(formKey);
        });
        notice(context, e.message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in [name, cpf, birth, phone, email, other]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppPage(
      showDecorativeWaves: true,
      child: AuthLayout(
          child: Form(
              key: formKey,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Responsável legal',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 27, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                        'Dados obrigatórios para concluir o cadastro do menor.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    field(name, 'Nome completo do responsável',
                        Icons.person_outline,
                        errorText: serverErrors['guardian_name'],
                        validator: (v) => guardianNameRule(
                            v, widget.patientData['name'] ?? '')),
                    field(cpf, 'CPF do responsável', Icons.badge_outlined,
                        number: true,
                        errorText: serverErrors['guardian_cpf'],
                        validator: (v) =>
                            guardianCpfRule(v, widget.patientData['cpf'] ?? ''),
                        inputFormatters: [CpfFormatter()]),
                    Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: TextFormField(
                            controller: birth,
                            readOnly: true,
                            onTap: pickBirth,
                            validator: guardianBirthRule,
                            forceErrorText: serverErrors['guardian_birth_date'],
                            decoration: const InputDecoration(
                                labelText: 'Data de nascimento',
                                prefixIcon:
                                    Icon(Icons.calendar_today_outlined)))),
                    DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: relationship,
                        decoration: const InputDecoration(
                            labelText: 'Parentesco',
                            prefixIcon: Icon(Icons.family_restroom)),
                        items: const [
                          DropdownMenuItem(value: 'Mãe', child: Text('Mãe')),
                          DropdownMenuItem(value: 'Pai', child: Text('Pai')),
                          DropdownMenuItem(
                              value: 'Avó/Avô', child: Text('Avó/Avô')),
                          DropdownMenuItem(
                              value: 'Tutor(a) legal',
                              child: Text('Tutor(a) legal')),
                          DropdownMenuItem(
                              value: 'Outro responsável legal',
                              child: Text('Outro responsável legal'))
                        ],
                        onChanged: (v) => setState(() => relationship = v!)),
                    const SizedBox(height: 16),
                    if (relationship == 'Outro responsável legal')
                      field(other, 'Descreva o parentesco', Icons.edit_outlined,
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Informe o parentesco.'
                              : null),
                    field(phone, 'Telefone / celular', Icons.phone_outlined,
                        number: true,
                        errorText: serverErrors['guardian_phone'],
                        validator: (v) => guardianPhoneRule(
                            v, widget.patientData['phone'] ?? ''),
                        inputFormatters: [PhoneFormatter()]),
                    field(email, 'E-mail do responsável', Icons.email_outlined,
                        errorText: serverErrors['guardian_email'],
                        validator: (v) => guardianEmailRule(
                            v, widget.patientData['email'] ?? '')),
                    AppActionButton(
                        label: 'Concluir cadastro',
                        icon: Icons.check_circle_outline,
                        onPressed: save,
                        busy: busy,
                        expand: true)
                  ]))));
}
