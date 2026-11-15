part of '../main.dart';

enum AdminArea {
  attendance('Atendimento', 'Rotina e fluxo dos pacientes.',
      Icons.monitor_heart_outlined, Color(0xFF0F6B3A)),
  schedule('Agenda e oferta', 'Consultas, horários e serviços.',
      Icons.calendar_month_outlined, Color(0xFF005A9C)),
  people('Pessoas e acessos', 'Profissionais e contas do sistema.',
      Icons.groups_outlined, Color(0xFF6A3DA6)),
  governance('Governança', 'Atividades e configurações.', Icons.policy_outlined,
      Color(0xFF9A4A00));

  const AdminArea(this.label, this.description, this.icon, this.color);
  final String label;
  final String description;
  final IconData icon;
  final Color color;
}

enum AdminSection {
  overview(AdminArea.attendance, 'Visão geral',
      'Indicadores das consultas de hoje.', Icons.dashboard_outlined),
  agenda(AdminArea.schedule, 'Agenda do dia',
      'Consulte consultas por data e filtros.', Icons.today_outlined),
  appointments(AdminArea.schedule, 'Agendamentos',
      'Veja e gerencie os agendamentos.', Icons.event_note_outlined),
  checkin(AdminArea.attendance, 'Confirmar chegada',
      'Registre check-in ou falta.', Icons.how_to_reg_outlined),
  queue(AdminArea.attendance, 'Fila de atendimento',
      'Acompanhe pacientes aguardando.', Icons.groups_outlined),
  grids(AdminArea.schedule, 'Grades e horários',
      'Configure períodos, vagas e intervalos.', Icons.view_week_outlined),
  specialties(AdminArea.schedule, 'Especialidades',
      'Gerencie os serviços oferecidos.', Icons.local_hospital_outlined),
  professionals(AdminArea.people, 'Profissionais',
      'Gerencie a equipe multiprofissional.', Icons.badge_outlined),
  doctors(
      AdminArea.people,
      'Médicos',
      'Gerencie contas e especialidades médicas.',
      Icons.health_and_safety_outlined),
  users(AdminArea.people, 'Usuários internos', 'Controle contas e permissões.',
      Icons.manage_accounts_outlined),
  history(AdminArea.governance, 'Histórico',
      'Consulte alterações e validações.', Icons.history_outlined),
  settings(AdminArea.governance, 'Configurações',
      'Ajuste preferências administrativas.', Icons.settings_outlined);

