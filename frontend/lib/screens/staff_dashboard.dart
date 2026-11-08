part of '../main.dart';

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({super.key, this.api});
  final ApiService? api;

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard> {
  late final ApiService api = widget.api ?? ApiService();
  final search = TextEditingController();
  DateTime day = DateTime.now();
  Map<String, dynamic> summary = {};
  List<AdminAppointment> items = [];
  final specialties = <String>{};
  final professionals = <int, String>{};
  String? specialty, status, risk;
  int? professionalId;
  bool loading = true, working = false;
  String? loadError;

  bool get isReception => ApiService.session?.role == 'recepcao';
  bool get isNursing => ApiService.session?.role == 'enfermagem';
  bool get isProfessional =>
      ApiService.session?.role == 'medico' ||
      ApiService.session?.role == 'profissional';

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (working) return;
    working = true;
    if (!loading && mounted) setState(() {});
    try {
      if (isNursing) {
        final result = await Future.wait([
          api.nursingSummary(day),
          api.nursingQueue(
              day: day, specialty: specialty, status: status, risk: risk),
        ]);
        summary = result[0] as Map<String, dynamic>;
        items = result[1] as List<AdminAppointment>;
      } else if (isProfessional) {
        items = await api.professionalQueue(day);
        summary = {
          'awaiting': items.where((item) => item.status == 'em_triagem').length,
          'in_care':
              items.where((item) => item.status == 'em_atendimento').length,
        };
      } else {
        final result = await Future.wait([
          api.receptionSummary(day),
          api.receptionAppointments(
              day: day,
              specialty: specialty,
              professionalId: professionalId,
              status: status,
              patient: search.text),
        ]);
        summary = result[0] as Map<String, dynamic>;
        items = result[1] as List<AdminAppointment>;
      }
      for (final item in items) {
        specialties.add(item.specialty);
        professionals[item.professionalId] = item.professional;
      }
      loadError = null;
    } on ApiException catch (e) {
      loadError = e.message;
    } finally {
      working = false;
      if (mounted) setState(() => loading = false);
    }
  }

  bool get _hasActiveFilters =>
      specialty != null ||
      professionalId != null ||
      status != null ||
      risk != null ||
      search.text.trim().isNotEmpty;

  Future<void> _clearFilters() async {
    if (working) return;
    setState(() {
      specialty = null;
      professionalId = null;
      status = null;
      risk = null;
      search.clear();
    });
    await load();
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (working) return;
    setState(() => working = true);
    try {
      await action();
      working = false;
      await load();
      if (mounted) notice(context, success);
    } on ApiException catch (e) {
      working = false;
      if (mounted) {
        setState(() {});
        notice(context, e.message);
      }
    }
  }

  Future<bool> _confirm(String title, String message, String label) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) =>
              AlertDialog(title: Text(title), content: Text(message), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Voltar')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(label)),
              ])) ??
      false;

  Future<void> _logout() async {
    await ApiService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
    }
  }

  Future<void> _chooseDay() async {
    final chosen = await showDatePicker(
        context: context,
        initialDate: day,
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (chosen != null) {
      setState(() => day = chosen);
      await load();
    }
  }

  Future<void> _details(AdminAppointment item) async {
    try {
      final value = isNursing
          ? await api.nursingDetails(item.id)
          : isProfessional
              ? await api.professionalDetails(item.id)
              : await api.receptionDetails(item.id);
      if (!mounted) return;
      final conditions = (value['priority_conditions'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text(value['patient']?.toString() ?? 'Agendamento'),
                  content: SingleChildScrollView(
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(value['patient_document']?.toString() ?? ''),
                        Text(
                            'Especialidade: ${specialtyDisplayName(value['specialty'].toString())}'),
                        Text('Profissional: ${value['professional']}'),
                        Text(
                            'Horário: ${showDate(DateTime.parse(value['scheduled_at']))}'),
                        Text('Status: ${statusLabel(value['status'])}'),
                        Text(
                            'Prioridade: ${value['priority_reason'] ?? 'Sem prioridade legal'}'),
                        if (conditions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('Condições prioritárias',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          ...conditions.map((condition) {
                            final code = condition['condition'].toString();
                            final status = condition['status'].toString();
                            final label = switch (code) {
                              'pcd' => 'PCD',
                              'gestante' => 'Gestante',
                              'lactante' => 'Lactante',
                              _ => code,
                            };
                            return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      '$label — ${status == 'pendente' ? 'Aguardando confirmação presencial' : status}'),
                                  if (condition['validated_by'] != null)
                                    Text(
                                        'Validado por ${condition['validated_by']} em ${showDate(DateTime.parse(condition['validated_at']))}'),
                                  if (isReception && status == 'pendente')
                                    Wrap(spacing: 8, children: [
                                      TextButton(
                                          onPressed: () async {
                                            Navigator.pop(context);
                                            await _validateCondition(item, code,
                                                'confirmada', label);
                                          },
                                          child: const Text('Confirmar')),
                                      TextButton(
                                          onPressed: () async {
                                            Navigator.pop(context);
                                            await _validateCondition(
                                                item, code, 'rejeitada', label);
                                          },
                                          child: const Text('Rejeitar')),
                                    ])
                                ]);
                          }),
                        ],
                        if (value['arrived_at'] != null)
                          Text(
                              'Chegada: ${showDate(DateTime.parse(value['arrived_at']))}'),
                        if (value['risk_classification'] != null)
                          AppRiskIndicator(
                              risk: value['risk_classification'].toString()),
                        if (value['triage_complaint'] != null)
                          Text('Queixa: ${value['triage_complaint']}'),
                        if (value['vital_signs'] != null)
                          Text('Sinais vitais: ${value['vital_signs']}'),
                        if (value['triage_observation'] != null)
                          Text('Observação: ${value['triage_observation']}'),
                      ])),
                  actions: [
                    FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fechar'))
                  ]));
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    }
  }

  Future<void> _validateCondition(AdminAppointment item, String condition,
      String status, String label) async {
    final verb = status == 'confirmada' ? 'confirmar' : 'rejeitar';
    if (!await _confirm(
        '${verb[0].toUpperCase()}${verb.substring(1)} $label?',
        'Confirme a validação presencial de $label para ${item.patient}.',
        status == 'confirmada' ? 'Confirmar' : 'Rejeitar')) {
      return;
    }
    await _run(
        () =>
            api.receptionValidatePriorityCondition(item.id, condition, status),
        '$label ${status == 'confirmada' ? 'confirmada' : 'rejeitada'} com sucesso.');
  }

  Future<void> _checkIn(AdminAppointment item) async {
    if (!await _confirm('Confirmar chegada?',
        'Registrar o check-in presencial de ${item.patient}?', 'Confirmar')) {
      return;
    }
    await _run(() => api.receptionCheckIn(item.id),
        'Check-in registrado com sucesso.');
  }

  Future<void> _absence(AdminAppointment item) async {
    if (!await _confirm('Marcar não comparecimento?',
        'Confirmar que ${item.patient} não compareceu?', 'Marcar ausência')) {
      return;
    }
    await _run(
        () => api.receptionAbsence(item.id), 'Não comparecimento registrado.');
  }

  Future<void> _classify(AdminAppointment item) async {
    final value = await showDialog<List<String?>>(
        context: context, builder: (_) => const _RiskDialog());
    if (value == null) {
      return;
    }
    await _run(
        () => api.classifyRisk(
            item.id, value[0]!, value[1]!, value[2]!, value[3]),
        'Triagem concluída com sucesso.');
  }

  Future<void> _start(AdminAppointment item) async {
    if (!await _confirm('Iniciar atendimento?',
        'Iniciar o atendimento de ${item.patient}?', 'Iniciar')) {
      return;
    }
    await _run(
        () => api.startCare(item.id), 'Atendimento iniciado com sucesso.');
  }

  Future<void> _call(AdminAppointment item) async {
    await _run(() => api.callPatient(item.id), 'Paciente chamado com sucesso.');
  }

  Future<void> _complete(AdminAppointment item) async {
    if (!await _confirm('Concluir atendimento?',
        'Concluir o atendimento de ${item.patient}?', 'Concluir')) {
      return;
    }
    await _run(
        () => api.completeCare(item.id), 'Atendimento concluído com sucesso.');
  }

  @override
  Widget build(BuildContext context) {
    final title = isNursing
        ? 'Painel da Enfermagem'
        : isProfessional
            ? 'Painel do Profissional de Saúde'
            : 'Painel da Recepção';
    return ResponsiveAppShell(
        wideNavigationMode: WideNavigationMode.contentOnly,
        title: title,
        subtitle: ApiService.session?.name,
        primaryAction: Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              onPressed: working ? null : load,
              icon: const Icon(Icons.refresh),
              label: const Text('Atualizar')),
          OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Sair')),
        ]),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: load,
                child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(children: [
                      if (isNursing) ...[
                        const AppSurfaceCard(
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Icon(Icons.info_outline),
                              SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text('Simulação acadêmica',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    SizedBox(height: 4),
                                    Text(
                                        'A classificação de risco é manual, deve ser feita somente por profissional autorizado e não substitui uma avaliação real.')
                                  ]))
                            ])),
                        const SizedBox(height: 12),
                      ],
                      _summaryCards(),
                      const SizedBox(height: 12),
                      _filters(),
                      const SizedBox(height: 12),
                      Semantics(
                          key: const Key('staff-results-region'),
                          container: true,
                          label: 'Resultados dos atendimentos',
                          child: Column(children: [
                            if (loadError != null) ...[
                              AppErrorState(
                                message: items.isEmpty
                                    ? '${loadError!} Verifique sua conexão e tente novamente.'
                                    : '${loadError!} Os atendimentos abaixo podem estar desatualizados.',
                                onAction: working ? null : load,
                              ),
                              if (items.isNotEmpty)
                                const SizedBox(height: AppSpacing.md),
                            ],
                            if (items.isEmpty && loadError == null)
                              AppEmptyState(
                                icon: Icons.filter_alt_off_outlined,
                                title: 'Nenhum atendimento encontrado',
                                message:
                                    'Não há atendimentos para os filtros selecionados.',
                                actionLabel:
                                    _hasActiveFilters ? 'Limpar filtros' : null,
                                onAction: _hasActiveFilters && !working
                                    ? _clearFilters
                                    : null,
                              )
                            else if (items.isNotEmpty)
                              for (final item in items) _itemCard(item),
                          ])),
                      const SizedBox(height: 100),
                    ]))));
  }

  Widget _summaryCards() {
    final cards = isNursing
        ? <(String, int, IconData, Color)>[
            (
              'Aguardando triagem',
              summary['awaiting_triage'] ?? 0,
              Icons.groups_outlined,
              Color(0xFF8A5A00)
            ),
            (
              'Em atendimento',
              summary['in_care'] ?? 0,
              Icons.medical_services_outlined,
              Color(0xFF6A3DA6)
            ),
            (
              'Concluídas',
              summary['completed'] ?? 0,
              Icons.task_alt_outlined,
              Color(0xFF2E7D32)
            ),
          ]
        : isProfessional
            ? <(String, int, IconData, Color)>[
                (
                  'Encaminhados',
                  summary['awaiting'] ?? 0,
                  Icons.campaign_outlined,
                  Color(0xFF005A9C)
                ),
                (
                  'Em atendimento',
                  summary['in_care'] ?? 0,
                  Icons.medical_services_outlined,
                  Color(0xFF6A3DA6)
                ),
              ]
            : <(String, int, IconData, Color)>[
                (
                  'Agendadas',
                  summary['scheduled'] ?? 0,
                  Icons.event_outlined,
                  Color(0xFF005A9C)
                ),
                (
                  'Check-in',
                  summary['checked_in'] ?? 0,
                  Icons.how_to_reg,
                  Color(0xFF0F766E)
                ),
                (
                  'Em atendimento',
                  summary['in_care'] ?? 0,
                  Icons.medical_services_outlined,
                  Color(0xFF6A3DA6)
                ),
                (
                  'Concluídas',
                  summary['completed'] ?? 0,
                  Icons.task_alt_outlined,
                  Color(0xFF2E7D32)
                ),
                (
                  'Não compareceu',
                  summary['absent'] ?? 0,
                  Icons.person_off_outlined,
                  Color(0xFFB42318)
                ),
              ];
    Widget workflowCards() => LayoutBuilder(builder: (_, constraints) {
          final width = constraints.maxWidth < 620
              ? constraints.maxWidth
              : constraints.maxWidth < 980
                  ? (constraints.maxWidth - 12) / 2
                  : (constraints.maxWidth - 36) / 4;
          return Wrap(
            key: isNursing ? const Key('nursing-workflow-summary') : null,
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final card in cards)
                SizedBox(
                  width: width,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Row(children: [
                        Icon(card.$3,
                            color: accessibility.highContrast
                                ? Colors.yellow
                                : card.$4),
                        const SizedBox(width: 10),
                        Expanded(child: Text(card.$1, softWrap: true)),
                        Text('${card.$2}',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: accessibility.highContrast
                                    ? Colors.yellow
                                    : card.$4)),
                      ]),
                    ),
                  ),
                ),
            ],
          );
        });
    if (!isNursing) return workflowCards();

    final riskCounts = summary['risk_counts'] as Map? ?? const {};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      workflowCards(),
      const SizedBox(height: AppSpacing.md),
      LayoutBuilder(builder: (_, constraints) {
        final compact = constraints.maxWidth < 700;
        final width = compact
            ? (constraints.maxWidth - AppSpacing.sm) / 2
            : (constraints.maxWidth - AppSpacing.sm * 3) / 4;
        return Wrap(
          key: const Key('nursing-risk-summary'),
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final code in RiskClassification.values)
              SizedBox(
                key: Key('nursing-risk-card-$code'),
                width: width,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Row(children: [
                      Expanded(
                          child: AppRiskIndicator(risk: code, prefix: false)),
                      const SizedBox(width: AppSpacing.xs),
                      Text('${riskCounts[code] ?? 0}',
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: blue)),
                    ]),
                  ),
                ),
              ),
          ],
        );
      }),
    ]);
  }

  Widget _filters() => LayoutBuilder(builder: (context, constraints) {
        final compactFilters = constraints.maxWidth < 600;
        final innerWidth =
            (constraints.maxWidth - (compactFilters ? 28 : AppSpacing.lg * 2))
                .clamp(0.0, double.infinity);
        final controlWidth = responsiveFilterWidth(innerWidth);
        final controls = Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(
              width: controlWidth,
              child: OutlinedButton.icon(
                  key: const Key('staff-filter-date'),
                  onPressed: _chooseDay,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(showOnlyDate(day)))),
          if (isReception)
            SizedBox(
                width: controlWidth,
                child: Semantics(
                    textField: true,
                    label: 'Localizar agendamento por nome ou CPF',
                    child: TextField(
                        key: const Key('staff-search'),
                        controller: search,
                        onSubmitted: (_) => load(),
                        decoration: InputDecoration(
                            labelText: 'Paciente',
                            hintText: 'Nome ou CPF',
                            prefixIcon: const ExcludeSemantics(
                                child: Icon(Icons.search)),
                            suffixIcon: IconButton(
                                tooltip: 'Buscar',
                                onPressed: load,
                                icon: const Icon(Icons.arrow_forward)))))),
          _dropdown('Especialidade', specialty,
              specialties.map((x) => (x, specialtyDisplayName(x))).toList(),
              (value) {
            setState(() => specialty = value);
            load();
          }, key: const Key('staff-filter-specialty'), width: controlWidth),
          if (isReception)
            _dropdown(
                'Profissional',
                professionalId?.toString(),
                professionals.entries
                    .map((x) => (x.key.toString(), x.value))
                    .toList(), (value) {
              setState(() => professionalId = int.tryParse(value ?? ''));
              load();
            },
                key: const Key('staff-filter-professional'),
                width: controlWidth),
          _dropdown(
              'Status',
              status,
              ((isNursing || isProfessional)
                      ? const {
                          'em_espera': 'Aguardando triagem',
                          'em_triagem': 'Em triagem',
                          'em_atendimento': 'Em atendimento',
                          'concluido': 'Concluída',
                        }
                      : const {
                          'agendado': 'Agendada',
                          'em_espera': 'Check-in realizado',
                          'em_triagem': 'Em triagem',
                          'em_atendimento': 'Em atendimento',
                          'concluido': 'Concluída',
                          'falta': 'Não compareceu',
                          'cancelado': 'Cancelada',
                        })
                  .entries
                  .map((x) => (x.key, x.value))
                  .toList(), (value) {
            setState(() => status = value);
            load();
          }, key: const Key('staff-filter-status'), width: controlWidth),
          if (isNursing)
            _dropdown(
                'Classificação de risco', risk, RiskClassification.options,
                (value) {
              setState(() => risk = value);
              load();
            },
                key: const Key('staff-filter-risk'),
                width: controlWidth,
                itemBuilder: (item) => AppRiskFilterItem(risk: item.$1)),
        ]);
        if (compactFilters) {
          return Card(
              key: const Key('staff-compact-filters'),
              child: ExpansionTile(
                  leading: const Icon(Icons.filter_alt_outlined),
                  title: const Text('Filtros'),
                  childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  children: [controls]));
        }
        return Semantics(
            key: const Key('staff-filter-region'),
            container: true,
            label: 'Filtros de atendimentos',
            child: AppSurfaceCard(child: controls));
      });

  Widget _dropdown(String label, String? value, List<(String, String)> values,
          ValueChanged<String?> changed,
          {Key? key,
          double width = 210,
          Widget Function((String, String))? itemBuilder}) =>
      SizedBox(
          width: width,
          child: DropdownButtonFormField<String>(
              key: key,
              initialValue: value,
              isExpanded: true,
              itemHeight: null,
              decoration: InputDecoration(labelText: label),
              items: [
                const DropdownMenuItem(value: '', child: Text('Todos')),
                for (final item in values)
                  DropdownMenuItem(
                      value: item.$1,
                      child: itemBuilder?.call(item) ??
                          Text(item.$2, softWrap: true, maxLines: 2)),
              ],
              onChanged: (value) =>
                  changed(value?.isEmpty ?? true ? null : value)));

  Widget _itemCard(AdminAppointment item) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
          key: Key('staff-appointment-card-${item.id}'),
          child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: LayoutBuilder(builder: (_, constraints) {
                final info = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.patient,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: AppSpacing.sm),
                      _careInformationLine(
                          Icons.badge_outlined, item.patientDocument),
                      _careInformationLine(Icons.medical_information_outlined,
                          'Especialidade: ${specialtyDisplayName(item.specialty)}'),
                      _careInformationLine(Icons.person_outline,
                          'Profissional: ${item.professional}'),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            Text('Horário: ${showDate(item.scheduledAt)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            AppStatusBadge(
                                label: statusLabel(item.status),
                                tone: statusToneFor(item.status),
                                semanticLabel:
                                    'Situação: ${statusLabel(item.status)}'),
                          ]),
                      if (item.arrivedAt != null)
                        Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Text('Chegada: ${showDate(item.arrivedAt!)}',
                                style: Theme.of(context).textTheme.bodyLarge)),
                      Text('Prioridade: ${item.priorityReason}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                  fontWeight: item.legalPriority == 'geral'
                                      ? FontWeight.normal
                                      : FontWeight.w700,
                                  color: item.legalPriority == 'geral'
                                      ? null
                                      : green)),
                      if (item.risk != null)
                        Align(
                            alignment: Alignment.centerLeft,
                            child: AppRiskIndicator(risk: item.risk)),
                      if (item.triageObservation?.isNotEmpty ?? false)
                        Text('Observação: ${item.triageObservation}'),
                      if (item.triageComplaint?.isNotEmpty ?? false)
                        Text('Queixa: ${item.triageComplaint}'),
                      if (item.vitalSigns?.isNotEmpty ?? false)
                        Text('Sinais vitais: ${item.vitalSigns}'),
                      if (isProfessional) ...[
                        const SizedBox(height: 8),
                        const Text('1. Chamar  2. Iniciar  3. Concluir',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ]);
                final detailsButton = OutlinedButton.icon(
                    key: Key('staff-details-button-${item.id}'),
                    onPressed: () => _details(item),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Detalhes'));
                final operationalActions = Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    alignment: WrapAlignment.end,
                    children: [
                      if (isReception && item.status == 'agendado')
                        AppActionButton(
                            onPressed: working ? null : () => _checkIn(item),
                            icon: Icons.how_to_reg,
                            label: 'Check-in',
                            semanticLabel: 'Registrar check-in'),
                      if (isReception && item.status == 'agendado')
                        Semantics(
                            button: true,
                            label: 'Registrar no-show ou falta',
                            excludeSemantics: true,
                            child: OutlinedButton.icon(
                                onPressed:
                                    working ? null : () => _absence(item),
                                icon: const Icon(Icons.person_off_outlined),
                                label: const Text('Não compareceu'))),
                      if (isNursing &&
                          const {'em_espera', 'em_triagem'}
                              .contains(item.status))
                        AppActionButton(
                            key: Key('triage-action-${item.id}'),
                            onPressed: working || !item.triageActionAllowed
                                ? null
                                : () => _classify(item),
                            icon: Icons.flag_outlined,
                            semanticLabel: 'Concluir triagem',
                            label: item.status == 'em_triagem'
                                ? 'Reclassificar risco'
                                : 'Classificar risco'),
                      if (isNursing &&
                          const {'em_espera', 'em_triagem'}
                              .contains(item.status) &&
                          !item.triageActionAllowed)
                        SizedBox(
                            width: 230,
                            child: Text(
                                item.triageBlockReason ??
                                    'Outro paciente está à frente na fila.',
                                key: Key('triage-order-message-${item.id}'),
                                style: Theme.of(context).textTheme.bodySmall)),
                      if (isProfessional && item.status == 'em_triagem')
                        OutlinedButton.icon(
                            onPressed: working ? null : () => _call(item),
                            icon: const Icon(Icons.campaign_outlined),
                            label: Text(item.calledAt == null
                                ? 'Chamar paciente'
                                : 'Chamar novamente')),
                      if (isProfessional && item.status == 'em_triagem')
                        AppActionButton(
                            onPressed: working ? null : () => _start(item),
                            icon: Icons.play_arrow,
                            label: 'Iniciar atendimento'),
                      if (isProfessional && item.status == 'em_atendimento')
                        AppActionButton(
                            onPressed: working ? null : () => _complete(item),
                            icon: Icons.task_alt,
                            label: 'Concluir atendimento'),
                    ]);
                final trailing = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      detailsButton,
                      if (operationalActions.children.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        operationalActions,
                      ],
                    ]);
                return constraints.maxWidth < 760
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                            info,
                            const SizedBox(height: AppSpacing.md),
                            Align(
                                alignment: Alignment.centerRight,
                                child: trailing),
                          ])
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                            Expanded(child: info),
                            const SizedBox(width: AppSpacing.lg),
                            trailing
                          ]);
              }))));

  Widget _careInformationLine(IconData icon, String value) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: accessibility.highContrast ? null : blue),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
              child: Text(value, style: Theme.of(context).textTheme.bodyLarge)),
        ]),
      );
}

