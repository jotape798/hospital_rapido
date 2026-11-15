part of '../main.dart';

class PatientDashboard extends StatefulWidget {
  const PatientDashboard({super.key, this.api});
  final ApiService? api;
  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  late final ApiService api = widget.api ?? ApiService();
  final ScrollController _bodyScrollController = ScrollController();
  PatientSummary? summary;
  List<Appointment> items = [];
  Timer? refreshTimer;
  bool loading = true, requesting = false;
  final Set<int> cancelling = {};
  final Set<String> _knownPriorityDecisions = {};
  bool _priorityDecisionsInitialized = false;
  String? error;
  int page = 0;

  @override
  void initState() {
    super.initState();
    load();
    refreshTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => load(quiet: true));
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    _bodyScrollController.dispose();
    super.dispose();
  }

  Future<void> load({bool quiet = false}) async {
    if (!mounted || requesting) return;
    requesting = true;
    try {
      final values =
          await Future.wait<Object>([api.summary(), api.appointments()]);
      final next = values[0] as PatientSummary;
      final all = values[1] as List<Appointment>;
      if (mounted) {
        String? changedStatus;
        String? priorityDecisionNotice;
        if (quiet) {
          final previous = {for (final item in items) item.id: item.status};
          for (final item in all) {
            if (previous[item.id] != null && previous[item.id] != item.status) {
              changedStatus = statusLabel(item.status);
              break;
            }
          }
        }
        final decisions = next.patient.priorityConditions.where((item) {
          final status = item['status']?.toString();
          return status == 'confirmada' || status == 'rejeitada';
        }).toList();
        if (quiet && _priorityDecisionsInitialized) {
          for (final item in decisions) {
            final key = _priorityDecisionKey(item);
            if (!_knownPriorityDecisions.contains(key)) {
              priorityDecisionNotice = _priorityDecisionText(item);
              break;
            }
          }
        }
        _knownPriorityDecisions
          ..clear()
          ..addAll(decisions.map(_priorityDecisionKey));
        _priorityDecisionsInitialized = true;
        setState(() {
          summary = next;
          items = all;
          error = null;
          loading = false;
        });
        if (changedStatus != null) {
          announceImportant(
              context, 'Status da consulta alterado para $changedStatus');
        }
        if (priorityDecisionNotice != null) {
          notice(context, priorityDecisionNotice);
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        refreshTimer?.cancel();
        Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
        return;
      }
      if (!quiet || summary == null) {
        setState(() {
          error = e.message;
          loading = false;
        });
      }
    } finally {
      requesting = false;
    }
  }

  Future<void> logout() async {
    refreshTimer?.cancel();
    await ApiService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
    }
  }

  void openBooking([Appointment? old]) {
    booking(context, api, old, _refreshAfterBooking);
  }

  Future<void> _refreshAfterBooking() async {
    while (requesting && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    await load();
    _scrollBodyToStart();
  }

  void _scrollBodyToStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_bodyScrollController.hasClients) {
        _bodyScrollController.jumpTo(0);
      }
    });
  }

  void _selectPage(int value) {
    if (page == value) return;
    setState(() => page = value);
    _scrollBodyToStart();
  }

  void details(Appointment item) {
    final now = DateTime.now();
    final canCancel = item.status == 'agendado' &&
        !item.scheduledAt.isBefore(now.add(const Duration(hours: 24)));
    final canReschedule = item.status == 'agendado' &&
        !item.scheduledAt.isBefore(now.add(const Duration(hours: 12)));
    showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Detalhes da consulta'),
              content: SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(specialtyDisplayName(item.specialty),
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(item.professional),
                  Text(showDate(item.scheduledAt)),
                  if (item.location != null) Text(item.location!),
                  Semantics(
                      label: 'Status da consulta: ${statusLabel(item.status)}',
                      child: Text('Status: ${statusLabel(item.status)}')),
                  const SizedBox(height: 12),
                  StatusTimeline(status: item.status, compact: true),
                  if (item.status == 'agendado' && !canCancel)
                    const Text('Cancelamento disponível até 24 horas antes.'),
                  if (item.status == 'agendado' && !canReschedule)
                    const Text('Reagendamento disponível até 12 horas antes.'),
                ],
              )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Fechar')),
                if (item.status == 'agendado')
                  TextButton(
                      onPressed: canReschedule
                          ? () {
                              Navigator.pop(dialogContext);
                              openBooking(item);
                            }
                          : null,
                      child: const Text('Reagendar')),
                if (item.status == 'agendado')
                  AppActionButton(
                      onPressed: canCancel && !cancelling.contains(item.id)
                          ? () {
                              Navigator.pop(dialogContext);
                              cancel(item);
                            }
                          : null,
                      icon: Icons.cancel_outlined,
                      label: 'Cancelar consulta',
                      semanticLabel: 'Cancelar consulta, ação destrutiva',
                      destructive: true),
              ],
            ));
  }

  Future<void> cancel(Appointment item) async {
    if (cancelling.contains(item.id)) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: const Text('Cancelar consulta'),
              content: Text(
                  'Esta ação cancelará o agendamento de ${specialtyDisplayName(item.specialty)} em ${showDate(item.scheduledAt)}.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Voltar')),
                AppActionButton(
                    onPressed: () => Navigator.pop(c, true),
                    icon: Icons.cancel_outlined,
                    label: 'Confirmar cancelamento',
                    semanticLabel: 'Confirmar cancelamento, ação destrutiva',
                    destructive: true)
              ],
            ));
    if (confirmed != true || !mounted) return;
    setState(() {
      cancelling.add(item.id);
    });
    try {
      final message = await api.cancel(item.id);
      await load();
      if (mounted) notice(context, message);
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    } finally {
      if (mounted) {
        setState(() {
          cancelling.remove(item.id);
        });
      }
    }
  }

  Widget statusBadge(String status) {
    final contrast = accessibility.highContrast;
    final cancelled = status == 'cancelado' || status == 'falta';
    final color = cancelled ? const Color(0xFFB42318) : green;
    return Semantics(
        label: 'Status da consulta: ${statusLabel(status)}',
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
                color: contrast ? Colors.black : color.withValues(alpha: .10),
                border: Border.all(
                    color: contrast ? Colors.yellow : color,
                    width: contrast ? 2 : 1),
                borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(cancelled ? Icons.cancel_outlined : Icons.check_circle,
                  size: 17, color: contrast ? Colors.yellow : color),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(statusLabel(status),
                      softWrap: true,
                      style: TextStyle(
                          color: contrast ? Colors.white : color,
                          fontWeight: FontWeight.w700)))
            ])));
  }

  String _priorityConditionLabel(Map<String, dynamic> item) =>
      switch (item['condition']) {
        'pcd' => 'PCD',
        'gestante' => 'Gestante',
        'lactante' => 'Lactante',
        _ => item['condition']?.toString() ?? 'Condição prioritária',
      };

  String _priorityDecisionKey(Map<String, dynamic> item) =>
      '${item['condition']}|${item['status']}|${item['validated_at']}';

  String _priorityDecisionEffect(String status) => status == 'confirmada'
      ? 'A condição foi incluída no cálculo da prioridade dos próximos atendimentos.'
      : 'A condição não altera sua prioridade de atendimento. Procure a Recepção se precisar de orientação.';

  String _priorityDecisionText(Map<String, dynamic> item) {
    final label = _priorityConditionLabel(item);
    final confirmed = item['status'] == 'confirmada';
    return '$label ${confirmed ? 'confirmada' : 'rejeitada'}. ${_priorityDecisionEffect(item['status'].toString())}';
  }

  Widget _priorityDecisionAlert(Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? '';
    final label = _priorityConditionLabel(item);
    final confirmed = status == 'confirmada';
    final validatedAt = item['validated_at']?.toString();
    final decisionDate = validatedAt == null
        ? 'Data da decisão não informada'
        : 'Decisão em ${showDate(DateTime.parse(validatedAt))}';
    final effect = _priorityDecisionEffect(status);
    return Semantics(
        key: ValueKey('priority-decision-${item['condition']}-$status'),
        container: true,
        liveRegion: true,
        label:
            'Aviso de condição prioritária. $label. ${confirmed ? 'Confirmada' : 'Rejeitada'}. $decisionDate. $effect',
        child: AppSurfaceCard(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(confirmed ? Icons.verified_outlined : Icons.info_outline,
              color: confirmed ? green : Colors.orange.shade800),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Aviso sobre $label',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(confirmed
                    ? 'Resultado: confirmada'
                    : 'Resultado: rejeitada'),
                Text(decisionDate),
                const SizedBox(height: 4),
                Text(effect),
              ]))
        ])));
  }

  Widget consultationCard(Appointment item) => Semantics(
      container: true,
      label:
          'Consulta. Especialidade: ${specialtyDisplayName(item.specialty)}. Profissional: ${item.professional}. Data e horário: ${showDate(item.scheduledAt)}. Status da consulta: ${statusLabel(item.status)}',
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(builder: (context, constraints) {
                      final title = Text(specialtyDisplayName(item.specialty),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800));
                      if (constraints.maxWidth < 480) {
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              const SizedBox(height: 10),
                              statusBadge(item.status)
                            ]);
                      }
                      return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: title),
                            const SizedBox(width: 10),
                            statusBadge(item.status),
                          ]);
                    }),
                    const SizedBox(height: 16),
                    _appointmentLine(
                        Icons.medical_services_outlined, item.professional),
                    const SizedBox(height: 9),
                    _appointmentLine(
                        Icons.event_outlined, showDate(item.scheduledAt)),
                    if (item.location != null) ...[
                      const SizedBox(height: 9),
                      _appointmentLine(
                          Icons.location_on_outlined, item.location!),
                    ],
                    const SizedBox(height: 18),
                    Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                            onPressed: () => details(item),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Ver detalhes'))),
                  ]))));

  Widget _appointmentLine(IconData icon, String text) => Row(children: [
        Icon(icon, size: 19, color: accessibility.highContrast ? null : blue),
        const SizedBox(width: 9),
        Expanded(child: Text(text))
      ]);

  Widget home() {
    final next = summary?.nextAppointment;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _pageHeading(Icons.home_outlined, 'Início'),
      const SizedBox(height: 24),
      Text('Próxima consulta',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      if (next == null)
        AppEmptyState(
            title: 'Nenhuma consulta agendada',
            message: 'Você não possui consultas agendadas.',
            actionLabel: 'Agendar consulta',
            onAction: () => openBooking())
      else
        consultationCard(next),
      const SizedBox(height: 28),
      Text('Acesso rápido',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 650;
        final width =
            wide ? (constraints.maxWidth - 24) / 3 : constraints.maxWidth;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          shortcut(width, Icons.add_circle_outline, 'Agendar consulta',
              () => openBooking()),
          shortcut(width, Icons.calendar_month, 'Minhas consultas',
              () => setState(() => page = 1)),
          shortcut(width, Icons.timeline, 'Acompanhar status',
              () => setState(() => page = 2)),
        ]);
      }),
    ]);
  }

  Widget shortcut(
          double width, IconData icon, String title, VoidCallback action) =>
      SizedBox(
          width: width,
          child: Card(
              child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ListTile(
                      leading: Icon(icon),
                      title: Text(title),
                      onTap: action))));

  Widget consultationList() {
    final now = DateTime.now();
    final upcoming = items
        .where((x) =>
            !['cancelado', 'concluido', 'falta'].contains(x.status) &&
            x.scheduledAt.isAfter(now))
        .toList();
    final completed = items
        .where((x) => x.status == 'concluido' || x.status == 'falta')
        .toList();
    final cancelled = items.where((x) => x.status == 'cancelado').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      section('Próximas', upcoming),
      section('Concluídas', completed),
      section('Canceladas', cancelled),
    ]);
  }

  Widget section(String title, List<Appointment> values) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 22),
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (values.isEmpty)
          _emptyState('Nenhuma consulta nesta categoria.')
        else
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1020
                ? 3
                : constraints.maxWidth >= 650
                    ? 2
                    : 1;
            const gap = 16.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: values
                    .map((item) =>
                        SizedBox(width: width, child: consultationCard(item)))
                    .toList());
          }),
      ]);

  Widget statusPage() {
    final tracked = items.where((x) => x.status != 'cancelado').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _pageHeading(Icons.timeline, 'Acompanhar status'),
      const SizedBox(height: 8),
      Row(children: [
        Icon(Icons.sync,
            size: 16,
            color: accessibility.highContrast ? null : Colors.black54),
        const SizedBox(width: 6),
        Text('Atualização automática a cada cinco segundos.',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
      const SizedBox(height: 20),
      if (tracked.isEmpty)
        _emptyState('Nenhuma consulta para acompanhar.')
      else
        ...tracked.map((x) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Card(
                child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(builder: (context, constraints) {
                            final narrow = constraints.maxWidth < 560;
                            final details = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(specialtyDisplayName(x.specialty),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 8),
                                  _appointmentLine(
                                      Icons.medical_services_outlined,
                                      x.professional),
                                  const SizedBox(height: 7),
                                  _appointmentLine(Icons.event_outlined,
                                      showDate(x.scheduledAt)),
                                ]);
                            if (narrow) {
                              return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    details,
                                    const SizedBox(height: 14),
                                    statusBadge(x.status)
                                  ]);
                            }
                            return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: details),
                                  const SizedBox(width: 16),
                                  statusBadge(x.status)
                                ]);
                          }),
                          const SizedBox(height: 24),
                          StatusTimeline(status: x.status),
                        ]))))),
    ]);
  }

  Widget profilePage() {
    final p = summary!.patient;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _pageHeading(Icons.person_outline, 'Perfil'),
      const SizedBox(height: 20),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                              color: accessibility.highContrast
                                  ? Colors.black
                                  : blue.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(14)),
                          child: Icon(Icons.person_outline,
                              color: accessibility.highContrast
                                  ? Colors.yellow
                                  : blue)),
                      const SizedBox(width: 14),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('Dados pessoais',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            const Text('Informações do paciente')
                          ]))
                    ]),
                    const SizedBox(height: 24),
                    LayoutBuilder(builder: (context, constraints) {
                      final width = constraints.maxWidth >= 650
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;
                      return Wrap(spacing: 16, runSpacing: 16, children: [
                        _profileField(
                            width, Icons.badge_outlined, 'Nome', p.name),
                        _profileField(
                            width, Icons.fingerprint, 'CPF', p.maskedCpf),
                        _profileField(
                            width,
                            Icons.cake_outlined,
                            'Data de nascimento',
                            p.birthDate == null
                                ? 'Não informado'
                                : showOnlyDate(p.birthDate!)),
                        _profileField(
                            width, Icons.email_outlined, 'E-mail', p.email),
                        _profileField(width, Icons.phone_outlined, 'Telefone',
                            formatBrazilianPhone(p.phone)),
                        _profileField(width, Icons.priority_high, 'Prioridade',
                            p.priorityReason),
                      ]);
                    }),
                    if (p.priorityConditions.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ...p.priorityConditions
                          .where((item) =>
                              item['status'] == 'confirmada' ||
                              item['status'] == 'rejeitada')
                          .map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _priorityDecisionAlert(item))),
                      ...p.priorityConditions.map((item) {
                        final status = item['status']?.toString() ?? 'pendente';
                        final label = _priorityConditionLabel(item);
                        final message = switch (status) {
                          'confirmada' => 'Confirmada presencialmente',
                          'rejeitada' => 'Rejeitada na validação presencial',
                          _ => 'Aguardando confirmação presencial',
                        };
                        return Semantics(
                            label: '$label. $message',
                            child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading:
                                    const Icon(Icons.verified_user_outlined),
                                title: Text(label),
                                subtitle: Text(message)));
                      }),
                    ],
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RecoveryPage())),
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Recuperar senha')),
                  ]))),
    ]);
  }

  Widget _pageHeading(IconData icon, String title) => Row(children: [
        Icon(icon, size: 30, color: accessibility.highContrast ? null : blue),
        const SizedBox(width: 12),
        Expanded(
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w800)))
      ]);

  Widget _emptyState(String message) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
          color: accessibility.highContrast ? Colors.black : Colors.white,
          border: Border.all(
              color: accessibility.highContrast
                  ? Colors.yellow
                  : const Color(0xFFE1E7ED)),
          borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Icon(Icons.event_busy_outlined,
            color: accessibility.highContrast ? Colors.yellow : Colors.black45),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center)
      ]));

  Widget _shellActions() => OutlinedButton.icon(
      onPressed: logout,
      icon: const Icon(Icons.logout, size: 18),
      label: const Text('Sair'));

  Widget _profileField(
          double width, IconData icon, String label, String value) =>
      SizedBox(
          width: width,
          child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                  color: accessibility.highContrast
                      ? Colors.black
                      : const Color(0xFFF5F8FA),
                  border: Border.all(
                      color: accessibility.highContrast
                          ? Colors.yellow
                          : const Color(0xFFE1E7ED)),
                  borderRadius: BorderRadius.circular(12)),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon,
                    size: 20,
                    color: accessibility.highContrast ? Colors.yellow : blue),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(label,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: accessibility.highContrast
                                      ? Colors.white
                                      : Colors.black54)),
                      const SizedBox(height: 3),
                      Text(value,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600))
                    ]))
              ])));

  @override
  Widget build(BuildContext context) {
    final firstName = summary?.patient.name.split(' ').first ??
        ApiService.session?.name.split(' ').first ??
        '';
    final titles = [
      'Olá, $firstName!',
      'Minhas consultas',
      'Acompanhar status',
      'Perfil'
    ];
    return ResponsiveAppShell(
        wideNavigationMode: WideNavigationMode.overlayDrawer,
        title: titles[page],
        subtitle: page == 0
            ? 'Acompanhe sua saúde e seus próximos atendimentos.'
            : null,
        destinations: const [
          AppDestination(icon: Icons.home_outlined, label: 'Início'),
          AppDestination(
              icon: Icons.calendar_month_outlined, label: 'Consultas'),
          AppDestination(icon: Icons.timeline, label: 'Status'),
          AppDestination(icon: Icons.person_outline, label: 'Perfil'),
        ],
        selectedIndex: page,
        onDestinationSelected: _selectPage,
        primaryAction: !loading && summary != null && error == null
            ? _shellActions()
            : null,
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null && summary == null
                ? AppErrorState(message: error!, onAction: load)
                : LayoutBuilder(builder: (context, constraints) {
                    final persistentScrollbar = constraints.maxWidth >= 900;
                    return Scrollbar(
                        key: const Key('patient-body-scrollbar'),
                        controller: _bodyScrollController,
                        thumbVisibility: persistentScrollbar,
                        interactive: persistentScrollbar,
                        thickness: persistentScrollbar ? 8 : 4,
                        radius: const Radius.circular(8),
                        child: SingleChildScrollView(
                            key: const Key('patient-body-scroll-view'),
                            controller: _bodyScrollController,
                            padding: EdgeInsets.only(
                                right: persistentScrollbar
                                    ? AppSpacing.lg
                                    : AppSpacing.xs,
                                bottom: AppSpacing.xl),
                            child: switch (page) {
                              1 => consultationList(),
                              2 => statusPage(),
                              3 => profilePage(),
                              _ => home()
                            }));
                  }));
  }
}