  const AdminSection(this.area, this.label, this.description, this.icon);
  final AdminArea area;
  final String label;
  final String description;
  final IconData icon;
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, this.api});
  final ApiService? api;
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late final ApiService api = widget.api ?? ApiService();
  AdminSection section = AdminSection.overview;
  AdminSummary? summary;
  List<AdminAppointment> appointments = [];
  List<InternalUser> users = [];
  List<DoctorAccount> doctors = [];
  List<Map<String, dynamic>> specialties = [],
      professionals = [],
      queue = [],
      audit = [],
      priorityValidations = [],
      grids = [];
  bool loading = true;
  bool queueFiltering = false;
  String? error;
  Timer? refreshTimer;
  final specialtySearch = TextEditingController();
  final queueSearch = TextEditingController();
  final historyPatientSearch = TextEditingController();
  final historyProfessionalSearch = TextEditingController();
  final historyActionSearch = TextEditingController();
  final adminScrollFocusNode = FocusNode(debugLabel: 'admin-scroll-region');
  final adminScrollControllers = {
    for (final section in AdminSection.values) section: ScrollController(),
  };
  DateTime queueDay = DateTime.now();
  String? queueSpecialty, queueStatus, queueRisk;
  int? queueProfessionalId;
  DateTime? historyDateFrom, historyDateTo;
  String? historyStatus;
  bool historyFiltering = false;
  bool historyFiltersExpanded = false;

  @override
  void initState() {
    super.initState();
    load();
    refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (section == AdminSection.queue && !loading) _refreshQueue();
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    specialtySearch.dispose();
    queueSearch.dispose();
    historyPatientSearch.dispose();
    historyProfessionalSearch.dispose();
    historyActionSearch.dispose();
    adminScrollFocusNode.dispose();
    for (final controller in adminScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchQueue() => api.queue(
      day: queueDay,
      specialty: queueSpecialty,
      professionalId: queueProfessionalId,
      status: queueStatus,
      risk: queueRisk,
      patient: queueSearch.text);

  Future<void> _refreshQueue() async {
    try {
      final latest = await _fetchQueue();
      if (mounted && section == AdminSection.queue) {
        setState(() => queue = latest);
      }
    } on ApiException catch (_) {}
  }

  Future<void> _applyQueueFilters() async {
    if (queueFiltering) return;
    setState(() => queueFiltering = true);
    try {
      final latest = await _fetchQueue();
      if (mounted) setState(() => queue = latest);
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    } finally {
      if (mounted) setState(() => queueFiltering = false);
    }
  }

  Future<void> _clearQueueFilters() async {
    setState(() {
      queueDay = DateTime.now();
      queueSpecialty = null;
      queueProfessionalId = null;
      queueStatus = null;
      queueRisk = null;
      queueSearch.clear();
    });
    await _applyQueueFilters();
  }

  Future<List<Object>> _fetchHistory() => Future.wait<Object>([
        api.auditHistory(
            patient: historyPatientSearch.text,
            professional: historyProfessionalSearch.text,
            dateFrom: historyDateFrom,
            dateTo: historyDateTo,
            action: historyActionSearch.text),
        api.priorityValidations(
            patient: historyPatientSearch.text,
            professional: historyProfessionalSearch.text,
            dateFrom: historyDateFrom,
            dateTo: historyDateTo,
            status: historyStatus),
      ]);

  Future<void> _applyHistoryFilters() async {
    if (historyFiltering) return;
    if (historyDateFrom != null &&
        historyDateTo != null &&
        historyDateFrom!.isAfter(historyDateTo!)) {
      notice(context, 'A data inicial não pode ser posterior à data final.');
      return;
    }
    setState(() => historyFiltering = true);
    try {
      final values = await _fetchHistory();
      if (mounted) {
        setState(() {
          audit = values[0] as List<Map<String, dynamic>>;
          priorityValidations = values[1] as List<Map<String, dynamic>>;
        });
      }
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    } finally {
      if (mounted) setState(() => historyFiltering = false);
    }
  }

  Future<void> _clearHistoryFilters() async {
    setState(() {
      historyPatientSearch.clear();
      historyProfessionalSearch.clear();
      historyActionSearch.clear();
      historyDateFrom = null;
      historyDateTo = null;
      historyStatus = null;
    });
    await _applyHistoryFilters();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      switch (section) {
        case AdminSection.overview:
          summary = await api.adminSummary();
        case AdminSection.agenda:
        case AdminSection.appointments:
        case AdminSection.checkin:
          final values = await Future.wait([
            api.adminAppointments(),
            api.adminSpecialties(),
            api.allProfessionals()
          ]);
          appointments = values[0] as List<AdminAppointment>;
          specialties = values[1] as List<Map<String, dynamic>>;
          professionals = values[2] as List<Map<String, dynamic>>;
        case AdminSection.queue:
          final values = await Future.wait(
              [_fetchQueue(), api.adminSpecialties(), api.allProfessionals()]);
          queue = values[0];
          specialties = values[1];
          professionals = values[2];
        case AdminSection.users:
        case AdminSection.professionals:
          users = await api.internalUsers(
              role: section == AdminSection.professionals ? 'medico' : null);
          specialties = await api.adminSpecialties();
        case AdminSection.doctors:
          doctors = await api.doctors();
        case AdminSection.specialties:
          specialties = await api.adminSpecialties();
        case AdminSection.grids:
          final values =
              await Future.wait([api.grids(), api.adminSpecialties()]);
          grids = values[0];
          specialties = values[1];
        case AdminSection.history:
          final values = await _fetchHistory();
          audit = values[0] as List<Map<String, dynamic>>;
          priorityValidations = values[1] as List<Map<String, dynamic>>;
        case AdminSection.settings:
          break;
      }
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void select(AdminSection value) {
    setState(() => section = value);
    load();
  }

  Future<void> logout() async {
    await ApiService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) => ResponsiveAppShell(
      title: 'Administração',
      subtitle: ApiService.session?.name ?? 'Administrador',
      destinations: [
        for (final item in AdminSection.values)
          AppDestination(
              icon: item.icon, label: item.label, color: item.area.color)
      ],
      selectedIndex: AdminSection.values.indexOf(section),
      onDestinationSelected: (index) => select(AdminSection.values[index]),
      primaryAction: Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            label: const Text('Atualizar')),
        OutlinedButton.icon(
            onPressed: logout,
            icon: const Icon(Icons.logout),
            label: const Text('Sair')),
      ]),
      body: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Administração: ${section.label}',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(
              key: const Key('admin-breadcrumb'),
              label: 'Localização: ${section.area.label}, ${section.label}',
              child: Row(children: [
                Icon(section.area.icon,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text('${section.area.label}  ›  ${section.label}',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: Card(
                  key: const Key('admin-module-content'),
                  child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: _content())),
            ),
          ])));

  Widget _content() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(error!, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'))
      ]));
    }
    return switch (section) {
      AdminSection.overview => _overview(),
      AdminSection.agenda ||
      AdminSection.appointments ||
      AdminSection.checkin =>
        _agenda(),
      AdminSection.queue => _queue(),
      AdminSection.grids => _grids(),
      AdminSection.specialties => _specialties(),
      AdminSection.doctors => _doctors(),
      AdminSection.professionals || AdminSection.users => _users(),
      AdminSection.history => _history(),
      AdminSection.settings => _settings(),
    };
  }

  bool adminScrollRegionFocused = false;

  ScrollController get adminScrollController =>
      adminScrollControllers[section]!;

  KeyEventResult _handleAdminScrollKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || !adminScrollController.hasClients) {
      return KeyEventResult.ignored;
    }
    final position = adminScrollController.position;
    final key = event.logicalKey;
    final double target;
    if (key == LogicalKeyboardKey.arrowDown) {
      target = position.pixels + 48;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      target = position.pixels - 48;
    } else if (key == LogicalKeyboardKey.pageDown) {
      target = position.pixels + position.viewportDimension * .8;
    } else if (key == LogicalKeyboardKey.pageUp) {
      target = position.pixels - position.viewportDimension * .8;
    } else if (key == LogicalKeyboardKey.home) {
      target = position.minScrollExtent;
    } else if (key == LogicalKeyboardKey.end) {
      target = position.maxScrollExtent;
    } else {
      return KeyEventResult.ignored;
    }
    adminScrollController.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
    return KeyEventResult.handled;
  }

  Widget _title(String title, String subtitle, {Widget? action}) {
    final header = ResponsivePageHeader(
        title: title, subtitle: subtitle, primaryAction: action);
    if (action != null) return header;
    return Focus(
      key: const Key('admin-scroll-region-focus'),
      focusNode: adminScrollFocusNode,
      onKeyEvent: _handleAdminScrollKey,
      onFocusChange: (focused) {
        if (adminScrollRegionFocused != focused) {
          setState(() => adminScrollRegionFocused = focused);
        }
      },
      child: Semantics(
        container: true,
        focusable: true,
        label: 'Conteúdo rolável: $title. $subtitle',
        hint: 'Use as setas para percorrer o conteúdo',
        excludeSemantics: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: adminScrollRegionFocused
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: header,
        ),
      ),
    );
  }

  Widget _overview() {
    final s = summary!;
    final cards = [
      ('Consultas agendadas', s.scheduled, Icons.event_available, blue),
      ('Chegadas confirmadas', s.checkedIn, Icons.how_to_reg, green),
      (
        'Pacientes aguardando',
        s.waiting,
        Icons.groups,
        const Color(0xFF9A6700)
      ),
      (
        'Em atendimento',
        s.inCare,
        Icons.monitor_heart_outlined,
        const Color(0xFF7A4CE0)
      ),
      ('Concluídos', s.completed, Icons.task_alt, green),
      ('Canceladas', s.cancelled, Icons.event_busy, const Color(0xFFB42318)),
      ('Faltas', s.absent, Icons.person_off_outlined, const Color(0xFFB42318)),
      ('Vagas disponíveis', s.available, Icons.event_seat_outlined, green),
    ];
    return ListView(
        key: const PageStorageKey('admin-overview-scroll'),
        controller: adminScrollController,
        children: [
          _title('Visão do dia', 'Indicadores reais das consultas de hoje.'),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (_, c) {
            final width = c.maxWidth >= 900
                ? (c.maxWidth - 32) / 3
                : c.maxWidth >= 560
                    ? (c.maxWidth - 16) / 2
                    : c.maxWidth;
            return Wrap(spacing: 16, runSpacing: 16, children: [
              for (final item in cards)
                SizedBox(
                    width: width,
                    child: _metric(item.$1, item.$2, item.$3, item.$4))
            ]);
          }),
          const SizedBox(height: 22),
          InfoPanel(
              icon: Icons.verified_user_outlined,
              text:
                  'As ações administrativas são validadas no servidor e registradas no histórico sem senhas, hashes ou CPF completo.')
        ]);
  }

  Widget _metric(String label, int value, IconData icon, Color color) => Card(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            CircleAvatar(
                backgroundColor: accessibility.highContrast
                    ? Colors.yellow
                    : color.withValues(alpha: .12),
                child: Icon(icon,
                    color: accessibility.highContrast ? Colors.black : color)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('$value',
                      style: const TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w900)),
                  Text(label)
                ]))
          ])));

  Widget _agenda() => _AgendaAdminView(
      key: ValueKey(section),
      api: api,
      title: section.label,
      initial: appointments,
      specialties: specialties,
      professionals: professionals,
      checkinOnly: section == AdminSection.checkin,
      onChanged: load);

  Widget _queue() => ListView(
          key: const PageStorageKey('admin-queue-scroll'),
          controller: adminScrollController,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _title('Fila de atendimento',
                'Ordenada pelo backend por risco, prioridade legal e chegada.'),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              key: const Key('admin-queue-filter-region'),
              container: true,
              label: 'Filtros da fila de atendimento',
              child: AppSurfaceCard(
                child: LayoutBuilder(builder: (context, constraints) {
                  final fieldWidth =
                      responsiveFilterWidth(constraints.maxWidth);
                  return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: fieldWidth,
                        child: Semantics(
                          textField: true,
                          label: 'Buscar paciente na fila por nome ou CPF',
                          child: TextField(
                            key: const Key('admin-queue-search'),
                            controller: queueSearch,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _applyQueueFilters(),
                            decoration: InputDecoration(
                              labelText: 'Paciente',
                              hintText: 'Nome ou CPF',
                              prefixIcon: const ExcludeSemantics(
                                  child: Icon(Icons.search)),
                              suffixIcon: IconButton(
                                tooltip: 'Buscar paciente',
                                onPressed:
                                    queueFiltering ? null : _applyQueueFilters,
                                icon: const Icon(Icons.arrow_forward),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: DropdownButtonFormField<String>(
                          key:
                              ValueKey('admin-queue-specialty-$queueSpecialty'),
                          initialValue: queueSpecialty,
                          isExpanded: true,
                          itemHeight: null,
                          decoration:
                              const InputDecoration(labelText: 'Especialidade'),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('Todas')),
                            for (final value in specialties)
                              DropdownMenuItem(
                                value: value['name'].toString(),
                                child: Text(
                                    specialtyDisplayName(
                                        value['name'].toString()),
                                    maxLines: 2,
                                    softWrap: true),
                              ),
                          ],
                          onChanged: queueFiltering
                              ? null
                              : (value) {
                                  setState(() => queueSpecialty = value);
                                  _applyQueueFilters();
                                },
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: DropdownButtonFormField<int>(
                          key: ValueKey(
                              'admin-queue-professional-$queueProfessionalId'),
                          initialValue: queueProfessionalId,
                          isExpanded: true,
                          itemHeight: null,
                          decoration:
                              const InputDecoration(labelText: 'Profissional'),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('Todos')),
                            for (final value in professionals)
                              DropdownMenuItem(
                                value: value['id'] as int,
                                child: Text(value['name'].toString(),
                                    maxLines: 2, softWrap: true),
                              ),
                          ],
                          onChanged: queueFiltering
                              ? null
                              : (value) {
                                  setState(() => queueProfessionalId = value);
                                  _applyQueueFilters();
                                },
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('admin-queue-status-$queueStatus'),
                          initialValue: queueStatus,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Status'),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('Todos')),
                            DropdownMenuItem(
                                value: 'em_espera', child: Text('Em espera')),
                            DropdownMenuItem(
                                value: 'em_triagem', child: Text('Em triagem')),
                            DropdownMenuItem(
                                value: 'em_atendimento',
                                child: Text('Em atendimento')),
                          ],
                          onChanged: queueFiltering
                              ? null
                              : (value) {
                                  setState(() => queueStatus = value);
                                  _applyQueueFilters();
                                },
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('admin-queue-risk-$queueRisk'),
                          initialValue: queueRisk,
                          isExpanded: true,
                          itemHeight: null,
                          decoration: const InputDecoration(
                              labelText: 'Classificação de risco'),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text('Todas')),
                            for (final item in RiskClassification.options)
                              DropdownMenuItem(
                                value: item.$1,
                                child: AppRiskFilterItem(risk: item.$1),
                              ),
                          ],
                          onChanged: queueFiltering
                              ? null
                              : (value) {
                                  setState(() => queueRisk = value);
                                  _applyQueueFilters();
                                },
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: OutlinedButton.icon(
                          key: const Key('admin-queue-date'),
                          onPressed: queueFiltering
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: queueDay,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 730)),
                                  );
                                  if (picked != null) {
                                    setState(() => queueDay = picked);
                                    await _applyQueueFilters();
                                  }
                                },
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text('Data: ${showOnlyDate(queueDay)}'),
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: OutlinedButton.icon(
                          key: const Key('admin-queue-clear-filters'),
                          onPressed: queueFiltering ? null : _clearQueueFilters,
                          icon: const Icon(Icons.filter_alt_off_outlined),
                          label: const Text('Limpar filtros'),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
            if (queueFiltering) ...[
              const SizedBox(height: AppSpacing.sm),
              const LinearProgressIndicator(
                  semanticsLabel:
                      'Atualizando fila com os filtros selecionados'),
            ],
            const SizedBox(height: AppSpacing.md),
            if (!queueFiltering && queue.isEmpty)
              const _EmptyState(
                  'Nenhum paciente corresponde aos filtros selecionados.'),
            for (final item in queue) ...[
              _queueCard(item),
              const SizedBox(height: AppSpacing.sm),
            ],
          ]);

  Widget _queueCard(Map<String, dynamic> item) {
    final position = '${item['position'] ?? '-'}';
    final patient = item['patient']?.toString() ?? 'Paciente';
    final specialty = specialtyDisplayName(item['specialty']?.toString() ?? '');
    final professional = item['professional']?.toString() ?? '-';
    final priority = item['legal_priority']?.toString() ?? 'geral';
    final status = item['status']?.toString() ?? '';
    final statusText = statusLabel(status);
    final arrival = _queueArrival(item['arrived_at']);
    final statusBadge = AppStatusBadge(
      key: Key('admin-queue-status-$position'),
      label: statusText,
      tone: statusToneFor(status),
      semanticLabel: 'Status atual: $statusText',
    );

    return Card(
      key: Key('admin-queue-card-$position'),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: LayoutBuilder(builder: (context, constraints) {
          final positionBadge = Semantics(
            label: 'Posição $position na fila',
            excludeSemantics: true,
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              child: Text(position,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(patient,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.xs),
              Text('$specialty • $professional',
                  softWrap: true, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.xs,
                children: [
                  _queueMetadata(Icons.schedule_outlined, 'Chegada: $arrival'),
                  _queueMetadata(Icons.accessible_forward_outlined,
                      'Prioridade: $priority'),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AppRiskIndicator(risk: item['risk_classification']?.toString()),
            ],
          );

          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  positionBadge,
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: details),
                ]),
                const SizedBox(height: AppSpacing.md),
                Align(alignment: Alignment.centerLeft, child: statusBadge),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              positionBadge,
              const SizedBox(width: AppSpacing.md),
              Expanded(child: details),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(
                  width: 190,
                  child: Align(
                      alignment: Alignment.centerLeft, child: statusBadge)),
            ],
          );
        }),
      ),
    );
  }

  Widget _queueMetadata(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: Text(text)),
        ],
      );

  String _queueArrival(Object? value) {
    if (value == null) return '-';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  Widget _users() => _InternalUsersView(
      api: api,
      initial: users,
      specialties: specialties,
      professionalOnly: section == AdminSection.professionals,
      onChanged: load);

  Widget _doctors() =>
      _DoctorsView(api: api, initial: doctors, onChanged: load);

  Widget _specialties() {
    final query = specialtySearch.text.trim().toLowerCase();
    final filtered = specialties
        .where((item) => item['name'].toString().toLowerCase().contains(query))
        .toList();
    return ListView(children: [
      _title('Especialidades',
          'Cadastre, edite e controle quais especialidades estão disponíveis para novos agendamentos.',
          action: FilledButton.icon(
              key: const Key('new-specialty-button'),
              onPressed: _openSpecialtyForm,
              icon: const Icon(Icons.add),
              label: const Text('Nova especialidade'))),
      const SizedBox(height: 16),
      Semantics(
          textField: true,
          label: 'Pesquisar especialidades',
          child: TextField(
              key: const Key('specialty-search-field'),
              controller: specialtySearch,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Pesquisar especialidades',
                  hintText: 'Digite o nome da especialidade',
                  prefixIcon: ExcludeSemantics(child: Icon(Icons.search)),
                  suffixIcon:
                      ExcludeSemantics(child: Icon(Icons.manage_search))))),
      const SizedBox(height: 16),
      if (specialties.isEmpty)
        const _EmptyState('Nenhuma especialidade cadastrada.')
      else if (filtered.isEmpty)
        const _EmptyState('Nenhuma especialidade encontrada.')
      else
        for (final item in filtered) ...[
          _specialtyCard(item),
          const SizedBox(height: 12)
        ]
    ]);
  }

  Widget _specialtyCard(Map<String, dynamic> item) {
    final active = item['active'] as bool? ?? true;
    final details = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(active ? Icons.check_circle_outline : Icons.block_outlined,
          size: 20,
          color: active ? green : Theme.of(context).colorScheme.error),
      const SizedBox(width: 8),
      Text(active ? 'Ativa' : 'Inativa', style: const TextStyle(fontSize: 16))
    ]);
    final actions = Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(
          key: Key('edit-specialty-${item['id']}'),
          onPressed: () => _openSpecialtyForm(item),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Editar')),
      OutlinedButton.icon(
          key: Key('toggle-specialty-${item['id']}'),
          onPressed: () => _toggleSpecialty(item),
          icon:
              Icon(active ? Icons.block_outlined : Icons.check_circle_outline),
          label: Text(active ? 'Desativar' : 'Ativar'))
    ]);
    return Semantics(
        container: true,
        label:
            'Especialidade ${specialtyDisplayName(item['name'].toString())}, ${active ? 'ativa' : 'inativa'}',
        child: Card(
            child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: LayoutBuilder(builder: (context, constraints) {
                  final information = Row(children: [
                    const Icon(Icons.medical_information_outlined, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(specialtyDisplayName(item['name'].toString()),
                              style: Theme.of(context).textTheme.titleMedium,
                              softWrap: true,
                              maxLines: 2),
                          const SizedBox(height: 6),
                          details
                        ]))
                  ]);
                  if (constraints.maxWidth < 620) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          information,
                          const SizedBox(height: 12),
                          Align(
                              alignment: Alignment.centerRight, child: actions)
                        ]);
                  }
                  return Row(children: [
                    Expanded(child: information),
                    const SizedBox(width: 16),
                    actions
                  ]);
                }))));
  }

  Future<void> _openSpecialtyForm([Map<String, dynamic>? existing]) async {
    final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _SpecialtyFormDialog(api: api, existing: existing));
    if (saved == true) {
      await load();
      if (mounted) {
        notice(
            context,
            existing == null
                ? 'Especialidade criada com sucesso.'
                : 'Especialidade atualizada com sucesso.');
      }
    }
  }

  Future<void> _toggleSpecialty(Map<String, dynamic> item) async {
    final active = item['active'] as bool? ?? true;
    try {
      await api.setSpecialtyActive(item['id'] as int, !active);
      await load();
      if (mounted) {
        notice(context,
            active ? 'Especialidade desativada.' : 'Especialidade ativada.');
      }
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    }
  }

  Widget _grids() => _GridAdminView(
      api: api, grids: grids, specialties: specialties, onChanged: load);

  Widget _historyFilters() => Semantics(
      key: const Key('admin-history-filter-region'),
      container: true,
      label: 'Filtros do histórico e da auditoria',
      child: AppSurfaceCard(
          child: Column(children: [
        ListTile(
            key: const Key('admin-history-filter-expansion'),
            title: const Text('Filtros do histórico'),
            subtitle:
                const Text('Paciente, profissional, período, ação e status'),
            trailing: Icon(
                historyFiltersExpanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(
                () => historyFiltersExpanded = !historyFiltersExpanded)),
        if (historyFiltersExpanded)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: LayoutBuilder(builder: (context, constraints) {
                final fieldWidth = responsiveFilterWidth(constraints.maxWidth);
                return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                          width: fieldWidth,
                          child: TextField(
                              key: const Key('admin-history-patient'),
                              controller: historyPatientSearch,
                              textInputAction: TextInputAction.search,
                              decoration: const InputDecoration(
                                  labelText: 'Paciente',
                                  hintText: 'Nome do paciente',
                                  prefixIcon: ExcludeSemantics(
                                      child: Icon(Icons.search))),
                              onSubmitted: (_) => _applyHistoryFilters())),
                      SizedBox(
                          width: fieldWidth,
                          child: TextField(
                              key: const Key('admin-history-professional'),
                              controller: historyProfessionalSearch,
                              textInputAction: TextInputAction.search,
                              decoration: const InputDecoration(
                                  labelText: 'Profissional ou responsável',
                                  hintText: 'Nome do profissional',
                                  prefixIcon: ExcludeSemantics(
                                      child: Icon(Icons.badge_outlined))),
                              onSubmitted: (_) => _applyHistoryFilters())),
                      SizedBox(
                          width: fieldWidth,
                          child: TextField(
                              key: const Key('admin-history-action'),
                              controller: historyActionSearch,
                              textInputAction: TextInputAction.search,
                              decoration: const InputDecoration(
                                  labelText: 'Tipo de ação',
                                  hintText: 'Ex.: chegada_confirmada'),
                              onSubmitted: (_) => _applyHistoryFilters())),
                      SizedBox(
                          width: fieldWidth,
                          child: DropdownButtonFormField<String>(
                              key: ValueKey(
                                  'admin-history-status-$historyStatus'),
                              initialValue: historyStatus,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'Status da condição'),
                              items: const [
                                DropdownMenuItem(
                                    value: null, child: Text('Todos')),
                                DropdownMenuItem(
                                    value: 'pendente', child: Text('Pendente')),
                                DropdownMenuItem(
                                    value: 'confirmada',
                                    child: Text('Confirmada')),
                                DropdownMenuItem(
                                    value: 'rejeitada',
                                    child: Text('Rejeitada')),
                                DropdownMenuItem(
                                    value: 'retirada', child: Text('Retirada')),
                              ],
                              onChanged: historyFiltering
                                  ? null
                                  : (value) =>
                                      setState(() => historyStatus = value))),
                      SizedBox(
                          width: fieldWidth,
                          child: OutlinedButton.icon(
                              key: const Key('admin-history-date-from'),
                              onPressed: historyFiltering
                                  ? null
                                  : () async {
                                      final picked = await showDatePicker(
                                          context: context,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime.now(),
                                          initialDate: historyDateFrom ??
                                              DateTime.now());
                                      if (picked != null) {
                                        setState(
                                            () => historyDateFrom = picked);
                                      }
                                    },
                              icon: const Icon(Icons.date_range_outlined),
                              label: Text(historyDateFrom == null
                                  ? 'Data inicial'
                                  : 'De: ${showOnlyDate(historyDateFrom!)}'))),
                      SizedBox(
                          width: fieldWidth,
                          child: OutlinedButton.icon(
                              key: const Key('admin-history-date-to'),
                              onPressed: historyFiltering
                                  ? null
                                  : () async {
                                      final picked = await showDatePicker(
                                          context: context,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime.now(),
                                          initialDate:
                                              historyDateTo ?? DateTime.now());
                                      if (picked != null) {
                                        setState(() => historyDateTo = picked);
                                      }
                                    },
                              icon: const Icon(Icons.event_available_outlined),
                              label: Text(historyDateTo == null
                                  ? 'Data final'
                                  : 'Até: ${showOnlyDate(historyDateTo!)}'))),
                      SizedBox(
                          width: fieldWidth,
                          child: FilledButton.icon(
                              key: const Key('admin-history-apply-filters'),
                              onPressed: historyFiltering
                                  ? null
                                  : _applyHistoryFilters,
                              icon: const Icon(Icons.filter_alt),
                              label: const Text('Aplicar filtros'))),
                      SizedBox(
                          width: fieldWidth,
                          child: OutlinedButton.icon(
                              key: const Key('admin-history-clear-filters'),
                              onPressed: historyFiltering
                                  ? null
                                  : _clearHistoryFilters,
                              icon: const Icon(Icons.filter_alt_off_outlined),
                              label: const Text('Limpar filtros'))),
                      const Text(
                          'Exibição limitada aos 100 registros mais recentes.'),
                    ]);
              }))
      ])));

  Widget _history() => SingleChildScrollView(
      key: const PageStorageKey('admin-history-scroll'),
      controller: adminScrollController,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _title('Histórico e auditoria',
            'Validações presenciais e ações administrativas, sem permitir alterar a idade.'),
        const SizedBox(height: 16),
        _historyFilters(),
        const SizedBox(height: 16),
        if (priorityValidations.isNotEmpty) ...[
          Text('Validações de prioridade',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final item in priorityValidations)
            Card(
                child: ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: Text('${item['patient']} • ${item['condition']}'),
                    subtitle: Text([
                      'Estado: ${item['status']}',
                      if (item['validated_by'] != null)
                        'Responsável: ${item['validated_by']}',
                      if (item['validated_at'] != null)
                        'Data: ${showDate(DateTime.parse(item['validated_at']))}',
                      'Eventos no histórico: ${(item['history'] as List? ?? const []).length}'
                    ].join('\n')))),
          const SizedBox(height: 16),
        ],
        if (audit.isEmpty)
          const _EmptyState('Nenhuma ação administrativa registrada.'),
        for (final item in audit)
          Semantics(
              container: true,
              label: 'Registro de auditoria: ${item['action']}',
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(builder: (context, constraints) {
                        final content = Row(
                            key: const Key('audit-content'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.history),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(item['action']
                                        .toString()
                                        .replaceAll('_', ' ')),
                                    const SizedBox(height: 4),
                                    Text(
                                        '${item['actor']} • ${item['record_type']} #${item['record_id'] ?? '-'}')
                                  ]))
                            ]);
                        final metadata = _AuditMetadata(
                            createdAt: item['created_at'].toString());
                        final compact = constraints.maxWidth < 620 ||
                            MediaQuery.textScalerOf(context).scale(16) > 18;
                        if (compact) {
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                content,
                                const SizedBox(height: 12),
                                Align(
                                    alignment: Alignment.centerLeft,
                                    child: metadata)
                              ]);
                        }
                        return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: content),
                              const SizedBox(width: 20),
                              metadata
                            ]);
                      }))))
      ]));

  Widget _settings() => ListView(
          key: const PageStorageKey('admin-settings-scroll'),
          controller: adminScrollController,
          children: [
            _title('Configurações',
                'Preferências do painel e informações de segurança.'),
            const SizedBox(height: 16),
            const InfoPanel(
                icon: Icons.accessibility_new,
                text:
                    'Use o menu de acessibilidade para ajustar A−, A, A+ e alto contraste. As preferências permanecem durante a navegação.'),
            const SizedBox(height: 12),
            const InfoPanel(
                icon: Icons.password,
                text:
                    'A alteração obrigatória de senha provisória no primeiro acesso ainda não faz parte desta versão. O administrador pode redefinir o acesso com uma nova senha provisória.'),
            const SizedBox(height: 18),
            Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                    onPressed: _createAnotherAdmin,
                    icon: const Icon(Icons.admin_panel_settings),
                    label: const Text('Criar outro administrador')))
          ]);

  Future<void> _createAnotherAdmin() async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController(),
        cpf = TextEditingController(),
        email = TextEditingController(),
        password = TextEditingController(),
        confirmation = TextEditingController();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Criar outro administrador'),
                content: SizedBox(
                    width: 520,
                    child: Form(
                        key: form,
                        child: SingleChildScrollView(
                            child: Column(children: [
                          field(name, 'Nome completo', Icons.person_outline,
                              validator: requiredName),
                          field(cpf, 'CPF', Icons.badge_outlined,
                              validator: requiredCpf,
                              inputFormatters: [CpfFormatter()],
                              number: true),
                          field(email, 'E-mail', Icons.email_outlined,
                              validator: emailRule),
                          field(
                              password, 'Senha provisória', Icons.lock_outline,
                              validator: passwordRule, secret: true),
                          field(confirmation, 'Confirmação', Icons.lock_reset,
                              validator: (v) => v != password.text
                                  ? 'As senhas não coincidem.'
                                  : null,
                              secret: true)
                        ])))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () {
                        if (form.currentState!.validate()) {
                          Navigator.pop(c, true);
                        }
                      },
                      child: const Text('Criar administrador'))
                ]));
    if (accepted == true) {
      try {
        await api.createAdmin({
          'name': name.text.trim(),
          'cpf': digits(cpf.text),
          'email': email.text.trim(),
          'password': password.text,
          'password_confirmation': confirmation.text
        });
        if (mounted) notice(context, 'Administrador criado com segurança.');
      } on ApiException catch (e) {
        if (mounted) notice(context, e.message);
      }
    }
    for (final controller in [name, cpf, email, password, confirmation]) {
      controller.dispose();
    }
  }
}