class _RiskDialog extends StatefulWidget {
  const _RiskDialog();

  @override
  State<_RiskDialog> createState() => _RiskDialogState();
}

class _RiskDialogState extends State<_RiskDialog> {
  final formKey = GlobalKey<FormState>();
  final complaint = TextEditingController();
  final vitalSigns = TextEditingController();
  final observation = TextEditingController();
  String? level;

  @override
  void dispose() {
    complaint.dispose();
    vitalSigns.dispose();
    observation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          actionsOverflowDirection: VerticalDirection.down,
          title: const Text('Classificação de risco manual'),
          content: SingleChildScrollView(
              child: SizedBox(
                  width: MediaQuery.sizeOf(context).width >= 900 ? 820 : 520,
                  child: Form(
                      key: formKey,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        AppRiskSelector(
                            value: level,
                            onChanged: (value) =>
                                setState(() => level = value)),
                        const SizedBox(height: 12),
                        Semantics(
                            textField: true,
                            label: 'Queixa principal, obrigatória',
                            child: TextFormField(
                                key: const Key('triage-complaint'),
                                controller: complaint,
                                maxLength: 500,
                                minLines: 2,
                                maxLines: 4,
                                validator: (value) =>
                                    (value ?? '').trim().length < 3
                                        ? 'Informe a queixa principal.'
                                        : null,
                                decoration: const InputDecoration(
                                    labelText: 'Queixa principal',
                                    hintText:
                                        'Relato fictício apresentado pelo paciente.'))),
                        const SizedBox(height: 12),
                        Semantics(
                            textField: true,
                            label: 'Sinais vitais, obrigatórios',
                            child: TextFormField(
                                key: const Key('triage-vital-signs'),
                                controller: vitalSigns,
                                maxLength: 500,
                                minLines: 2,
                                maxLines: 4,
                                validator: (value) =>
                                    (value ?? '').trim().length < 3
                                        ? 'Informe os sinais vitais aferidos.'
                                        : null,
                                decoration: const InputDecoration(
                                    labelText: 'Sinais vitais aferidos',
                                    hintText:
                                        'Ex.: PA e temperatura fictícias para demonstração.'))),
                        const SizedBox(height: 12),
                        TextField(
                            controller: observation,
                            maxLength: 500,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                                labelText: 'Observação curta (opcional)',
                                hintText:
                                    'Registre somente a observação necessária.')),
                      ])))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            Semantics(
                button: true,
                label: 'Concluir triagem',
                excludeSemantics: true,
                child: FilledButton(
                    onPressed: () {
                      if (!(formKey.currentState?.validate() ?? false)) {
                        announceImportant(context,
                            'Preencha os campos obrigatórios da triagem.');
                        return;
                      }
                      Navigator.pop(context, <String?>[
                        level,
                        complaint.text.trim(),
                        vitalSigns.text.trim(),
                        observation.text.trim()
                      ]);
                    },
                    child: const Text('Salvar classificação'))),
          ]);
}