String formatBrazilianPhone(String? value) {
  final number = digits(value ?? '');
  if (number.length == 11) {
    return '(${number.substring(0, 2)}) ${number.substring(2, 7)}-${number.substring(7)}';
  }
  if (number.length == 10) {
    return '(${number.substring(0, 2)}) ${number.substring(2, 6)}-${number.substring(6)}';
  }
  return value == null || value.trim().isEmpty ? 'Não informado' : value;
}

String showOnlyDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String statusLabel(String value) =>
    const {
      'agendado': 'Agendada',
      'em_espera': 'Check-in realizado',
      'em_triagem': 'Em triagem',
      'em_atendimento': 'Em atendimento',
      'concluido': 'Concluída',
      'cancelado': 'Cancelada',
      'falta': 'Falta',
    }[value] ??
    value;

class StatusTimeline extends StatelessWidget {
  const StatusTimeline({super.key, required this.status, this.compact = false});
  final String status;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    const states = [
      'agendado',
      'em_espera',
      'em_triagem',
      'em_atendimento',
      'concluido'
    ];
    if (status == 'cancelado' || status == 'falta') {
      return Row(children: [
        const Icon(Icons.info_outline),
        const SizedBox(width: 8),
        Text(statusLabel(status))
      ]);
    }
    final current = states.indexOf(status).clamp(0, states.length - 1);
    final contrast = accessibility.highContrast;
    Color colorFor(int index) => contrast
        ? (index <= current ? Colors.yellow : Colors.white54)
        : index < current
            ? green
            : index == current
                ? blue
                : const Color(0xFFB8C1CC);