class _SpecialtyFormDialog extends StatefulWidget {
  const _SpecialtyFormDialog({required this.api, this.existing});

  final ApiService api;
  final Map<String, dynamic>? existing;

  @override
  State<_SpecialtyFormDialog> createState() => _SpecialtyFormDialogState();
}

class _SpecialtyFormDialogState extends State<_SpecialtyFormDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name =
      TextEditingController(text: widget.existing?['name']?.toString() ?? '');
  bool saving = false;
  String? serverError;

  bool get editing => widget.existing != null;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => serverError = null);
    if (!(formKey.currentState?.validate() ?? false)) return;
    setState(() => saving = true);
    try {
      if (editing) {
        await widget.api
            .updateSpecialty(widget.existing!['id'] as int, name.text.trim());
      } else {
        await widget.api.createSpecialty(name.text.trim());
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          serverError = error.message;
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(editing ? 'Editar especialidade' : 'Nova especialidade'),
          content: SizedBox(
              width: 480,
              child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                        key: const Key('specialty-name-field'),
                        controller: name,
                        autofocus: true,
                        enabled: !saving,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => save(),
                        maxLength: 80,
                        decoration: const InputDecoration(
                            labelText: 'Nome da especialidade',
                            hintText: 'Ex.: Pediatria',
                            prefixIcon:
                                Icon(Icons.medical_information_outlined)),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Informe o nome da especialidade.'
                                : null),
                    if (serverError != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                          liveRegion: true,
                          child: Text(serverError!,
                              key: const Key('specialty-form-error'),
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w600)))
                    ]
                  ])))),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton.icon(
                key: const Key('save-specialty-button'),
                onPressed: saving ? null : save,
                icon: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(editing ? 'Salvar alterações' : 'Salvar'))
          ]);
}

class _AuditMetadata extends StatelessWidget {
  const _AuditMetadata({required this.createdAt});

  final String createdAt;

  @override
  Widget build(BuildContext context) {
    final formatted = createdAt.replaceFirst('T', ' ').substring(0, 16);
    return Column(
        key: const Key('audit-metadata'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Registrado',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Text(formatted, style: const TextStyle(fontSize: 16))
        ]);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
          child: Column(children: [
        const Icon(Icons.inbox_outlined, size: 44),
        const SizedBox(height: 12),
        Text(message)
      ])));
}

class _AgendaAdminView extends StatefulWidget {
  const _AgendaAdminView(
      {super.key,
      required this.api,
      required this.title,
      required this.initial,
      required this.specialties,
      required this.professionals,
      required this.checkinOnly,
      required this.onChanged});
  final ApiService api;
  final String title;
  final List<AdminAppointment> initial;
  final List<Map<String, dynamic>> specialties, professionals;
  final bool checkinOnly;
  final Future<void> Function() onChanged;
  @override
  State<_AgendaAdminView> createState() => _AgendaAdminViewState();
}

class _AgendaAdminViewState extends State<_AgendaAdminView> {
  late List<AdminAppointment> items = widget.initial;
  final search = TextEditingController();
  String? status, specialty, risk;
  int? professionalId;
  DateTime day = DateTime.now();
  bool busy = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> filter() async {
    setState(() => busy = true);
    try {
      items = await widget.api.adminAppointments(
          day: day,
          specialty: specialty,
          professionalId: professionalId,
          status: widget.checkinOnly ? 'agendado' : status,
          risk: widget.checkinOnly ? null : risk,
          patient: search.text);
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> clearFilters() async {
    if (busy) return;
    setState(() {
      day = DateTime.now();
      status = null;
      specialty = null;
      professionalId = null;
      risk = null;
      search.clear();
    });
    await filter();
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
          context: context,
          builder: (c) =>
              AlertDialog(title: Text(title), content: Text(message), actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: Text(action))
              ])) ??
      false;