    Widget marker(int index) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
            color: index <= current ? colorFor(index) : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: colorFor(index), width: 2)),
        child: Icon(index <= current ? Icons.check : Icons.circle,
            size: index <= current ? 19 : 9,
            color: index <= current
                ? (contrast ? Colors.black : Colors.white)
                : colorFor(index)));

    Widget verticalTimeline() => Column(
            children: List.generate(states.length, (index) {
          final last = index == states.length - 1;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 34,
                child: Column(children: [
                  marker(index),
                  if (!last)
                    Container(
                        width: 2,
                        height: 28,
                        color:
                            colorFor(index < current ? index : states.length))
                ])),
            const SizedBox(width: 12),
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 24),
                    child: Text(statusLabel(states[index]),
                        style: TextStyle(
                            fontWeight: index == current
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: contrast || index <= current
                                ? null
                                : Colors.black54))))
          ]);
        }));

    return Semantics(
        container: true,
        label:
            'Fluxo da consulta. Etapa atual: ${statusLabel(states[current])}',
        child: compact
            ? verticalTimeline()
            : LayoutBuilder(builder: (context, constraints) {
                if (constraints.maxWidth < 720) {
                  return verticalTimeline();
                }
                return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(states.length, (index) {
                      final last = index == states.length - 1;
                      return Expanded(
                          child: Column(children: [
                        Row(children: [
                          if (index > 0)
                            Expanded(
                                child: Container(
                                    height: 2,
                                    color: colorFor(index <= current
                                        ? index - 1
                                        : states.length))),
                          marker(index),
                          if (!last)
                            Expanded(
                                child: Container(
                                    height: 2,
                                    color: colorFor(index < current
                                        ? index
                                        : states.length))),
                        ]),
                        const SizedBox(height: 9),
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(statusLabel(states[index]),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontWeight: index == current
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: contrast || index <= current
                                        ? null
                                        : Colors.black54)))
                      ]));
                    }));
              }));
  }
}