  Future<void> registerAbsence(AdminAppointment item) async {
    if (!await _confirm(
        'Registrar falta?',
        'Registrar a ausência de ${item.patient}? Esta ação ficará no histórico.',
        'Registrar falta')) {
      return;
    }
    try {
      await widget.api.registerAbsence(item.id);
      await filter();
      await widget.onChanged();
      if (mounted) notice(context, 'Falta registrada.');
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    }
  }

  Future<void> showDetails(AdminAppointment item) async {
    try {
      final value = await widget.api.adminAppointmentDetails(item.id);
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
                title: const Text('Detalhes da consulta'),
                content: Semantics(
                    label: 'Detalhes administrativos da consulta',
                    child: SizedBox(
                        width: 480,
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(value['patient'].toString(),
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 12),
                              Text(
                                  'CPF protegido: ${value['patient_document']}'),
                              Text(
                                  'Data e horário: ${showDate(DateTime.parse(value['scheduled_at'].toString()))}'),
                              Text(
                                  'Especialidade: ${specialtyDisplayName(value['specialty'].toString())}'),
                              Text('Profissional: ${value['professional']}'),
                              Text('Prioridade: ${value['legal_priority']}'),
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: AppRiskIndicator(
                                      risk: value['risk_classification']
                                          ?.toString())),
                              Text(
                                  'Status: ${statusLabel(value['status'].toString())}'),
                            ]))),
                actions: [
                  FilledButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Fechar'))
                ],
              ));
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    }
  }

  Future<void> checkIn(AdminAppointment item) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Confirmar chegada?'),
                content: Text(
                    'Confirmar a chegada de ${item.patient} para ${specialtyDisplayName(item.specialty)}?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Confirmar chegada'))
                ]));
    if (confirmed != true) return;
    try {
      await widget.api.checkIn(item.id);
      await filter();
      await widget.onChanged();
      if (mounted) notice(context, 'Chegada confirmada pelo backend.');
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(children: [
        Text(widget.title,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
        const Text(
            'Filtre por data, especialidade, profissional, status, nome ou CPF. O CPF nunca é exibido por completo.'),
        const SizedBox(height: 16),
        Semantics(
          key: const Key('admin-agenda-filter-region'),
          container: true,
          label: 'Filtros de agendamentos administrativos',
          child: AppSurfaceCard(
            child: LayoutBuilder(builder: (context, constraints) {
              final fieldWidth = responsiveFilterWidth(constraints.maxWidth);
              return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                        width: fieldWidth,
                        child: Semantics(
                            textField: true,
                            label: 'Buscar paciente por nome ou CPF',
                            child: TextField(
                                key: const Key('admin-agenda-search'),
                                controller: search,
                                textInputAction: TextInputAction.search,
                                decoration: const InputDecoration(
                                    labelText: 'Paciente',
                                    hintText: 'Nome ou CPF',
                                    prefixIcon: ExcludeSemantics(
                                        child: Icon(Icons.search))),
                                onSubmitted: (_) => filter()))),
                    if (!widget.checkinOnly)
                      SizedBox(
                          width: fieldWidth,
                          child: DropdownButtonFormField<String>(
                              key: ValueKey('admin-agenda-status-$status'),
                              initialValue: status,
                              isExpanded: true,
                              itemHeight: null,
                              decoration:
                                  const InputDecoration(labelText: 'Status'),
                              items: const [
                                DropdownMenuItem(
                                    value: null, child: Text('Todos')),
                                DropdownMenuItem(
                                    value: 'agendado', child: Text('Agendada')),
                                DropdownMenuItem(
                                    value: 'em_espera',
                                    child: Text('Check-in')),
                                DropdownMenuItem(
                                    value: 'em_triagem',
                                    child: Text('Em triagem')),
                                DropdownMenuItem(
                                    value: 'em_atendimento',
                                    child: Text('Em atendimento')),
                                DropdownMenuItem(
                                    value: 'concluido',
                                    child: Text('Concluída')),
                                DropdownMenuItem(
                                    value: 'cancelado',
                                    child: Text('Cancelada')),
                                DropdownMenuItem(
                                    value: 'falta', child: Text('Falta'))
                              ],
                              onChanged: busy
                                  ? null
                                  : (value) {
                                      setState(() => status = value);
                                      filter();
                                    })),
                    SizedBox(
                        width: fieldWidth,
                        child: DropdownButtonFormField<String>(
                            key: ValueKey('admin-agenda-specialty-$specialty'),
                            initialValue: specialty,
                            isExpanded: true,
                            itemHeight: null,
                            decoration: const InputDecoration(
                                labelText: 'Especialidade'),
                            items: [
                              const DropdownMenuItem(
                                  value: null, child: Text('Todas')),
                              for (final value in widget.specialties)
                                DropdownMenuItem(
                                    value: value['name'].toString(),
                                    child: Text(
                                        specialtyDisplayName(
                                            value['name'].toString()),
                                        maxLines: 2,
                                        softWrap: true))
                            ],
                            onChanged: busy
                                ? null
                                : (value) {
                                    setState(() => specialty = value);
                                    filter();
                                  })),
                    SizedBox(
                        width: fieldWidth,
                        child: DropdownButtonFormField<int>(
                            key: ValueKey(
                                'admin-agenda-professional-$professionalId'),
                            initialValue: professionalId,
                            isExpanded: true,
                            itemHeight: null,
                            decoration: const InputDecoration(
                                labelText: 'Profissional'),
                            items: [
                              const DropdownMenuItem(
                                  value: null, child: Text('Todos')),
                              for (final value in widget.professionals)
                                DropdownMenuItem(
                                    value: value['id'] as int,
                                    child: Text(value['name'].toString(),
                                        maxLines: 2, softWrap: true))
                            ],
                            onChanged: busy
                                ? null
                                : (value) {
                                    setState(() => professionalId = value);
                                    filter();
                                  })),
                    if (!widget.checkinOnly)
                      SizedBox(
                          width: fieldWidth,
                          child: DropdownButtonFormField<String>(
                              key: ValueKey('admin-agenda-risk-$risk'),
                              initialValue: risk,
                              isExpanded: true,
                              itemHeight: null,
                              decoration: const InputDecoration(
                                  labelText: 'Classificação de risco'),
                              items: [
                                const DropdownMenuItem(
                                    value: null, child: Text('Todas')),
                                for (final item in RiskClassification.options)
                                  DropdownMenuItem(
                                      value: item.$1,
                                      child: AppRiskFilterItem(risk: item.$1)),
                              ],
                              onChanged: busy
                                  ? null
                                  : (value) {
                                      setState(() => risk = value);
                                      filter();
                                    })),
                    SizedBox(
                        width: fieldWidth,
                        child: OutlinedButton.icon(
                            key: const Key('admin-agenda-date'),
                            onPressed: busy
                                ? null
                                : () async {
                                    final picked = await showDatePicker(
                                        context: context,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime.now()
                                            .add(const Duration(days: 730)),
                                        initialDate: day);
                                    if (picked != null) {
                                      setState(() => day = picked);
                                      await filter();
                                    }
                                  },
                            icon: const Icon(Icons.calendar_today_outlined),
                            label: Text('Data: ${showOnlyDate(day)}'))),
                    SizedBox(
                        width: fieldWidth,
                        child: FilledButton.icon(
                            onPressed: busy ? null : filter,
                            icon: const Icon(Icons.filter_alt),
                            label: const Text('Aplicar filtros'))),
                    SizedBox(
                        width: fieldWidth,
                        child: OutlinedButton.icon(
                            key: const Key('admin-agenda-clear-filters'),
                            onPressed: busy ? null : clearFilters,
                            icon: const Icon(Icons.filter_alt_off_outlined),
                            label: const Text('Limpar filtros')))
                  ]);
            }),
          ),
        ),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        if (!busy && items.isEmpty)
          const _EmptyState(
              'Nenhum agendamento encontrado para os filtros selecionados.'),
        for (final item in items)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: LayoutBuilder(builder: (_, c) {
                    final details = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${item.scheduledAt.hour.toString().padLeft(2, '0')}:${item.scheduledAt.minute.toString().padLeft(2, '0')} • ${item.patient}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          Text(
                              '${item.patientDocument} • ${specialtyDisplayName(item.specialty)} • ${item.professional}'),
                          Text('Prioridade: ${item.legalPriority}'),
                          const SizedBox(height: 6),
                          AppStatusBadge(
                              label: 'Status: ${statusLabel(item.status)}',
                              tone: statusToneFor(item.status),
                              semanticLabel:
                                  'Situação: ${statusLabel(item.status)}')
                        ]);
                    final action = Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                          onPressed: () => showDetails(item),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Ver detalhes')),
                      if (item.status == 'agendado' &&
                          (ApiService.session?.can('appointments:checkin') ??
                              false)) ...[
                        FilledButton.icon(
                            onPressed: () => checkIn(item),
                            icon: const Icon(Icons.how_to_reg),
                            label: const Text('Confirmar chegada')),
                        OutlinedButton.icon(
                            onPressed: () => registerAbsence(item),
                            icon: const Icon(Icons.person_off_outlined),
                            label: const Text('Registrar falta')),
                      ]
                    ]);
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          details,
                          const SizedBox(height: 10),
                          action
                        ]);
                  })))
      ]);
}