class LegacyStaffDashboard extends StatefulWidget {
  const LegacyStaffDashboard({super.key});
  @override
  State<LegacyStaffDashboard> createState() => _LegacyStaffDashboardState();
}

class _LegacyStaffDashboardState extends State<LegacyStaffDashboard> {
  List<Map<String, dynamic>> queue = [];
  List<AdminAppointment> agenda = [];
  bool loading = true, requesting = false;
  int page = 0;
  Timer? refreshTimer;
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
    refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => load());
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (requesting || !mounted) return;
    requesting = true;
    try {
      final values = await Future.wait([
        ApiService().queue(),
        ApiService().adminAppointments(patient: search.text)
      ]);
      queue = values[0] as List<Map<String, dynamic>>;
      agenda = values[1] as List<AdminAppointment>;
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    } finally {
      requesting = false;
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> logout() async {
    refreshTimer?.cancel();
    await ApiService.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
    }
  }

  Future<void> checkIn(AdminAppointment item) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Confirmar chegada?'),
                content: Text('Confirmar a chegada de ${item.patient}?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Confirmar'))
                ]));
    if (ok != true) return;
    try {
      await ApiService().checkIn(item.id);
      await load();
      if (mounted) notice(context, 'Chegada confirmada pelo backend.');
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    }
  }

  Future<void> registerAbsence(AdminAppointment item) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Registrar falta?'),
                content: Text(
                    'Confirmar falta de ${item.patient} neste atendimento?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Voltar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Registrar falta'))
                ]));
    if (ok != true) return;
    try {
      await ApiService().registerAbsence(item.id);
      await load();
      if (mounted) notice(context, 'Falta registrada.');
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    }
  }

  Future<void> transition(AdminAppointment item, String next) async {
    String? risk, triage;
    if (next == 'em_triagem') {
      final details = await showDialog<List<String>>(
          context: context, builder: (_) => const _TriageDialog());
      if (details == null) return;
      risk = details[0];
      triage = details[1];
    }
    try {
      await ApiService()
          .changeStatus(item.id, next, risk: risk, triage: triage);
      await load();
      if (mounted) notice(context, 'Status atualizado pelo backend.');
    } on ApiException catch (e) {
      if (mounted) notice(context, e.message);
    }
  }

  Widget actionFor(AdminAppointment item) {
    final role = ApiService.session?.role;
    if (role == 'recepcao' && item.status == 'agendado') {
      return Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
            onPressed: () => checkIn(item),
            icon: const Icon(Icons.how_to_reg),
            label: const Text('Check-in')),
        OutlinedButton.icon(
            onPressed: () => registerAbsence(item),
            icon: const Icon(Icons.person_off_outlined),
            label: const Text('Registrar falta'))
      ]);
    }
    if (role == 'profissional' &&
        item.status == 'em_espera' &&
        (ApiService.session?.can('triage:write') ?? false)) {
      return FilledButton(
          onPressed: () => transition(item, 'em_triagem'),
          child: const Text('Registrar triagem'));
    }
    if (role == 'profissional' && item.status == 'em_triagem') {
      return FilledButton(
          onPressed: () => transition(item, 'em_atendimento'),
          child: const Text('Iniciar atendimento'));
    }
    if (role == 'profissional' && item.status == 'em_atendimento') {
      return FilledButton(
          onPressed: () => transition(item, 'concluido'),
          child: const Text('Concluir atendimento'));
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final professional = ApiService.session?.role == 'profissional';
    return AppPage(
        child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 76, 20, 20),
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(children: [
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(children: [
                                const BrandMark(compact: true),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(ApiService.session?.name ?? '',
                                          style: const TextStyle(
                                              fontSize: 21,
                                              fontWeight: FontWeight.w800)),
                                      Text(professional
                                          ? 'Painel do Profissional'
                                          : 'Painel da Recepção')
                                    ])),
                                IconButton(
                                    tooltip: 'Recuperar senha',
                                    onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const RecoveryPage())),
                                    icon: const Icon(Icons.password)),
                                IconButton(
                                    tooltip: 'Atualizar',
                                    onPressed: load,
                                    icon: const Icon(Icons.refresh)),
                                IconButton(
                                    tooltip: 'Sair',
                                    onPressed: logout,
                                    icon: const Icon(Icons.logout))
                              ]))),
                      const SizedBox(height: 12),
                      SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(
                                value: 0,
                                icon: Icon(Icons.today),
                                label: Text('Agenda do dia')),
                            ButtonSegment(
                                value: 1,
                                icon: Icon(Icons.groups),
                                label: Text('Fila'))
                          ],
                          selected: {
                            page
                          },
                          onSelectionChanged: (v) =>
                              setState(() => page = v.first)),
                      const SizedBox(height: 12),
                      if (!professional && page == 0) ...[
                        TextField(
                            controller: search,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                                labelText:
                                    'Buscar por paciente, CPF ou horário',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: IconButton(
                                    tooltip: 'Buscar',
                                    onPressed: load,
                                    icon: const Icon(Icons.arrow_forward))),
                            onSubmitted: (_) => load()),
                        const SizedBox(height: 12),
                      ],
                      Expanded(
                          child: loading
                              ? const Center(child: CircularProgressIndicator())
                              : page == 0
                                  ? _agendaList()
                                  : _queueList())
                    ])))));
  }

  Widget _agendaList() => agenda.isEmpty
      ? const _EmptyState(
          'Nenhum agendamento encontrado para os filtros selecionados.')
      : ListView(children: [
          for (final item in agenda)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: LayoutBuilder(builder: (_, c) {
                      final info = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${item.scheduledAt.hour.toString().padLeft(2, '0')}:${item.scheduledAt.minute.toString().padLeft(2, '0')} • ${item.patient}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            Text(
                                '${item.patientDocument} • ${specialtyDisplayName(item.specialty)} • ${item.professional}'),
                            Text(
                                'Status: ${statusLabel(item.status)} • Prioridade: ${item.legalPriority}')
                          ]);
                      final action = actionFor(item);
                      return c.maxWidth < 700
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                  info,
                                  const SizedBox(height: 10),
                                  action
                                ])
                          : Row(children: [Expanded(child: info), action]);
                    })))
        ]);

  Widget _queueList() => queue.isEmpty
      ? const _EmptyState('Não há pacientes na fila.')
      : ListView(children: [
          for (final x in queue)
            Card(
                child: ListTile(
                    leading:
                        const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(x['patient']?.toString() ?? 'Paciente'),
                    subtitle: Text(
                        '${specialtyDisplayName(x['specialty'].toString())} • ${x['professional']}\nPrioridade: ${x['legal_priority'] ?? 'geral'}'),
                    isThreeLine: true,
                    trailing: Text(statusLabel(x['status'].toString()))))
        ]);
}