class _DoctorsView extends StatefulWidget {
  const _DoctorsView(
      {required this.api, required this.initial, required this.onChanged});
  final ApiService api;
  final List<DoctorAccount> initial;
  final Future<void> Function() onChanged;

  @override
  State<_DoctorsView> createState() => _DoctorsViewState();
}

class _DoctorsViewState extends State<_DoctorsView> {
  late List<DoctorAccount> doctors = widget.initial;
  late bool hasActiveDoctor = widget.initial.any((doctor) => doctor.active);
  final search = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> filter() async {
    setState(() => busy = true);
    try {
      final values = await Future.wait([
        widget.api.doctors(search: search.text),
        widget.api.doctors(active: true),
      ]);
      doctors = values[0];
      hasActiveDoctor = values[1].isNotEmpty;
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openForm([DoctorAccount? existing]) async {
    await showDialog<void>(
        context: context,
        builder: (_) => _DoctorDialog(api: widget.api, existing: existing));
    await filter();
    await widget.onChanged();
  }

  Future<void> toggle(DoctorAccount doctor) async {
    if (doctor.active) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Desativar Médico?'),
                content: Text(
                    '${doctor.name} perderá o acesso, mas consultas e histórico serão preservados.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Desativar')),
                ],
              ));
      if (confirmed != true) return;
    }
    try {
      await widget.api.setDoctorActive(doctor.id, !doctor.active);
      await filter();
      await widget.onChanged();
      if (mounted) {
        notice(
            context, doctor.active ? 'Médico desativado.' : 'Médico ativado.');
      }
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      ResponsivePageHeader(
          title: 'Profissionais de atendimento',
          subtitle:
              'Médicos e dentistas com acesso exclusivo à própria fila de atendimento.',
          primaryAction: AppActionButton(
              label: 'Cadastrar Médico',
              icon: Icons.person_add_alt_1,
              onPressed: () => openForm())),
      const SizedBox(height: AppSpacing.md),
      Semantics(
          label: hasActiveDoctor
              ? 'Há Médico ativo para atendimento'
              : 'Não há Médico ativo para atendimento',
          child: AppSurfaceCard(
              child: Row(children: [
            Icon(
                hasActiveDoctor
                    ? Icons.check_circle_outline
                    : Icons.warning_amber,
                color: hasActiveDoctor
                    ? green
                    : Theme.of(context).colorScheme.error),
            const SizedBox(width: AppSpacing.md),
            Expanded(
                child: Text(hasActiveDoctor
                    ? 'Há Médico ativo para atendimento'
                    : 'Não há Médico ativo para atendimento')),
          ]))),
      const SizedBox(height: AppSpacing.md),
      Row(children: [
        Expanded(
            child: TextField(
                key: const Key('doctor-search'),
                controller: search,
                decoration: const InputDecoration(
                    labelText: 'Pesquisar por nome ou CPF',
                    prefixIcon: Icon(Icons.search)),
                onSubmitted: (_) => filter())),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filledTonal(
            tooltip: 'Pesquisar',
            onPressed: busy ? null : filter,
            icon: const Icon(Icons.search)),
      ]),
      const SizedBox(height: AppSpacing.md),
      if (busy) const LinearProgressIndicator(),
      if (!busy && doctors.isEmpty)
        const AppEmptyState(
            icon: Icons.medical_services_outlined,
            title: 'Nenhum Médico encontrado',
            message: 'Cadastre uma conta ou altere o termo pesquisado.'),
      for (final doctor in doctors) ...[
        AppSurfaceCard(child: LayoutBuilder(builder: (context, constraints) {
          final details =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(doctor.name,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text(
                '${doctor.profession} • ${doctor.maskedCpf} • ${specialtyDisplayName(doctor.specialty)}'),
            Text(doctor.active ? 'Ativo' : 'Inativo'),
          ]);
          final actions = Wrap(spacing: 8, runSpacing: 8, children: [
            IconButton(
                tooltip: 'Editar Médico',
                onPressed: () => openForm(doctor),
                icon: const Icon(Icons.edit_outlined)),
            IconButton(
                tooltip: doctor.active ? 'Desativar Médico' : 'Ativar Médico',
                onPressed: () => toggle(doctor),
                icon: Icon(doctor.active
                    ? Icons.block_outlined
                    : Icons.check_circle_outline)),
          ]);
          return constraints.maxWidth < 540
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      details,
                      const SizedBox(height: AppSpacing.sm),
                      Align(alignment: Alignment.centerRight, child: actions),
                    ])
              : Row(children: [
                  Expanded(child: details),
                  actions,
                ]);
        })),
        const SizedBox(height: AppSpacing.sm),
      ],
    ]);
  }
}

class _DoctorDialog extends StatefulWidget {
  const _DoctorDialog({required this.api, this.existing});
  final ApiService api;
  final DoctorAccount? existing;

  @override
  State<_DoctorDialog> createState() => _DoctorDialogState();
}

class _DoctorDialogState extends State<_DoctorDialog> {
  final formKey = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.existing?.name);
  final cpf = TextEditingController();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  late bool active = widget.existing?.active ?? true;
  bool saving = false;

  @override
  void dispose() {
    name.dispose();
    cpf.dispose();
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => saving = true);
    final data = <String, dynamic>{
      'name': name.text.trim(),
      'active': active,
      if (cpf.text.trim().isNotEmpty) 'cpf': digits(cpf.text),
      if (widget.existing == null) 'password': password.text,
      if (widget.existing == null) 'password_confirmation': confirmation.text,
    };
    try {
      if (widget.existing == null) {
        await widget.api.createDoctor(data);
      } else {
        await widget.api.updateDoctor(widget.existing!.id, data);
      }
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.existing == null ? 'Cadastrar Médico' : 'Editar Médico'),
        content: SizedBox(
            width: 540,
            child: Form(
                key: formKey,
                child: SingleChildScrollView(
                    child: Column(children: [
                  TextFormField(
                      controller: name,
                      decoration: const InputDecoration(
                          labelText: 'Nome completo',
                          prefixIcon: Icon(Icons.person_outline)),
                      validator: requiredName),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                      controller: cpf,
                      inputFormatters: [CpfFormatter()],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: widget.existing == null
                              ? 'CPF'
                              : 'Novo CPF (opcional)',
                          prefixIcon: const Icon(Icons.badge_outlined)),
                      validator: (value) => widget.existing != null &&
                              (value ?? '').trim().isEmpty
                          ? null
                          : requiredCpf(value)),
                  if (widget.existing == null) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                        controller: password,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'Senha',
                            prefixIcon: Icon(Icons.lock_outline)),
                        validator: passwordRule),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                        controller: confirmation,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'Confirmar senha',
                            prefixIcon: Icon(Icons.lock_reset)),
                        validator: (value) => value != password.text
                            ? 'As senhas não coincidem.'
                            : null),
                  ],
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Conta ativa'),
                      value: active,
                      onChanged: saving
                          ? null
                          : (value) => setState(() => active = value)),
                  const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.health_and_safety_outlined),
                      title: Text('Perfil: Médico'),
                      subtitle: Text('Especialidade inicial: Clínica Geral')),
                ])))),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton.icon(
              onPressed: saving ? null : save,
              icon: const Icon(Icons.save_outlined),
              label: Text(saving ? 'Salvando...' : 'Salvar')),
        ],
      );
}

class _InternalUsersView extends StatefulWidget {
  const _InternalUsersView(
      {required this.api,
      required this.initial,
      required this.specialties,
      required this.professionalOnly,
      required this.onChanged});
  final ApiService api;
  final List<InternalUser> initial;
  final List<Map<String, dynamic>> specialties;
  final bool professionalOnly;
  final Future<void> Function() onChanged;
  @override
  State<_InternalUsersView> createState() => _InternalUsersViewState();
}

class _InternalUsersViewState extends State<_InternalUsersView> {
  late List<InternalUser> users = widget.initial;
  final search = TextEditingController();
  String? role;
  bool? active;
  bool busy = false;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> filter() async {
    setState(() => busy = true);
    try {
      users = await widget.api.internalUsers(
          search: search.text,
          role: widget.professionalOnly ? 'medico' : role,
          active: active);
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggle(InternalUser user) async {
    if (user.active) {
      final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Desativar usuário?'),
                  content: Text(
                      '${user.name} perderá o acesso, mas seu histórico será preservado.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Desativar'))
                  ]));
      if (ok != true) return;
    }
    try {
      await widget.api.setInternalUserActive(user.id, !user.active);
      await filter();
      await widget.onChanged();
      if (mounted) {
        notice(
            context, user.active ? 'Usuário desativado.' : 'Usuário ativado.');
      }
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(children: [
        ResponsivePageHeader(
            title:
                widget.professionalOnly ? 'Profissionais' : 'Usuários internos',
            subtitle: widget.professionalOnly
                ? 'Profissionais, especialidades e autorização para triagem.'
                : 'Recepcionistas e profissionais. Paciente não é uma opção nesta tela.',
            primaryAction: AppActionButton(
                label: 'Cadastrar usuário',
                icon: Icons.person_add,
                onPressed: () => _openForm())),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final fieldWidth =
              responsiveFilterWidth(constraints.maxWidth, maxColumns: 3);
          return Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(
                width: fieldWidth,
                child: TextField(
                    controller: search,
                    decoration: const InputDecoration(
                        labelText: 'Pesquisar por nome',
                        prefixIcon: Icon(Icons.search)),
                    onSubmitted: (_) => filter())),
            if (!widget.professionalOnly)
              SizedBox(
                  width: fieldWidth,
                  child: DropdownButtonFormField<String>(
                      initialValue: role,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Perfil'),
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Todos')),
                        DropdownMenuItem(
                            value: 'recepcao', child: Text('Recepção')),
                        DropdownMenuItem(
                            value: 'enfermagem', child: Text('Enfermagem')),
                        DropdownMenuItem(value: 'medico', child: Text('Médico'))
                      ],
                      onChanged: (v) {
                        role = v;
                        filter();
                      })),
            SizedBox(
                width: fieldWidth,
                child: DropdownButtonFormField<bool>(
                    initialValue: active,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Situação'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Todas')),
                      DropdownMenuItem(value: true, child: Text('Ativa')),
                      DropdownMenuItem(value: false, child: Text('Inativa'))
                    ],
                    onChanged: (v) {
                      active = v;
                      filter();
                    }))
          ]);
        }),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        if (!busy && users.isEmpty)
          const _EmptyState(
              'Nenhum usuário encontrado para os filtros selecionados.'),
        for (final user in users)
          Card(child: LayoutBuilder(builder: (context, constraints) {
            final identity = ListTile(
                leading: CircleAvatar(
                    child: Icon(
                        user.role == 'medico' || user.role == 'enfermagem'
                            ? Icons.medical_services
                            : Icons.support_agent)),
                title: Text(user.name),
                subtitle: Text(
                    '${user.profession ?? (user.role == 'admin' ? 'Administrador' : 'Recepção')} • ${user.maskedCpf}\n${user.email}${user.specialty == null ? '' : ' • ${specialtyDisplayName(user.specialty!)}'}'),
                isThreeLine: true);
            final actions = Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(user.active ? Icons.check_circle : Icons.block,
                  color: user.active
                      ? green
                      : Theme.of(context).colorScheme.error),
              const SizedBox(width: 6),
              Text(user.active ? 'Ativo' : 'Inativo'),
              PopupMenuButton<String>(
                  tooltip: 'Ações do usuário',
                  onSelected: (action) {
                    if (action == 'edit') {
                      _openForm(user);
                    } else if (action == 'access') {
                      _resetAccess(user);
                    } else if (action == 'toggle') {
                      toggle(user);
                    }
                  },
                  itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'edit', child: Text('Editar dados')),
                        const PopupMenuItem(
                            value: 'access', child: Text('Redefinir acesso')),
                        PopupMenuItem(
                            value: 'toggle',
                            child: Text(user.active ? 'Desativar' : 'Ativar'))
                      ])
            ]);
            if (constraints.maxWidth < 600) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                        child: Align(
                            alignment: Alignment.centerRight, child: actions))
                  ]);
            }
            return Row(children: [
              Expanded(child: identity),
              const SizedBox(width: 8),
              actions,
              const SizedBox(width: 8),
            ]);
          }))
      ]);

  Future<void> _openForm([InternalUser? existing]) async {
    await showDialog<void>(
        context: context,
        builder: (_) => _InternalUserDialog(
            api: widget.api,
            existing: existing,
            specialties: widget.specialties));
    await filter();
    await widget.onChanged();
  }

  Future<void> _resetAccess(InternalUser user) async {
    final password = TextEditingController(),
        confirmation = TextEditingController();
    final key = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Redefinir acesso'),
                content: Form(
                    key: key,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          'Defina uma nova senha provisória para ${user.name}.'),
                      const SizedBox(height: 12),
                      TextFormField(
                          controller: password,
                          obscureText: true,
                          validator: passwordRule,
                          decoration: const InputDecoration(
                              labelText: 'Nova senha provisória')),
                      const SizedBox(height: 12),
                      TextFormField(
                          controller: confirmation,
                          obscureText: true,
                          validator: (v) => v != password.text
                              ? 'As senhas não coincidem.'
                              : null,
                          decoration:
                              const InputDecoration(labelText: 'Confirmação'))
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () {
                        if (key.currentState!.validate()) {
                          Navigator.pop(c, true);
                        }
                      },
                      child: const Text('Redefinir'))
                ]));
    if (accepted == true) {
      try {
        await widget.api
            .resetInternalAccess(user.id, password.text, confirmation.text);
        if (mounted) {
          notice(
              context, 'Acesso redefinido. A senha anterior foi invalidada.');
        }
      } on ApiException catch (e) {
        if (mounted) notice(context, e.message);
      }
    }
    password.dispose();
    confirmation.dispose();
  }
}

class _InternalUserDialog extends StatefulWidget {
  const _InternalUserDialog(
      {required this.api, required this.existing, required this.specialties});
  final ApiService api;
  final InternalUser? existing;
  final List<Map<String, dynamic>> specialties;
  @override
  State<_InternalUserDialog> createState() => _InternalUserDialogState();
}

class _InternalUserDialogState extends State<_InternalUserDialog> {
  final key = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.existing?.name),
      cpf = TextEditingController(),
      email = TextEditingController(text: widget.existing?.email),
      registration = TextEditingController(
          text: widget.existing?.professionalRegistration),
      password = TextEditingController(),
      confirmation = TextEditingController();
  late String role = widget.existing?.role ?? 'recepcao';
  late int? specialtyId = widget.existing?.specialtyId;
  late bool canTriage = widget.existing?.canTriage ?? false;
  bool saving = false;
  Map<String, String> errors = {};

  @override
  void dispose() {
    for (final c in [name, cpf, email, registration, password, confirmation]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() => errors = {});
    if (!key.currentState!.validate()) return;
    setState(() => saving = true);
    final data = <String, dynamic>{
      'name': name.text.trim(),
      'email': email.text.trim(),
      'role': role,
      if (role == 'medico' || role == 'enfermagem')
        'professional_registration': registration.text.trim(),
      if (role == 'medico' || role == 'enfermagem') 'specialty_id': specialtyId,
      if (role == 'enfermagem') 'can_triage': true
    };
    if (widget.existing == null) {
      data.addAll({
        'cpf': digits(cpf.text),
        'password': password.text,
        'password_confirmation': confirmation.text,
        'active': true
      });
    }
    try {
      if (widget.existing == null) {
        await widget.api.createInternalUser(data);
      } else {
        await widget.api.updateInternalUser(widget.existing!.id, data);
      }
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          if (e.field != null) {
            errors[e.field!] = e.message;
          } else {
            notice(context, e.message);
          }
        });
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          actionsOverflowDirection: VerticalDirection.down,
          title: Text(widget.existing == null
              ? 'Cadastrar usuário interno'
              : 'Editar usuário interno'),
          content: SizedBox(
              width: 560,
              child: Form(
                  key: key,
                  child: SingleChildScrollView(
                      child: Column(children: [
                    field(name, 'Nome completo', Icons.person_outline,
                        validator: requiredName, errorText: errors['name']),
                    if (widget.existing == null)
                      field(cpf, 'CPF', Icons.badge_outlined,
                          validator: requiredCpf,
                          errorText: errors['cpf'],
                          inputFormatters: [CpfFormatter()],
                          number: true),
                    field(email, 'E-mail', Icons.email_outlined,
                        validator: emailRule, errorText: errors['email']),
                    DropdownButtonFormField<String>(
                        initialValue: role,
                        isExpanded: true,
                        itemHeight: null,
                        decoration: const InputDecoration(labelText: 'Perfil'),
                        items: const [
                          DropdownMenuItem(
                              value: 'recepcao', child: Text('Recepção')),
                          DropdownMenuItem(
                              value: 'enfermagem', child: Text('Enfermagem')),
                          DropdownMenuItem(
                              value: 'medico', child: Text('Médico'))
                        ],
                        onChanged: (v) => setState(() {
                              role = v!;
                              if (role == 'recepcao') {
                                specialtyId = null;
                                canTriage = false;
                              }
                            })),
                    const SizedBox(height: 16),
                    if (role == 'medico' || role == 'enfermagem') ...[
                      field(registration, 'Registro profissional',
                          Icons.workspace_premium_outlined,
                          errorText: errors['professional_registration']),
                      DropdownButtonFormField<int>(
                          initialValue: specialtyId,
                          isExpanded: true,
                          itemHeight: null,
                          decoration: InputDecoration(
                              labelText: 'Especialidade',
                              errorText: errors['specialty_id']),
                          validator: (v) =>
                              v == null ? 'Selecione a especialidade.' : null,
                          items: [
                            for (final item in widget.specialties)
                              DropdownMenuItem(
                                  value: item['id'] as int,
                                  child: Text(
                                      specialtyDisplayName(
                                          item['name'].toString()),
                                      softWrap: true,
                                      maxLines: 2))
                          ],
                          onChanged: (v) => setState(() => specialtyId = v)),
                      if (role == 'enfermagem')
                        const ListTile(
                            leading: Icon(Icons.verified_user_outlined),
                            title: Text('Autorizado a realizar triagem'),
                            subtitle: Text(
                                'Permissão exclusiva do perfil Enfermagem.')),
                    ],
                    if (widget.existing == null) ...[
                      field(password, 'Senha provisória', Icons.lock_outline,
                          secret: true,
                          validator: passwordRule,
                          errorText: errors['password']),
                      field(confirmation, 'Confirmação da senha',
                          Icons.lock_reset,
                          secret: true,
                          validator: (v) => v != password.text
                              ? 'As senhas não coincidem.'
                              : null,
                          errorText: errors['password_confirmation']),
                    ]
                  ])))),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            AppActionButton(label: 'Salvar', onPressed: save, busy: saving)
          ]);
}