class _TriageDialog extends StatefulWidget {
  const _TriageDialog();
  @override
  State<_TriageDialog> createState() => _TriageDialogState();
}

class _TriageDialogState extends State<_TriageDialog> {
  final form = GlobalKey<FormState>(),
      complaint = TextEditingController(),
      vitalSigns = TextEditingController(),
      notes = TextEditingController();
  String? risk;
  @override
  void dispose() {
    complaint.dispose();
    vitalSigns.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Registrar triagem'),
          content: Form(
              key: form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AppRiskSelector(
                    value: risk,
                    onChanged: (value) => setState(() => risk = value)),
                const SizedBox(height: 12),
                TextFormField(
                    controller: complaint,
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Informe a queixa principal.'
                        : null,
                    decoration:
                        const InputDecoration(labelText: 'Queixa principal')),
                const SizedBox(height: 12),
                TextFormField(
                    controller: vitalSigns,
                    minLines: 2,
                    maxLines: 3,
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Informe os sinais vitais aferidos.'
                        : null,
                    decoration: const InputDecoration(
                        labelText: 'Sinais vitais aferidos')),
                const SizedBox(height: 12),
                TextFormField(
                    controller: notes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        labelText: 'Observações da triagem (opcional)'))
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () {
                  if (form.currentState!.validate()) {
                    final assessment = [
                      'Queixa: ${complaint.text.trim()}',
                      'Sinais vitais: ${vitalSigns.text.trim()}',
                      if (notes.text.trim().isNotEmpty)
                        'Observações: ${notes.text.trim()}'
                    ].join('\n');
                    Navigator.pop(context, [risk!, assessment]);
                  }
                },
                child: const Text('Salvar triagem'))
          ]);
}