class _GridAdminView extends StatelessWidget {
  const _GridAdminView(
      {required this.api,
      required this.grids,
      required this.specialties,
      required this.onChanged});
  final ApiService api;
  final List<Map<String, dynamic>> grids, specialties;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) => ListView(children: [
        Row(children: [
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Horários disponíveis',
                    style:
                        TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
                Text(
                    'Períodos configuráveis, duração, vagas e intervalo de almoço.')
              ])),
          FilledButton.icon(
              onPressed: () => _open(context),
              icon: const Icon(Icons.add),
              label: const Text('Nova grade'))
        ]),
        const SizedBox(height: 16),
        if (grids.isEmpty) const _EmptyState('Nenhuma grade cadastrada.'),
        for (final item in grids)
          Card(
              child: ListTile(
                  leading: const Icon(Icons.calendar_month),
                  title: Text(
                      '${item['professional']} • ${specialtyDisplayName(item['specialty'].toString())}'),
                  subtitle: Text(
                      '${item['day']} • ${item['start_time']} às ${item['end_time']} • ${item['duration_minutes']} min • ${item['capacity']} vaga(s)\nIntervalo: ${item['break_start'] ?? 'sem'}${item['break_end'] == null ? '' : ' às ${item['break_end']}'}'),
                  isThreeLine: true,
                  trailing: IconButton(
                      tooltip: 'Remover disponibilidade',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(context, item))))
      ]);

  Future<void> _remove(BuildContext context, Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Remover disponibilidade?'),
              content: const Text(
                  'Horários com consultas vinculadas serão preservados e não podem ser removidos.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Remover')),
              ],
            ));
    if (confirmed != true) return;
    try {
      await api.removeGrid(item['id'] as int);
      await onChanged();
      if (context.mounted) notice(context, 'Disponibilidade removida.');
    } on ApiException catch (e) {
      if (context.mounted) notice(context, e.message);
    }
  }

  Future<void> _open(BuildContext context) async {
    final professionals = await api.allProfessionals();
    if (!context.mounted) return;
    await showDialog<void>(
        context: context,
        builder: (_) => _GridDialog(
            api: api, professionals: professionals, specialties: specialties));
    await onChanged();
  }
}

class _GridDialog extends StatefulWidget {
  const _GridDialog(
      {required this.api,
      required this.professionals,
      required this.specialties});
  final ApiService api;
  final List<Map<String, dynamic>> professionals, specialties;
  @override
  State<_GridDialog> createState() => _GridDialogState();
}

class _GridDialogState extends State<_GridDialog> {
  final key = GlobalKey<FormState>();
  final day = TextEditingController(),
      start = TextEditingController(text: '09:00'),
      end = TextEditingController(text: '11:00'),
      duration = TextEditingController(text: '60'),
      capacity = TextEditingController(text: '1'),
      breakStart = TextEditingController(),
      breakEnd = TextEditingController();
  int? professionalId, specialtyId;
  bool saving = false;
  @override
  void dispose() {
    for (final c in [
      day,
      start,
      end,
      duration,
      capacity,
      breakStart,
      breakEnd
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.api.createGrid({
        'professional_id': professionalId,
        'specialty_id': specialtyId,
        'day': day.text,
        'start_time': start.text,
        'end_time': end.text,
        'duration_minutes': int.parse(duration.text),
        'capacity': int.parse(capacity.text),
        if (breakStart.text.isNotEmpty) 'break_start': breakStart.text,
        if (breakEnd.text.isNotEmpty) 'break_end': breakEnd.text
      });
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Nova grade de atendimento'),
          content: SizedBox(
              width: 560,
              child: Form(
                  key: key,
                  child: SingleChildScrollView(
                      child: Column(children: [
                    DropdownButtonFormField<int>(
                        initialValue: professionalId,
                        isExpanded: true,
                        itemHeight: null,
                        decoration:
                            const InputDecoration(labelText: 'Profissional'),
                        validator: (v) =>
                            v == null ? 'Selecione o profissional.' : null,
                        items: [
                          for (final x in widget.professionals)
                            DropdownMenuItem(
                                value: x['id'] as int,
                                child: Text(x['name'].toString(),
                                    maxLines: 2, softWrap: true))
                        ],
                        onChanged: (v) => professionalId = v),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                        initialValue: specialtyId,
                        isExpanded: true,
                        itemHeight: null,
                        decoration:
                            const InputDecoration(labelText: 'Especialidade'),
                        validator: (v) =>
                            v == null ? 'Selecione a especialidade.' : null,
                        items: [
                          for (final x in widget.specialties)
                            DropdownMenuItem(
                                value: x['id'] as int,
                                child: Text(
                                    specialtyDisplayName(x['name'].toString()),
                                    maxLines: 2,
                                    softWrap: true))
                        ],
                        onChanged: (v) => specialtyId = v),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: day,
                        readOnly: true,
                        onTap: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                              context: context,
                              firstDate: DateTime(now.year, now.month, now.day),
                              lastDate: now.add(const Duration(days: 730)),
                              initialDate: now);
                          if (picked != null) {
                            day.text =
                                picked.toIso8601String().substring(0, 10);
                          }
                        },
                        decoration: const InputDecoration(
                            labelText: 'Data',
                            suffixIcon: Icon(Icons.calendar_today)),
                        validator: (v) => DateTime.tryParse(v ?? '') == null
                            ? 'Informe uma data válida.'
                            : null),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, constraints) {
                      final fieldWidth = responsiveFilterWidth(
                          constraints.maxWidth,
                          minWidth: 150,
                          maxColumns: 3);
                      return Wrap(spacing: 12, runSpacing: 12, children: [
                        SizedBox(
                            width: fieldWidth,
                            child: TextFormField(
                                controller: start,
                                decoration: const InputDecoration(
                                    labelText: 'Início'))),
                        SizedBox(
                            width: fieldWidth,
                            child: TextFormField(
                                controller: end,
                                decoration:
                                    const InputDecoration(labelText: 'Fim'))),
                        SizedBox(
                            width: fieldWidth,
                            child: TextFormField(
                                controller: duration,
                                readOnly: true,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Duração (min)'))),
                        SizedBox(
                            width: fieldWidth,
                            child: TextFormField(
                                controller: capacity,
                                readOnly: true,
                                keyboardType: TextInputType.number,
                                decoration:
                                    const InputDecoration(labelText: 'Vagas'))),
                        SizedBox(
                            width: fieldWidth,
                            child: TextFormField(
                                controller: breakStart,
                                decoration: const InputDecoration(
                                    labelText: 'Início intervalo'))),
                        SizedBox(
                            width: fieldWidth,
                            child: TextFormField(
                                controller: breakEnd,
                                decoration: const InputDecoration(
                                    labelText: 'Fim intervalo'))),
                      ]);
                    }),
                    const SizedBox(height: 12),
                    const InfoPanel(
                        icon: Icons.schedule,
                        text:
                            'Consultas duram 1 hora. Horários permitidos: 07:00 a 11:00 e 13:00 a 16:00, somente em dias úteis não feriados.')
                  ])))),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Salvando...' : 'Salvar grade'))
          ]);
}
